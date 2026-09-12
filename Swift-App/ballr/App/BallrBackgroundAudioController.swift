import AVFoundation
import Foundation

@MainActor
final class BallrBackgroundAudioController {
    static let shared = BallrBackgroundAudioController()

    private enum PlaybackState {
        case menu
        case gameplay
        case silent
    }

    private let menuResource = (name: "in-menu audio", ext: "mp3")
    private let gameplayResource = (name: "in-game audio", ext: "mp3")
    private let menuVolume: Float = 0.42
    private let gameplayCountdownVolume: Float = 0.24
    private let gameplayVolume: Float = 0.52
    private let fadeDuration: TimeInterval = 1.2

    private var menuPlayer: AVAudioPlayer?
    private var gameplayPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?
    private var currentState: PlaybackState = .silent
    private var currentGameplayVolume: Float = 0.52
    private var activeGameplayScenes = 0
    private var isSceneActive = true

    private init() {}

    func activateMenuMusic(restartTrack: Bool = false, fadeInFromZero: Bool = false) {
        guard activeGameplayScenes == 0 else { return }
        if restartTrack {
            preparePlayersIfNeeded()
            menuPlayer?.currentTime = 0
        }
        if fadeInFromZero {
            menuPlayer?.volume = 0
            gameplayPlayer?.volume = 0
        }
        transition(to: .menu)
    }

    func enterGameplayScene() {
        activeGameplayScenes += 1
        transition(to: .silent)
    }

    func startGameplayCountdownMusic() {
        guard activeGameplayScenes > 0 else { return }
        restartGameplayTrackIfNeeded()
        currentGameplayVolume = gameplayCountdownVolume
        transition(to: .gameplay)
    }

    func intensifyGameplayMusic() {
        guard activeGameplayScenes > 0 else { return }
        currentGameplayVolume = gameplayVolume
        transition(to: .gameplay)
    }

    func exitGameplayScene() {
        activeGameplayScenes = max(0, activeGameplayScenes - 1)
        if activeGameplayScenes == 0 {
            transition(to: .menu)
        }
    }

    func updateScenePhase(isActive: Bool) {
        isSceneActive = isActive
        if isActive {
            transition(to: currentState, animated: false)
        } else {
            fadeTimer?.invalidate()
            menuPlayer?.pause()
            gameplayPlayer?.pause()
        }
    }

    private func transition(to state: PlaybackState, animated: Bool = true) {
        currentState = state

        guard isSceneActive else { return }

        preparePlayersIfNeeded()
        configureAudioSession()

        let menuTargetVolume: Float = state == .menu ? menuVolume : 0
        let gameplayTargetVolume: Float = state == .gameplay ? currentGameplayVolume : 0

        if state == .menu {
            startPlaybackIfNeeded(for: menuPlayer)
        } else if state == .gameplay {
            startPlaybackIfNeeded(for: gameplayPlayer)
        }

        applyVolumes(
            menuTargetVolume: menuTargetVolume,
            gameplayTargetVolume: gameplayTargetVolume,
            animated: animated
        )
    }

    private func preparePlayersIfNeeded() {
        if menuPlayer == nil {
            menuPlayer = preparePlayer(resource: menuResource.name, fileExtension: menuResource.ext)
        }
        if gameplayPlayer == nil {
            gameplayPlayer = preparePlayer(resource: gameplayResource.name, fileExtension: gameplayResource.ext)
        }
    }

    private func preparePlayer(resource: String, fileExtension: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else {
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            return player
        } catch {
            print("Background audio failed to load for \(resource).\(fileExtension): \(error.localizedDescription)")
            return nil
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Background audio session failed to activate: \(error.localizedDescription)")
        }
    }

    private func restartGameplayTrackIfNeeded() {
        preparePlayersIfNeeded()
        gameplayPlayer?.currentTime = 0
    }

    private func startPlaybackIfNeeded(for player: AVAudioPlayer?) {
        guard let player else { return }
        if !player.isPlaying {
            player.play()
        }
    }

    private func applyVolumes(menuTargetVolume: Float, gameplayTargetVolume: Float, animated: Bool) {
        fadeTimer?.invalidate()

        guard animated else {
            menuPlayer?.volume = menuTargetVolume
            gameplayPlayer?.volume = gameplayTargetVolume
            finalizePlayback(menuTargetVolume: menuTargetVolume, gameplayTargetVolume: gameplayTargetVolume)
            return
        }

        let startMenuVolume = menuPlayer?.volume ?? 0
        let startGameplayVolume = gameplayPlayer?.volume ?? 0
        let startTime = Date()

        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(startTime)
                let progress = min(max(elapsed / self.fadeDuration, 0), 1)

                self.menuPlayer?.volume = startMenuVolume + (menuTargetVolume - startMenuVolume) * Float(progress)
                self.gameplayPlayer?.volume = startGameplayVolume + (gameplayTargetVolume - startGameplayVolume) * Float(progress)

                guard progress >= 1 else { return }
                timer.invalidate()
                self.finalizePlayback(menuTargetVolume: menuTargetVolume, gameplayTargetVolume: gameplayTargetVolume)
            }
        }
    }

    private func finalizePlayback(menuTargetVolume: Float, gameplayTargetVolume: Float) {
        if menuTargetVolume == 0 {
            menuPlayer?.pause()
        }
        if gameplayTargetVolume == 0 {
            gameplayPlayer?.pause()
        }
    }
}
