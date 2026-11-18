import AppKit
import SwiftUI

/// Mounted only while the resource disclosure is open. Sampling also pauses
/// when Sift is not the foreground application.
struct ProcessResourcesView: View {
    let isActive: Bool
    @StateObject private var monitor = ProcessResourceMonitor()
    @State private var sort: ProcessResourceSort = .cpu
    @State private var search = ""
    @State private var showAll = false
    @State private var isVisible = false
    @State private var showsReadingNotes = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let matchingConsumers = ProcessResourceMath.sorted(monitor.consumers, by: sort, search: search)
        let visibleConsumers = showAll || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? matchingConsumers : Array(matchingConsumers.prefix(8))
        return VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(SiftColor.stroke)
                .frame(height: 1)
                .accessibilityHidden(true)

            HStack(spacing: 12) {
                Text("Apps and processes")
                    .siftStyle(.cardTitle)
                if !isActive {
                    // Pausing keeps the last sample on screen under the notice.
                    SiftStatusPill(Text("Live updates paused"), tone: .neutral)
                }
                Spacer()
                SiftSegmented(selection: $sort, options: [
                    (value: ProcessResourceSort.cpu, label: Text("CPU")),
                    (value: ProcessResourceSort.memory, label: Text("Memory"))
                ])
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Sort by"))
                .accessibilityIdentifier("performance.processSort")
            }

            searchField

            if isActive && monitor.samplingFailed {
                SiftNoticeBanner(
                    Text("Process information is unavailable. Try Activity Monitor for more detail."),
                    tone: .warning
                )
            } else if isActive && monitor.consumers.isEmpty && monitor.isWarmingUp {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).tint(SiftColor.accent)
                    Text("Measuring apps and processes…")
                        .siftStyle(.label)
                }
                .padding(.vertical, 10)
            } else if visibleConsumers.isEmpty {
                if isActive || !monitor.consumers.isEmpty {
                    Text("No matching apps or processes")
                        .siftStyle(.label)
                        .padding(.vertical, 10)
                }
            } else {
                VStack(spacing: 2) {
                    SiftTableHeader {
                        Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                        Text("CPU")
                            .foregroundStyle(sort == .cpu ? SiftColor.textSecondary : SiftColor.textTertiary)
                            .frame(width: 92, alignment: .trailing)
                        Text("Memory")
                            .foregroundStyle(sort == .memory ? SiftColor.textSecondary : SiftColor.textTertiary)
                            .frame(width: 122, alignment: .trailing)
                    }
                    .padding(.horizontal, -2)

                    LazyVStack(spacing: 2) {
                        ForEach(visibleConsumers) { consumer in
                            ProcessResourceRow(consumer: consumer, icon: monitor.icon(for: consumer))
                        }
                    }
                }

                if matchingConsumers.count > 8 && search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(showAll ? String(localized: "Show top 8") : String(localized: "Show all apps and processes")) {
                        showAll.toggle()
                    }
                    .buttonStyle(.siftQuiet)
                    .accessibilityIdentifier("performance.showAllProcesses")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if isActive && monitor.isWarmingUp && !monitor.samplingFailed {
                    Text("CPU values appear after the next sample.")
                }
                if isActive && monitor.changedProcessCount > 0 {
                    Text("Some processes started or stopped since the last sample. Their values appear in the next one.")
                }
                if monitor.protectedProcessCount > 0 {
                    Text("System processes are not listed. Use Activity Monitor for those.")
                }
            }
            .font(.sift(11))
            .foregroundStyle(SiftColor.textTertiary)

            readingNotes
        }
        .onAppear {
            isVisible = true
            monitor.setActive(isActive)
        }
        .onDisappear {
            isVisible = false
            monitor.setActive(false)
        }
        .onChange(of: isActive) { active in
            monitor.setActive(isVisible && active)
        }
    }

    /// A SiftSearchField look-alike that keeps the identifier on the text field
    /// and stays off ⌘F, which belongs to the page.
    private var searchField: some View {
        HStack(spacing: 10) {
            SiftIcon.search.image(15).foregroundStyle(SiftColor.textTertiary)
            TextField(text: $search, prompt: Text("Search apps and processes").foregroundColor(SiftColor.textTertiary)) {
                Text("Search apps and processes")
            }
            .textFieldStyle(.plain)
            .font(.sift(13))
            .foregroundStyle(SiftColor.textPrimary)
            .focused($searchFocused)
            .accessibilityIdentifier("performance.processSearch")
            if !search.isEmpty {
                Button { search = "" } label: {
                    SiftIcon.x.image(13).foregroundStyle(SiftColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Capsule(style: .continuous).fill(SiftColor.control))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(searchFocused ? SiftColor.accent : SiftColor.controlStroke, lineWidth: 1)
        )
    }

    private var readingNotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(SiftMotion.quick) { showsReadingNotes.toggle() }
            } label: {
                HStack(spacing: 6) {
                    SiftIcon.chevronRight.image(11)
                        .rotationEffect(.degrees(showsReadingNotes ? 90 : 0))
                    Text("About these readings")
                }
                .font(.sift(11.5, weight: 500))
                .foregroundStyle(SiftColor.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(LocalizedStringKey(showsReadingNotes ? "Expanded" : "Collapsed")))

            if showsReadingNotes {
                VStack(alignment: .leading, spacing: 5) {
                    Text("CPU uses the Mac’s total capacity. App helpers are grouped with their app.")
                    Text("App memory shows resident memory, including shared pages. App totals can differ from the summary.")
                    Text("Memory estimate includes active, wired and compressed memory.")
                }
                .font(.sift(11))
                .foregroundStyle(SiftColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 17)
            }
        }
    }
}

/// The Performance startup-item row grammar: 52 pt, 14 pt corners, name over
/// a mono sub-line, with mono values and thin meters on the right.
private struct ProcessResourceRow: View {
    let consumer: ProcessResourceConsumer
    let icon: NSImage?
    private let memoryTotal = ProcessInfo.processInfo.physicalMemory

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: SiftRadius.tile, style: .continuous).fill(SiftColor.control))
                } else {
                    SiftIconTile(icon: .cpu, size: 32)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(consumer.name)
                    .font(.sift(12.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Group {
                    if consumer.processCount == 1 {
                        Text("1 process")
                    } else {
                        Text("\(consumer.processCount) processes")
                    }
                }
                .siftStyle(.monoSmall)
            }
            .help(consumer.applicationPath ?? consumer.name)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 5) {
                Text(cpuText)
                    .font(.siftMono(12))
                    .foregroundStyle(SiftColor.textPrimary)
                    .help(consumer.cpuIsPartial && consumer.cpuFraction != nil
                          ? String(localized: "Some of this app's processes have no CPU reading yet, so this total is partial.") : "")
                SiftMeterBar(fraction: consumer.cpuFraction ?? 0, height: 4)
                    .accessibilityHidden(true)
            }
            .frame(width: 92)

            VStack(alignment: .trailing, spacing: 5) {
                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: consumer.residentBytes), countStyle: .memory))
                    .font(.siftMono(12))
                    .foregroundStyle(SiftColor.textPrimary)
                SiftMeterBar(
                    fraction: memoryTotal > 0 ? min(1, Double(consumer.residentBytes) / Double(memoryTotal)) : 0,
                    fill: SiftColor.accentDim,
                    height: 4
                )
                .accessibilityHidden(true)
            }
            .frame(width: 122)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .siftRowBackground()
        .accessibilityElement(children: .combine)
    }

    /// A trailing plus marks a group whose CPU is the sum of its measured members only.
    private var cpuText: String {
        guard let cpu = consumer.cpuFraction else { return "—" }
        let value = cpu.formatted(.percent.precision(.fractionLength(1)))
        return consumer.cpuIsPartial ? value + "+" : value
    }
}
