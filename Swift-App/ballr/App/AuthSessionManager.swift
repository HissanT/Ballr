import Foundation
import Combine
import Supabase

@MainActor
final class AuthSessionManager: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingAccount = false
    @Published private(set) var isWorking = false
    @Published private(set) var profile: BallrUserProfile?
    @Published private(set) var progress: BallrUserProgress?
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published private(set) var levelUpEvent: BallrLevelUpEvent?

    private var authStateTask: Task<Void, Never>?

    var isSignedIn: Bool {
        session != nil
    }

    var accountLabel: String {
        "Level \(level)"
    }

    var profileName: String {
        profile?.shownName ?? "Player"
    }

    var xp: Int {
        progress?.xp ?? 0
    }

    var level: Int {
        max(progress?.level ?? 1, Self.level(forXP: xp))
    }

    var streakCount: Int {
        progress?.streakCount ?? 0
    }

    var needsProfileSetup: Bool {
        session != nil && !isLoadingAccount && profile?.isComplete != true
    }

    init() {
        authStateTask = Task { [weak self] in
            for await (event, session) in BallrSupabase.client.auth.authStateChanges {
                guard let self else { return }

                switch event {
                case .initialSession, .signedIn, .signedOut, .tokenRefreshed, .userUpdated:
                    self.session = session
                    self.isLoading = false
                    await self.refreshAccountData()
                default:
                    break
                }
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    func signInAsGuest() async {
        await runAuthAction {
            try await BallrSupabase.client.auth.signInAnonymously()
        }
    }

    func signOut() async {
        await runAuthAction {
            try await BallrSupabase.client.auth.signOut()
        }
    }

    func clearAccountMessages() {
        errorMessage = nil
        noticeMessage = nil
    }

    func dismissLevelUpEvent() {
        levelUpEvent = nil
    }

    func completeProfile(
        username: String,
        age: Int,
        preferredPosition: String,
        preferredFoot: String
    ) async {
        guard let userID = session?.user.id else { return }

        let cleanedUsername = sanitizedUsername(username)

        guard cleanedUsername.count >= 3 else {
            errorMessage = "Username must be at least 3 characters."
            return
        }

        guard (1...99).contains(age) else {
            errorMessage = "Enter a valid player age."
            return
        }

        await runAuthAction {
            let updateRequest = BallrProfileUpdateRequest(
                username: cleanedUsername,
                age: age,
                preferredPosition: preferredPosition,
                preferredFoot: preferredFoot
            )

            try await BallrSupabase.client
                .from("profiles")
                .update(updateRequest)
                .eq("id", value: userID)
                .execute()

            await refreshAccountData()
        }
    }

    func updateUsername(_ username: String) async {
        guard let userID = session?.user.id else { return }

        let cleanedUsername = sanitizedUsername(username)

        guard cleanedUsername.count >= 3 else {
            errorMessage = "Username must be at least 3 characters."
            return
        }

        if cleanedUsername == profile?.username {
            noticeMessage = "Name is already up to date."
            return
        }

        await runAuthAction {
            try await BallrSupabase.client
                .from("profiles")
                .update(BallrProfileNameUpdateRequest(username: cleanedUsername))
                .eq("id", value: userID)
                .execute()

            await refreshAccountData()
            noticeMessage = "Name updated."
        }
    }

    func updateDailyStreakCount(_ streakCount: Int) async {
        guard let userID = session?.user.id else { return }

        let normalizedStreak = max(0, streakCount)

        do {
            try await BallrSupabase.client
                .from("user_progress")
                .update(BallrProgressStreakUpdateRequest(streakCount: normalizedStreak))
                .eq("user_id", value: userID)
                .execute()

            if let progress {
                self.progress = BallrUserProgress(
                    userID: progress.userID,
                    level: progress.level,
                    xp: progress.xp,
                    streakCount: normalizedStreak
                )
            } else {
                progress = BallrUserProgress(
                    userID: userID,
                    level: 1,
                    xp: 0,
                    streakCount: normalizedStreak
                )
            }
        } catch {
            debugPrint("Ballr streak update failed:", error)
            errorMessage = error.localizedDescription
        }
    }

    func awardSuccessfulDrillCompletion(xpAward: Int = 50) async {
        guard let userID = session?.user.id else { return }

        let normalizedAward = max(xpAward, 0)
        let currentProgress = progress ?? BallrUserProgress.empty(for: userID)
        let previousXP = max(currentProgress.xp, 0)
        let previousLevel = max(currentProgress.level, Self.level(forXP: previousXP))
        let updatedXP = previousXP + normalizedAward
        let updatedLevel = Self.level(forXP: updatedXP)

        do {
            try await BallrSupabase.client
                .from("user_progress")
                .update(BallrProgressScoreUpdateRequest(level: updatedLevel, xp: updatedXP))
                .eq("user_id", value: userID)
                .execute()

            progress = BallrUserProgress(
                userID: currentProgress.userID,
                level: updatedLevel,
                xp: updatedXP,
                streakCount: currentProgress.streakCount
            )

            if updatedLevel > previousLevel {
                levelUpEvent = BallrLevelUpEvent(
                    previousLevel: previousLevel,
                    newLevel: updatedLevel,
                    xpAward: normalizedAward
                )
            }
        } catch {
            debugPrint("Ballr XP update failed:", error)
            errorMessage = error.localizedDescription
        }
    }

    func refreshAccountData() async {
        guard let userID = session?.user.id else {
            profile = nil
            progress = nil
            isLoadingAccount = false
            return
        }

        isLoadingAccount = true

        do {
            try await bootstrapAccountRows(for: userID)

            let loadedProfile: BallrUserProfile = try await BallrSupabase.client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value

            let loadedProgress: BallrUserProgress = try await BallrSupabase.client
                .from("user_progress")
                .select()
                .eq("user_id", value: userID)
                .single()
                .execute()
                .value

            profile = loadedProfile
            progress = loadedProgress
        } catch {
            profile = nil
            progress = BallrUserProgress.empty(for: userID)
            debugPrint("Ballr account load failed:", error)
            errorMessage = "Could not load your profile. Make sure the latest Supabase SQL has been run."
        }

        isLoadingAccount = false
    }

    private func bootstrapAccountRows(for userID: UUID) async throws {
        try await BallrSupabase.client
            .from("profiles")
            .upsert(
                BallrProfileBootstrapRequest(id: userID),
                onConflict: "id"
            )
            .execute()

        try await BallrSupabase.client
            .from("user_progress")
            .upsert(
                BallrProgressBootstrapRequest(userID: userID),
                onConflict: "user_id"
            )
            .execute()
    }

    private func sanitizedUsername(_ username: String) -> String {
        username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func level(forXP xp: Int) -> Int {
        max(1, xp / 100 + 1)
    }

    private func runAuthAction(_ action: () async throws -> Void) async {
        errorMessage = nil
        noticeMessage = nil
        isWorking = true

        do {
            try await action()
        } catch {
            errorMessage = error.localizedDescription
        }

        isWorking = false
    }
}
