import SwiftUI

struct BallrAppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        backgroundColor
        .ignoresSafeArea()
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .ballrDarkModeBackground : .ballrLightModeBackground
    }
}

extension Color {
    static let ballrDarkModeBackground = Color(
        red: 18.0 / 255.0,
        green: 20.0 / 255.0,
        blue: 28.0 / 255.0
    )

    static let ballrLightModeBackground = Color(
        red: 245.0 / 255.0,
        green: 240.0 / 255.0,
        blue: 232.0 / 255.0
    )
}
