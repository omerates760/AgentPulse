// Animations.swift — AgentPulse
// BlurFade transition and MorphText view for polished UI transitions

import SwiftUI

// MARK: - BlurFade Transition

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(progress: 1),
            identity: BlurFadeModifier(progress: 0)
        )
    }
}

private struct BlurFadeModifier: ViewModifier, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .blur(radius: progress * 5)
            .opacity(1 - progress)
    }
}

// MARK: - MorphText

struct MorphText: View {
    let text: String
    var font: Font = .body
    var color: Color = .white

    @State private var displayedText: String = ""
    @State private var blurRadius: CGFloat = 0

    var body: some View {
        Text(displayedText)
            .font(font)
            .foregroundColor(color)
            .blur(radius: blurRadius)
            .onAppear { displayedText = text }
            .onChange(of: text) { newValue in
                guard newValue != displayedText else { return }
                // Phase 1: blur in
                withAnimation(.easeIn(duration: 0.1)) {
                    blurRadius = 4
                }
                // Phase 2: swap text while blurred
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    displayedText = newValue
                }
                // Phase 3: blur out
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        blurRadius = 0
                    }
                }
            }
    }
}
