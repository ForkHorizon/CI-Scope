//
//  CI_ScopeApp.swift
//  CI Scope
//
//  Created by Kiryl Shcherba on 27/05/2026.
//

import SwiftUI

@main
struct CI_ScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
