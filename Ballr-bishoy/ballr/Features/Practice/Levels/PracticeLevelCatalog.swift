import SwiftUI

enum PracticeLevel: Int, CaseIterable, Identifiable, Hashable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
    case six = 6
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case eleven = 11
    case twelve = 12
    case thirteen = 13
    case fourteen = 14
    case fifteen = 15
    case sixteen = 16
    case seventeen = 17
    case eighteen = 18
    case nineteen = 19
    case twenty = 20

    var id: Int {
        rawValue
    }

    init?(levelNumber: Int) {
        self.init(rawValue: levelNumber)
    }

    var title: String {
        "Level \(rawValue)"
    }

    var subtitle: String {
        switch self {
        case .one:
            return "Ball Basics"
        case .two:
            return "Hand Targets"
        case .three:
            return "Foot Targets"
        case .four:
            return "Ball Targets"
        case .five:
            return "Timed Targets"
        case .six:
            return "Bomb Targets"
        case .seven:
            return "Timed Hand Targets"
        case .eight:
            return "Timed Foot Targets"
        case .nine:
            return "Combo Targets"
        case .ten:
            return "Timed Targets 45%"
        case .eleven, .fifteen:
            return "First Touch"
        case .twelve, .sixteen:
            return "Dribble Tiles"
        case .thirteen, .seventeen:
            return "Juggling"
        case .fourteen, .eighteen:
            return "Dribbling"
        case .nineteen:
            return "Ball Blast"
        case .twenty:
            return "The Hunter"
        }
    }

    @ViewBuilder
    func destinationView() -> some View {
        switch self {
        case .one:
            LevelOneCameraView()
                .navigationBarBackButtonHidden(true)
        case .two:
            LevelTwoCameraView()
                .navigationBarBackButtonHidden(true)
        case .three:
            LevelThreeCameraView()
                .navigationBarBackButtonHidden(true)
        case .four:
            LevelFourCameraView()
                .navigationBarBackButtonHidden(true)
        case .five:
            LevelFiveCameraView()
                .navigationBarBackButtonHidden(true)
        case .six:
            LevelSixCameraView()
                .navigationBarBackButtonHidden(true)
        case .seven:
            LevelSevenCameraView()
                .navigationBarBackButtonHidden(true)
        case .eight:
            LevelEightCameraView()
                .navigationBarBackButtonHidden(true)
        case .nine:
            LevelNineCameraView()
                .navigationBarBackButtonHidden(true)
        case .ten:
            LevelTenCameraView()
                .navigationBarBackButtonHidden(true)
        case .nineteen:
            LevelNineteenCameraView()
                .navigationBarBackButtonHidden(true)
        case .twenty:
            LevelTwentyCameraView()
                .navigationBarBackButtonHidden(true)
        case .eleven, .twelve, .thirteen, .fourteen, .fifteen, .sixteen, .seventeen, .eighteen:
            PracticeLevelPlaceholderView(level: rawValue)
        }
    }
}
