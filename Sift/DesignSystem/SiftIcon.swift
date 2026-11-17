import AppKit
import SwiftUI

/// The design draws with lucide icons; the app renders the nearest SF Symbol.
/// Each case is named after its lucide icon so a design layer maps 1:1.
enum SiftIcon: String {
    case activity, apple, arrowDown, arrowDownWideNarrow, batteryCharging, bookmarkPlus
    case calendarClock, chartPie, check, chevronDown, chevronRight, codeXml, copy, cpu
    case disc3, download, file, fileArchive, flaskConical, folder, folderOpen, hardDrive
    case history, images, info, layoutGrid, lockKeyhole, mail, memoryStick, package
    case packageMinus, palette, plus, power, rotateCw, scanSearch, search, settings
    case shieldCheck, slidersHorizontal, sparkles, trash, trash2, triangleAlert, x
    // Screens without a design reuse the same vocabulary.
    case appWindow, refresh, photo, user, bell, globe, terminal, externalLink

    var symbol: String {
        switch self {
        case .activity: return "waveform.path.ecg"
        case .apple: return "applelogo"
        case .arrowDown: return "arrow.down"
        case .arrowDownWideNarrow: return "arrow.up.arrow.down"
        case .batteryCharging: return "battery.100.bolt"
        case .bookmarkPlus: return "bookmark"
        case .calendarClock: return "calendar.badge.clock"
        case .chartPie: return "chart.pie"
        case .check: return "checkmark"
        case .chevronDown: return "chevron.down"
        case .chevronRight: return "chevron.right"
        case .codeXml: return "chevron.left.forwardslash.chevron.right"
        case .copy: return "doc.on.doc"
        case .cpu: return "cpu"
        case .disc3: return "opticaldisc"
        case .download: return "arrow.down.to.line"
        case .file: return "doc"
        case .fileArchive: return "doc.zipper"
        case .flaskConical: return "testtube.2"
        case .folder: return "folder"
        case .folderOpen: return "folder"
        case .hardDrive: return "internaldrive"
        case .history: return "clock.arrow.circlepath"
        case .images: return "photo.on.rectangle"
        case .info: return "info.circle"
        case .layoutGrid: return "square.grid.2x2"
        case .lockKeyhole: return "lock"
        case .mail: return "envelope"
        case .memoryStick: return "memorychip"
        case .package: return "shippingbox"
        case .packageMinus: return "shippingbox.and.arrow.backward"
        case .palette: return "paintpalette"
        case .plus: return "plus"
        case .power: return "power"
        case .rotateCw: return "arrow.clockwise"
        case .scanSearch: return "viewfinder"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        case .shieldCheck: return "checkmark.shield"
        case .slidersHorizontal: return "slider.horizontal.3"
        case .sparkles: return "sparkles"
        case .trash: return "trash"
        case .trash2: return "trash"
        case .triangleAlert: return "exclamationmark.triangle"
        case .x: return "xmark"
        case .appWindow: return "macwindow"
        case .refresh: return "arrow.triangle.2.circlepath"
        case .photo: return "photo"
        case .user: return "person"
        case .bell: return "bell"
        case .globe: return "globe"
        case .terminal: return "terminal"
        case .externalLink: return "arrow.up.right.square"
        }
    }

    private static func available(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// The icon at the design's point size. Lucide's 2 px stroke reads closest
    /// to SF Symbols at regular weight.
    func image(_ size: CGFloat = 16) -> some View {
        Image(systemName: Self.available(symbol) ? symbol : "circle")
            .font(.system(size: size * 0.9, weight: .regular))
            .frame(width: size, height: size)
    }
}
