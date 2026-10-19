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
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Toggle("Launch on login", isOn: launchOnLogin)
                            .toggleStyle(.switch)
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
                }
                Section {
                    VStack(alignment: .leading) {
                        Toggle("Volume feedback", isOn: $playVolumeFeedback)
                            .toggleStyle(.switch)
                        Text("Play feedback when volume is changed")
                    }
                }
                Section {
                    VStack(alignment: .leading) {
                        Toggle("Prevent sleep", isOn: $preventSleep)
                            .toggleStyle(.switch)
                            .onChange(of: preventSleep) { _, enabled in
                                SleepGuard.setEnabled(enabled)
                            }
                        Text("Keep the Mac awake while switcher is running. The display can still turn off.")
                    }
                }
            }
            .navigationBarBackButtonHidden()
            .formStyle(.grouped)
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
