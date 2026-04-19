import SwiftUI

struct LevelFiveCameraView: View {
    var body: some View {
        PracticeBallTargetLevelView(configuration: .levelFive) {
            LevelSixCameraView()
        }
    }
}
