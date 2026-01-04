//
//  Settings.swift
//  switcher
//
//  Created by Tony Do on 1/4/26.
//

import ServiceManagement
import SwiftUI

struct Settings: View {
    @Environment(NavigationRouter.self) var router
    @State private var launchOnLogin: Bool = false
    
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
                        Toggle("Launch on login", isOn: $launchOnLogin)
                            .onChange(of: launchOnLogin) { _, newState in
                                newState
                                    ? try? SMAppService.mainApp.register()
                                    : try? SMAppService.mainApp.unregister()

                            }
                            .toggleStyle(.switch)
                        Text("When enabled, add switcher to the menu bar on user login.")
                    }
                }
            }
            .navigationBarBackButtonHidden()
            .formStyle(.grouped)
            .onAppear {
                launchOnLogin = SMAppService.mainApp.status == .enabled ? true : false
            }
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
}
