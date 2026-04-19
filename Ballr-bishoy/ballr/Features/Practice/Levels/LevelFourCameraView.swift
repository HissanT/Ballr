import SwiftUI

struct LevelFourCameraView: View {
    var body: some View {
        PracticeBallTargetLevelView(configuration: .levelFour) {
            LevelFiveCameraView()
        }
    }
}
