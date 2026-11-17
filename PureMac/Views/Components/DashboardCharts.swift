import SwiftUI

struct SuccessMedal: View {
    var tint: Color = Tint.green
    var size: CGFloat = 120
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.11))
            Circle()
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.34, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .scaleEffect(visible ? 1 : 0.92)
        .opacity(visible ? 1 : 0)
        .onAppear {
            if reduceMotion {
                visible = true
            } else {
                withAnimation(MotionTokens.gentle) {
                    visible = true
                }
            }
        }
    }
}

struct StaggeredReveal: ViewModifier {
    let index: Int
    var baseDelay = 0.035
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.easeOut(duration: 0.28).delay(Double(index) * baseDelay)) {
                        shown = true
                    }
                }
            }
    }
}

extension View {
    func staggered(_ index: Int, baseDelay: Double = 0.035) -> some View {
        modifier(StaggeredReveal(index: index, baseDelay: baseDelay))
    }
}

struct CountUpBytes: View {
    let bytes: Int64
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .modifier(ByteRollEffect(value: shown))
            .onAppear { animate(to: bytes) }
            .onChange(of: bytes) { animate(to: $0) }
    }

    private func animate(to target: Int64) {
        if reduceMotion {
            shown = Double(target)
        } else {
            withAnimation(.easeOut(duration: 0.55)) {
                shown = Double(target)
            }
        }
    }
}

private struct ByteRollEffect: AnimatableModifier {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func body(content: Content) -> some View {
        Text(ByteCountFormatter.string(fromByteCount: Int64(max(0, value)), countStyle: .file))
            .monospacedDigit()
    }
}
