//
//  beauty_wallApp.swift
//  beauty_wall
//
//  Created by wang on 2026/3/2.
//

import SwiftUI
import AppKit

@main
struct beauty_wallApp: App {
    @StateObject private var settings: AppSettingsStore
    @StateObject private var refreshController: WallpaperRefreshController
    
    init() {
        let settingsStore = AppSettingsStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _refreshController = StateObject(wrappedValue: WallpaperRefreshController(settings: settingsStore))
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(settings)
                .environmentObject(refreshController)
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
        }
        .menuBarExtraStyle(.menu)
        
        WindowGroup(id: "settings") {
            SettingsView()
                .environmentObject(settings)
        }
        .defaultSize(width: SettingsLayout.windowWidth, height: SettingsLayout.windowHeight)
        .commands {
            CommandMenu("壁纸") {
                Button("立即刷新壁纸") {
                    Task { await refreshController.refreshNow(trigger: .manual) }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("打开设置…") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
