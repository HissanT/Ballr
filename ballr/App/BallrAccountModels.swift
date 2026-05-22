import Foundation

struct BallrUserProfile: Codable, Equatable {
    let id: UUID
    let username: String?
    let age: Int?
    let preferredPosition: String?
    let preferredFoot: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case age
        case preferredPosition = "preferred_position"
        case preferredFoot = "preferred_foot"
    }

    var shownName: String {
        if let username, !username.isEmpty {
            return username
        }

        return "Player"
    }

    var isComplete: Bool {
        guard let username, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return age != nil && preferredPosition != nil && preferredFoot != nil
    }
}

struct BallrUserProgress: Codable, Equatable {
    let userID: UUID
    let level: Int
    let xp: Int
    let streakCount: Int?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case level
        case xp
        case streakCount = "streak_count"
    }

    static func empty(for userID: UUID) -> BallrUserProgress {
        BallrUserProgress(userID: userID, level: 1, xp: 0, streakCount: 0)
    }
}

struct BallrLevelUpEvent: Identifiable, Equatable {
    let id = UUID()
    let previousLevel: Int
    let newLevel: Int
    let xpAward: Int
}

struct BallrProfileBootstrapRequest: Codable {
    let id: UUID
}

struct BallrProgressBootstrapRequest: Codable {
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
    }
}

struct BallrProfileNameUpdateRequest: Codable {
    let username: String
}

struct BallrProgressStreakUpdateRequest: Codable {
    let streakCount: Int

    enum CodingKeys: String, CodingKey {
        case streakCount = "streak_count"
    }
}

struct BallrProgressScoreUpdateRequest: Codable {
    let level: Int
    let xp: Int
}

struct BallrProfileUpdateRequest: Codable {
    let username: String
    let age: Int
    let preferredPosition: String
    let preferredFoot: String

    enum CodingKeys: String, CodingKey {
        case username
        case age
        case preferredPosition = "preferred_position"
        case preferredFoot = "preferred_foot"
    }
}
