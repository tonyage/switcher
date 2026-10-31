//
//  Settings.swift
//  switcher
//
//  Created by tonyage on 1/4/26.
//

import ServiceManagement
import SwiftUI

struct Settings: View {
    @Environment(NavigationRouter.self) var router
    @State private var loginStatus: SMAppService.Status = SMAppService.mainApp.status
    @State private var loginError: String?
    @AppStorage(playVolumeFeedbackKey) private var playVolumeFeedback = false
    @AppStorage(preventSleepKey) private var preventSleep = false

    /// Derived from the system's registration rather than stored separately so it
    /// can't drift: the menubar window keeps this view alive between openings and
    /// the login item can also be changed from System Settings.
    private var launchOnLogin: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    loginError = nil
                } catch {
                    loginError = error.localizedDescription
                }
                refreshLoginStatus()
            }
        )
    }

    private func refreshLoginStatus() {
        loginStatus = SMAppService.mainApp.status
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button { router.popToRoot() } label: {
                    Label("Settings", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .scenePadding(.top)
            .scenePadding(.horizontal)
            // Cards instead of a grouped Form: on macOS the form draws its own light
            // row backgrounds and ignores `listRowBackground`, so they couldn't
            // match the darker panels on the main screen.
            ScrollView {
                VStack(spacing: 10) {
                    SettingsCard("Launch on login", isOn: launchOnLogin) {
                        Text("When enabled, add switcher to the menu bar on user login.")
                        if loginStatus == .requiresApproval {
                            HStack {
                                Text("Needs approval in Login Items.")
                                    .foregroundStyle(.secondary)
                                Button("Open Settings") {
                                    SMAppService.openSystemSettingsLoginItems()
                                }
                                .buttonStyle(.link)
                            }
                        }
                        if let loginError {
                            Text(loginError).foregroundStyle(.red)
                        }
                    }
                    SettingsCard("Volume feedback", isOn: $playVolumeFeedback) {
                        Text("Play feedback when volume is changed")
                    }
                    SettingsCard("Prevent sleep", isOn: $preventSleep) {
                        Text("Keep the Mac awake while switcher is running. The display can still turn off.")
                    }
                    .onChange(of: preventSleep) { _, enabled in
                        SleepGuard.setEnabled(enabled)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .navigationBarBackButtonHidden()
            .onAppear(perform: refreshLoginStatus)
            .onReceive(
                NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            ) { _ in refreshLoginStatus() }
            .onReceive(
                NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            ) { _ in refreshLoginStatus() }
        }
    }
}

/// One toggle setting with its description, drawn like the panels on the main
/// screen. The switch sits on the right at the mini size the grouped form used.
fileprivate struct SettingsCard<Details: View>: View {
    let title: String
    @Binding var isOn: Bool
    @ViewBuilder let details: Details

    init(_ title: String, isOn: Binding<Bool>, @ViewBuilder details: () -> Details) {
        self.title = title
        self._isOn = isOn
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isOn) {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            details
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3)))
    }
}

#Preview("Settings") {
    @State @Previewable var router = NavigationRouter()
    NavigationStack(path: $router.paths) {
        router.navigate(to: .settings)
    }
    .frame(width: WIDTH, height: HEIGHT)
    .environment(router)
    .environment(AudioDeviceService(listener: AudioHardwareListener()))
    .environment(MixerService(listener: AudioHardwareListener()))
}
