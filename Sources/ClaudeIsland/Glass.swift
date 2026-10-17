import SwiftUI

/// Liquid Glass via the system API, so it follows the user's macOS settings
/// (Appearance > Liquid Glass Clear/Tinted, Reduce Transparency, light/dark).
/// Falls back to a plain material before macOS 26.
extension View {
    @ViewBuilder
    func islandGlass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint { self.glassEffect(.regular.tint(tint), in: shape) }
            else { self.glassEffect(.regular, in: shape) }
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay { if let tint { shape.fill(tint) } }
        }
    }

    @ViewBuilder
    func islandButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
}
