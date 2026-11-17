import SwiftUI

/// An empty or finished state: a tinted icon tile, a narrow display title, one
/// sentence of direction and an optional primary action.
struct EmptyStateView: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey
    var action: (() -> Void)?
    var actionLabel: LocalizedStringKey?
    /// Icon tint. Positive states pass a status color (e.g. success for "All
    /// clean"); neutral states keep the secondary look.
    var tint: Color?

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey,
         action: (() -> Void)? = nil, actionLabel: LocalizedStringKey? = nil, tint: Color? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.action = action
        self.actionLabel = actionLabel
        self.tint = tint
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(tint ?? SiftColor.textSecondary)
                .frame(width: 56, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.map { $0.opacity(0.14) } ?? SiftColor.control)
                )
                .accessibilityHidden(true)
                // One-shot entrance; skipped under Reduce Motion.
                .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                .opacity(appeared || reduceMotion ? 1 : 0)

            VStack(spacing: 6) {
                Text(title)
                    .font(.siftDisplay(26))
                    .tracking(-0.4)
                    .foregroundStyle(SiftColor.textPrimary)
                    .multilineTextAlignment(.center)
                Text(description)
                    .siftStyle(.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action, let label = actionLabel {
                Button(action: action) { Text(label) }
                    .buttonStyle(.siftPrimary)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(SiftMotion.snappy) { appeared = true }
        }
    }
}
