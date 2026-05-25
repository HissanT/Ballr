import SwiftUI

struct LevelSevenCameraView: View {
    var body: some View {
        HandTargetCameraView(
            nextDestination: .levelEight,
            configuration: .levelSevenTimed
        )
    }
}
