import SwiftUI

struct BallrJeffCountdownLoadingScreen: View {
    let startedAt: Date
    var scoreText: String?
    var timeText: String?

    var body: some View {
        ZStack {
            BallrDrillCountdownOverlay(startedAt: startedAt)

            BallrJeffCameraOverlay(
                presentation: .countdown(
                    startedAt: startedAt,
                    scoreText: scoreText,
                    timeText: timeText
                )
            )
            .zIndex(90)
        }
        .allowsHitTesting(false)
    }
}
