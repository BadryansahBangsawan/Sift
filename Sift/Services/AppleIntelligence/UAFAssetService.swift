import Foundation

/// What the asset service answered to a reset request.
enum AppleAssetResetOutcome: Equatable {
    case done
    case locked
    case noAnswer
    case failed(String)

    var explanation: String {
        switch self {
        case .done: return ""
        case .locked:
            return String(localized: "macOS is still using these models, so it wouldn't delete them yet. Restart your Mac, then try again.")
        case .noAnswer:
            return String(localized: "The asset service did not answer in time.")
        case .failed(let reason):
            return reason
        }
    }
}

/// Apple's Unified Asset Framework, behind a seam so tests never touch it.
protocol AppleAssetServicing {
    /// Whether the framework and the catalog lookup answered at run time.
    var isAvailable: Bool { get }
    func assetType(for set: String) -> String?
    /// Bytes of present assets by asset type.
    func inventory() -> [String: Int64]?
    /// Bytes on disk for a set, or nil when the service does not say.
    func downloadedBytes(for set: String) -> Int64?
    /// Removes the downloaded models of these sets. An empty list must be
    /// refused: the service reads a missing list as "every set".
    func reset(sets: [String]) -> AppleAssetResetOutcome
}

enum AppleAssetError: LocalizedError, Equatable {
    case emptySelection
    case unavailable

    var errorDescription: String? {
        switch self {
        case .emptySelection: return String(localized: "No model sets were selected, so nothing was asked of the asset service.")
        case .unavailable: return String(localized: "Apple's asset service is not available on this macOS, so models can't be removed here.")
        }
    }
}

enum AppleAssetReset {
    /// Fails closed: an empty list would be read as every set.
    static func validate(_ sets: [String]) throws {
        guard !sets.isEmpty else { throw AppleAssetError.emptySelection }
    }
}

enum AppleAssetInventory {
    /// Bytes of present assets by asset type, from the service's inventory.
    static func parse(_ info: [String: Any]) -> [String: Int64] {
        var bytes: [String: Int64] = [:]
        for asset in info["SystemAssets"] as? [[String: Any]] ?? [] {
            guard asset["isPresentOnDevice"] as? Bool == true,
                  let metadata = asset["metadata"] as? [String: Any],
                  let type = metadata["AssetType"] as? String
            else { continue }
            let size = metadata["com.apple.UnifiedAssetFramework.UnarchivedSize"]
                ?? metadata["_UnarchivedSize"]
            bytes[type, default: 0] += Int64("\(size ?? 0)") ?? 0
        }
        return bytes
    }
}

/// The real asset service. Every lookup is dynamic and fails closed: a missing
/// framework, class or selector means "not available", never a guess.
final class UAFAssetService: AppleAssetServicing {
    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/UnifiedAssetFramework.framework/UnifiedAssetFramework"
    private static let serviceName = "com.apple.siri.uaf.subscription.service"

    private let handle: UnsafeMutableRawPointer?
    private var cachedInventory: (at: Date, value: [String: Int64]?)?

    init() {
        handle = dlopen(Self.frameworkPath, RTLD_NOW)
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    var isAvailable: Bool {
        handle != nil && assetType(for: AppleIntelligenceCatalog.foundationModels) != nil
    }

    func assetType(for set: String) -> String? {
        guard let managerClass = NSClassFromString("UAFConfigurationManager") as AnyObject?,
              let manager = callClassMethod(managerClass, "defaultManager"),
              responds(manager, "getAssetSet:"),
              let assetSet = call(manager, "getAssetSet:", set),
              responds(assetSet, "autoAssetType"),
              let type = call(assetSet, "autoAssetType") as? String
        else { return nil }
        return type
    }

    func inventory() -> [String: Int64]? {
        if let cached = cachedInventory, Date().timeIntervalSince(cached.at) < 1 {
            return cached.value
        }
        let value: [String: Int64]?
        if let manager = NSClassFromString("UAFAssetSetManager") as AnyObject?,
           responds(manager, "generateInformationWithError:"),
           let raw = call(manager, "generateInformationWithError:", nil) {
            let information: Any?
            if let string = raw as? String {
                information = try? JSONSerialization.jsonObject(
                    with: Data(string.utf8), options: [])
            } else {
                information = raw
            }
            value = (information as? [String: Any]).map(AppleAssetInventory.parse)
        } else {
            value = nil
        }
        cachedInventory = (Date(), value)
        return value
    }

    func downloadedBytes(for set: String) -> Int64? {
        if let model = AppleIntelligenceCatalog.modelSet(set), let inventory = inventory() {
            return inventory[model.assetType] ?? 0
        }
        guard let manager = NSClassFromString("UAFAutoAssetManager") as AnyObject?,
              responds(manager, "latestStatusForClients:error:"),
              let status = call(manager, "latestStatusForClients:", set),
              responds(status, "downloadedFilesystemBytes")
        else { return nil }
        return int64(status, "downloadedFilesystemBytes")
    }

    func reset(sets: [String]) -> AppleAssetResetOutcome {
        guard !sets.isEmpty else { return .failed(AppleAssetError.emptySelection.localizedDescription) }
        guard let interfaceClass = NSClassFromString("UAFXPCProxyServiceInterface") as AnyObject?,
              let interface = callClassMethod(interfaceClass, "defaultInterface") as? NSXPCInterface
        else { return .failed(AppleAssetError.unavailable.localizedDescription) }

        let interfaceProtocol = interface.perform(NSSelectorFromString("protocol"))?
            .takeUnretainedValue() as? Protocol
        let connection = NSXPCConnection(machServiceName: Self.serviceName, options: [])
        connection.remoteObjectInterface = interface
        connection.resume()
        defer { connection.invalidate() }

        let finished = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var answered = false
        var result: AppleAssetResetOutcome = .noAnswer

        func finish(_ outcome: AppleAssetResetOutcome) {
            lock.lock()
            let first = !answered
            if first { answered = true; result = outcome }
            lock.unlock()
            if first { finished.signal() }
        }

        guard let proxy = remoteProxy(of: connection, onError: { error in
            finish(.failed(error.localizedDescription))
        }) else {
            return .failed(AppleAssetError.unavailable.localizedDescription)
        }

        let configuration: NSDictionary = [
            "Operation": "ResetAssetSets",
            "AssetSets": sets,
        ]
        guard sendOperation(to: proxy, protocolObject: interfaceProtocol, configuration: configuration, completion: { error in
            if let error {
                finish(Self.isLocked(error) ? .locked : .failed(
                    "\(error.localizedDescription) (\(error.domain) \(error.code))"))
            } else {
                finish(.done)
            }
        }) else {
            return .failed(AppleAssetError.unavailable.localizedDescription)
        }

        if finished.wait(timeout: .now() + 120) != .success { return .noAnswer }
        return result
    }

    /// The asset service refuses while something on the Mac holds the set.
    static func isLocked(_ error: NSError) -> Bool {
        error.userInfo["currentLockUsage"] != nil
            || error.localizedDescription.contains("current locks")
    }

    // MARK: dynamic dispatch

    private func responds(_ object: AnyObject, _ selector: String) -> Bool {
        object.responds(to: NSSelectorFromString(selector))
    }

    private func callClassMethod(_ object: AnyObject, _ selector: String) -> AnyObject? {
        guard responds(object, selector) else { return nil }
        return object.perform(NSSelectorFromString(selector))?.takeUnretainedValue()
    }

    private func call(_ object: AnyObject, _ selector: String, _ argument: Any? = nil) -> AnyObject? {
        guard responds(object, selector) else { return nil }
        let name = NSSelectorFromString(selector)
        guard let result = object.perform(name, with: argument) else { return nil }
        return result.takeUnretainedValue()
    }

    private func int64(_ object: AnyObject, _ selector: String) -> Int64? {
        let name = NSSelectorFromString(selector)
        guard responds(object, selector) else { return nil }
        typealias Value = @convention(c) (AnyObject, Selector) -> Int64
        let implementation = unsafeBitCast(object.method(for: name), to: Value.self)
        return implementation(object, name)
    }

    private func remoteProxy(
        of connection: NSXPCConnection, onError: @escaping (NSError) -> Void
    ) -> AnyObject? {
        let selector = NSSelectorFromString("remoteObjectProxyWithErrorHandler:")
        guard connection.responds(to: selector) else { return nil }
        typealias Proxy = @convention(c)
            (AnyObject, Selector, @convention(block) (NSError) -> Void) -> AnyObject
        let implementation = unsafeBitCast(connection.method(for: selector), to: Proxy.self)
        return implementation(connection, selector, onError)
    }

    /// A proxy answers every selector, so the interface is asked whether it
    /// carries the operation the reset needs.
    private func sendOperation(
        to proxy: AnyObject, protocolObject: Protocol?, configuration: NSDictionary,
        completion: @escaping (NSError?) -> Void
    ) -> Bool {
        let selector = NSSelectorFromString("operationWithConfig:completion:")
        guard let protocolObject,
              protocol_getMethodDescription(protocolObject, selector, true, true).name != nil
                || protocol_getMethodDescription(protocolObject, selector, false, true).name != nil
        else { return false }
        typealias Operation = @convention(c)
            (AnyObject, Selector, NSDictionary, @convention(block) (NSError?) -> Void) -> Void
        let implementation = unsafeBitCast(proxy.method(for: selector), to: Operation.self)
        implementation(proxy, selector, configuration, completion)
        return true
    }

}
