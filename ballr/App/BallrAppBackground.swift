import SwiftUI

struct BallrAppBackground: View {
    @AppStorage("ballrDarkModeEnabled") private var isDarkModeEnabled = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                isDarkModeEnabled ? Color.black : Color.white

                Image(isDarkModeEnabled ? "DarkMode" : "WhiteMode")
                    .resizable()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .ignoresSafeArea()
    }
}
