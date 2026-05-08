import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject private var authSession: AuthSessionManager

    var body: some View {
        Group {
            if authSession.isLoading {
                AuthLoadingView()
            } else if authSession.needsProfileSetup {
                BallrProfileSetupView()
            } else if authSession.isSignedIn {
                ContentView()
            } else {
                BallrAuthView()
            }
        }
        .font(.ballr(size: 16, weight: .regular))
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: authSession.isLoading)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: authSession.isSignedIn)
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: authSession.needsProfileSetup)
    }
}

private struct AuthLoadingView: View {
    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.10, blue: 0.11)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                AuthMapIcon()
                    .frame(width: 108, height: 78)

                ProgressView()
                    .tint(Color.yellow)
            }
        }
    }
}

private struct BallrAuthView: View {
    @EnvironmentObject private var authSession: AuthSessionManager

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.10, blue: 0.11)
                .ignoresSafeArea()

            AuthFieldBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        AuthMapIcon()
                            .frame(width: 112, height: 80)

                        AuthWordmark(size: 54)

                        Text("BUILD YOUR PLAYER PROFILE")
                            .font(.ballr(size: 16, weight: .black))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 48)

                    if let message = authSession.errorMessage {
                        AuthStatusCard(message: message, color: Color.orange)
                    }

                    if let message = authSession.noticeMessage {
                        AuthStatusCard(message: message, color: Color.yellow)
                    }

                    VStack(spacing: 12) {
                        AuthProviderButton(
                            title: authSession.isWorking ? "STARTING..." : "START AS PLAYER",
                            systemImage: "figure.soccer",
                            background: Color.yellow,
                            foreground: Color(red: 0.08, green: 0.08, blue: 0.08)
                        ) {
                            Task {
                                await authSession.signInAsGuest()
                            }
                        }
                    }
                    .disabled(authSession.isWorking)
                    .opacity(authSession.isWorking ? 0.58 : 1.0)

                    Text("No email needed. Your player data is saved to this app profile.")
                        .font(.ballr(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.36))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 42)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private struct AuthProviderButton: View {
    let title: String
    let systemImage: String
    let background: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.ballr(size: 20, weight: .black))
                    .frame(width: 28)

                Text(title)
                    .font(.ballr(size: 15, weight: .black))
                    .tracking(1.3)

                Spacer()
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.12), lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct BallrProfileSetupView: View {
    @EnvironmentObject private var authSession: AuthSessionManager
    @State private var username = ""
    @State private var age = 10
    @State private var preferredPosition = "ST"
    @State private var preferredFoot = "Right"
    @FocusState private var focusedField: ProfileSetupField?

    private var canSave: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && !authSession.isWorking
    }

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.10, blue: 0.11)
                .ignoresSafeArea()

            AuthFieldBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AuthMapIcon()
                        .frame(width: 112, height: 80)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("SET UP YOUR PLAYER")
                            .font(.ballr(size: 34, weight: .black))
                            .foregroundStyle(Color.yellow)

                        Text("Choose the player details that will be saved in your Ballr profile.")
                            .font(.ballr(size: 15, weight: .bold))
                            .foregroundStyle(.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    AuthTextField(
                        title: "USERNAME",
                        text: $username,
                        focusedField: $focusedField,
                        field: .username,
                        contentType: .username,
                        keyboardType: .default,
                        submitLabel: .done
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("AGE")
                            .font(.ballr(size: 12, weight: .black))
                            .tracking(2)
                            .foregroundStyle(Color.yellow.opacity(0.72))

                        Picker("Age", selection: $age) {
                            ForEach(1...99, id: \.self) { value in
                                Text("\(value)")
                                    .font(.ballr(size: 24, weight: .black))
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 176)
                        .clipped()
                        .background(Color.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.yellow.opacity(0.22), lineWidth: 1.5)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("PREFERRED POSITION")
                            .font(.ballr(size: 12, weight: .black))
                            .tracking(2)
                            .foregroundStyle(Color.yellow.opacity(0.72))

                        SoccerFormationPicker(selectedPosition: $preferredPosition)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("PREFERRED FOOT")
                            .font(.ballr(size: 12, weight: .black))
                            .tracking(2)
                            .foregroundStyle(Color.yellow.opacity(0.72))

                        HStack(spacing: 12) {
                            FootChoiceButton(title: "RIGHT", isSelected: preferredFoot == "Right") {
                                preferredFoot = "Right"
                            }

                            FootChoiceButton(title: "LEFT", isSelected: preferredFoot == "Left") {
                                preferredFoot = "Left"
                            }
                        }
                    }

                    if let message = authSession.errorMessage {
                        AuthStatusCard(message: message, color: Color.orange)
                    }

                    Button {
                        Task {
                            await authSession.completeProfile(
                                username: username,
                                age: age,
                                preferredPosition: preferredPosition,
                                preferredFoot: preferredFoot
                            )
                        }
                    } label: {
                        HStack {
                            Text("SAVE PLAYER")
                                .font(.ballr(size: 22, weight: .black))
                                .tracking(2)

                            Spacer()

                            if authSession.isWorking {
                                ProgressView()
                                    .tint(Color(red: 0.08, green: 0.08, blue: 0.08))
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.ballr(size: 20, weight: .black))
                            }
                        }
                        .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                        .padding(.horizontal, 22)
                        .frame(height: 68)
                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.78, green: 0.64, blue: 0.0))
                                .frame(height: 7)
                                .offset(y: 4)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .opacity(canSave ? 1.0 : 0.48)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 26)
                .padding(.top, 46)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

private enum ProfileSetupField {
    case username
}

private struct SoccerFormationPicker: View {
    @Binding var selectedPosition: String

    private let positions: [FormationPosition] = [
        FormationPosition(code: "GK", x: 0.50, y: 0.88),
        FormationPosition(code: "LB", x: 0.18, y: 0.68),
        FormationPosition(code: "CB", x: 0.39, y: 0.70),
        FormationPosition(code: "CB", x: 0.61, y: 0.70),
        FormationPosition(code: "RB", x: 0.82, y: 0.68),
        FormationPosition(code: "CDM", x: 0.50, y: 0.54),
        FormationPosition(code: "CM", x: 0.34, y: 0.43),
        FormationPosition(code: "CAM", x: 0.66, y: 0.43),
        FormationPosition(code: "LW", x: 0.20, y: 0.24),
        FormationPosition(code: "ST", x: 0.50, y: 0.16),
        FormationPosition(code: "RW", x: 0.80, y: 0.24)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.32, green: 0.72, blue: 0.33),
                                Color(red: 0.18, green: 0.58, blue: 0.25)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))

                FormationFieldLines()
                    .stroke(.white.opacity(0.45), lineWidth: 2)
                    .padding(18)

                ForEach(positions) { position in
                    Button {
                        selectedPosition = position.code
                    } label: {
                        VStack(spacing: 3) {
                            Circle()
                                .fill(selectedPosition == position.code ? Color.yellow : .white)
                                .frame(width: 42, height: 42)
                                .overlay {
                                    Text(position.code)
                                        .font(.ballr(size: position.code.count > 2 ? 10 : 13, weight: .black))
                                        .foregroundStyle(Color(red: 0.06, green: 0.10, blue: 0.07))
                                }
                                .shadow(color: .black.opacity(0.24), radius: 5, y: 3)

                            Text(position.code)
                                .font(.ballr(size: 11, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: geometry.size.width * position.x, y: geometry.size.height * position.y)
                }
            }
        }
        .frame(height: 420)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.yellow.opacity(0.24), lineWidth: 1.5)
        }
    }
}

private struct FormationPosition: Identifiable {
    let id = UUID()
    let code: String
    let x: CGFloat
    let y: CGFloat
}

private struct FormationFieldLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.addRect(rect)
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addEllipse(in: CGRect(x: rect.midX - 44, y: rect.midY - 44, width: 88, height: 88))
        path.addRect(CGRect(x: rect.midX - 46, y: rect.minY, width: 92, height: 54))
        path.addRect(CGRect(x: rect.midX - 46, y: rect.maxY - 54, width: 92, height: 54))

        return path
    }
}

private struct FootChoiceButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ballr(size: 18, weight: .black))
                .foregroundStyle(isSelected ? Color(red: 0.08, green: 0.08, blue: 0.08) : Color.yellow)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(isSelected ? Color.yellow : Color.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow.opacity(0.28), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
    }
}

private struct AuthFieldBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.10, blue: 0.04),
                        Color(red: 0.03, green: 0.16, blue: 0.07),
                        Color(red: 0.02, green: 0.08, blue: 0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 0) {
                    ForEach(0..<14, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.018) : Color.black.opacity(0.055))
                    }
                }

                Circle()
                    .stroke(Color.yellow.opacity(0.15), lineWidth: 3)
                    .frame(width: geometry.size.width * 0.92)
                    .offset(y: geometry.size.height * 0.33)

                VStack(spacing: 8) {
                    ForEach(0..<5, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<24, id: \.self) { seat in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill((seat + row).isMultiple(of: 5) ? Color.yellow.opacity(0.16) : Color.white.opacity(0.055))
                                    .frame(width: 6, height: 5)
                            }
                        }
                        .offset(x: row.isMultiple(of: 2) ? -12 : 12)
                    }
                }
                .padding(.top, 84)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

private struct AuthWordmark: View {
    let size: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text("Ball")
                .foregroundStyle(Color.yellow)
            Text("r")
                .foregroundStyle(Color.orange)
        }
        .font(.ballr(size: size, weight: .black))
    }
}

private struct AuthMapIcon: View {
    var body: some View {
        Canvas { context, size in
            let dark = Color(red: 0.137, green: 0.122, blue: 0.125)
            let nodeRadius = min(size.width, size.height) * 0.105
            let points = [
                CGPoint(x: size.width * 0.16, y: size.height * 0.30),
                CGPoint(x: size.width * 0.16, y: size.height * 0.70),
                CGPoint(x: size.width * 0.50, y: size.height * 0.50),
                CGPoint(x: size.width * 0.84, y: size.height * 0.30),
                CGPoint(x: size.width * 0.84, y: size.height * 0.70)
            ]

            var line = Path()
            line.move(to: points[0])
            line.addLine(to: points[2])
            line.addLine(to: points[3])
            line.move(to: points[1])
            line.addLine(to: points[2])
            line.addLine(to: points[4])
            context.stroke(
                line,
                with: .color(dark),
                style: StrokeStyle(lineWidth: nodeRadius * 1.25, lineCap: .round, lineJoin: .round)
            )

            for point in points {
                let rect = CGRect(
                    x: point.x - nodeRadius,
                    y: point.y - nodeRadius,
                    width: nodeRadius * 2,
                    height: nodeRadius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(dark))
            }
        }
    }
}

private struct AuthTextField<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    var focusedField: FocusState<Field?>.Binding
    let field: Field
    let contentType: UITextContentType?
    let keyboardType: UIKeyboardType
    var submitLabel: SubmitLabel = .next

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.ballr(size: 12, weight: .black))
                .tracking(2)
                .foregroundStyle(Color.yellow.opacity(0.72))

            TextField("", text: $text)
                .font(.ballr(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focusedField, equals: field)
                .submitLabel(submitLabel)
                .padding(.horizontal, 18)
                .frame(height: 58)
                .background(Color.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow.opacity(0.22), lineWidth: 1.5)
                }
        }
    }
}

private struct AuthStatusCard: View {
    let message: String
    let color: Color

    var body: some View {
        Text(message)
            .font(.ballr(size: 14, weight: .bold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.34), lineWidth: 1.5)
            }
    }
}
