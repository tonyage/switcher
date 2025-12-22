//
//  Helpers.swift
//  switcher
//
//  Created by Tony Do on 7/23/25.
//

import CoreAudio
import ServiceManagement
import SwiftUI

private extension AudioObjectPropertyAddress {
    init(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope,
        _ element: AudioObjectPropertyElement
    ) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}

@Observable class AppState { var launchOnLogin = false }

struct LaunchOnLogin: View {
    @Environment(AppState.self) var state
    
    var body: some View {
        @Bindable var state = state
        Section {
            VStack(alignment: .leading) {
                Toggle("Launch on login", isOn: $state.launchOnLogin)
                Text("Add switcher to the menu bar on user login")
            }
        }
        .padding(8)
        .onAppear {
            state.launchOnLogin = SMAppService.mainApp.status == .enabled ? true : false
        }
        .onChange(of: state.launchOnLogin) { _, newState in
            newState
                ? try? SMAppService.mainApp.register()
                : try? SMAppService.mainApp.unregister()
        }
    }
}
