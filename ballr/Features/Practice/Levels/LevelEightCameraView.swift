import SwiftUI

struct LevelEightCameraView: View {
    var body: some View {
        FootTargetCameraView(
            nextDestination: .levelNine,
            configuration: .levelEightTimed
        )
    }
}
