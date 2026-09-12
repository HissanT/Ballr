//
//  ballrApp.swift
//  ballr
//
//  Created by Bishoy Tadrous on 4/10/26.
//

import SwiftUI

@main
struct ballrApp: App {
    @UIApplicationDelegateAdaptor(BallrAppDelegate.self) private var appDelegate
    @StateObject private var authSession = AuthSessionManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BallrFont.registerFontsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView()
                .environmentObject(authSession)
        }
        .onChange(of: scenePhase) { _, newPhase in
            BallrBackgroundAudioController.shared.updateScenePhase(isActive: newPhase == .active)
        }
    }
}
