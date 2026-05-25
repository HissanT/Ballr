import Foundation
import SwiftUI
import UIKit

struct DribblingCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                .ignoresSafeArea()

            BallTrackerDetectionOverlay(cameraController: cameraController)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomInstruction
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if cameraController.isStarting {
                DribblingLoadingOverlay()
            }

            if let errorMessage = cameraController.errorMessage {
                DribblingErrorOverlay(
                    message: errorMessage,
                    permissionDenied: cameraController.permissionDenied,
                    onDismiss: { dismiss() }
                )
            }
        }
        .statusBarHidden(true)
        .onAppear {
            BallrOrientationController.lockDribblingLandscape()
            cameraController.start()
        }
        .onDisappear {
            cameraController.stop()
            BallrOrientationController.restoreDefaultOrientation()
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.65), in: Circle())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Text("DRIBBLING")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    DribblingHudChip(
                        title: cameraController.overlayState.statusText,
                        value: cameraController.overlayState.isTracking ? "LIVE" : "SCAN",
                        tint: cameraController.overlayState.isTracking ? .green : .orange
                    )
                    DribblingHudChip(
                        title: "BALL",
                        value: confidenceText,
                        tint: .yellow
                    )
                    DribblingHudChip(
                        title: "CANDS",
                        value: "\(cameraController.overlayState.candidateCount)",
                        tint: .white
                    )
                }
            }
        }
    }

    private var bottomInstruction: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tracking Only")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Place the phone sideways and keep the ball in frame.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 18))
    }

    private var confidenceText: String {
        guard let confidence = cameraController.overlayState.confidence else {
            return "--"
        }

        return String(format: "%.2f", confidence)
    }
}

private struct BallTrackerDetectionOverlay: View {
    @ObservedObject var cameraController: BallTrackerCameraController

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                if
                    let normalizedRect = cameraController.overlayState.normalizedRect,
                    let displayRect = cameraController.displayRect(for: normalizedRect)
                {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: displayRect.width, height: displayRect.height)
                        .position(x: displayRect.midX, y: displayRect.midY)
                        .shadow(color: .black.opacity(0.42), radius: 8, x: 0, y: 0)

                    Circle()
                        .fill(Color.orange)
                        .frame(width: 12, height: 12)
                        .position(x: displayRect.midX, y: displayRect.midY)

                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.7))
                        .frame(width: 110, height: 36)
                        .overlay {
                            Text(cameraController.overlayState.statusText.uppercased())
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .position(
                            x: max(displayRect.midX, 70),
                            y: max(displayRect.minY - 24, 30)
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct DribblingHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.82), lineWidth: 1.5)
        )
    }
}

private struct DribblingLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)

                Text("Starting camera and tracker...")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct DribblingErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Camera Unavailable")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button(action: onDismiss) {
                        Text("CLOSE")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.12), in: Capsule())
                    }

                    if permissionDenied {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            UIApplication.shared.open(url)
                        } label: {
                            Text("OPEN SETTINGS")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.yellow, in: Capsule())
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 24)
        }
    }
}
