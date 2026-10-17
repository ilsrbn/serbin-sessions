import SwiftUI

/// Flat black, like the hardware notch it grows out of. No glass, no material.
enum Theme {
    static let bg = Color.black
    static let raised = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.10)
    /// The one attention color: something needs you. Everything else stays neutral.
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.22)
}

struct IslandButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(prominent ? Color.white : Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension View {
    func islandButton(prominent: Bool = false) -> some View {
        buttonStyle(IslandButtonStyle(prominent: prominent))
    }
}
