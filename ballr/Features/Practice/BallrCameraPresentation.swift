import SwiftUI

struct BallrCameraPresentationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .statusBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    }
}

extension View {
    func ballrCameraPresentationChrome() -> some View {
        modifier(BallrCameraPresentationModifier())
    }
}
