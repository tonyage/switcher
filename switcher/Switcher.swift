//
//  Switcher.swift
//  switcher
//
//  Created by Tony Do on 7/14/25.
//

import SwiftUI

internal let WIDTH: CGFloat = 460
internal let HEIGHT: CGFloat = 460

@main
struct Switcher: App {
    
    @State private var service: AudioDeviceService
    @State private var router = NavigationRouter()
    
    init() {
        _service = State(
            wrappedValue: AudioDeviceService(listener: AudioHardwareListener())
        )
    }
    
    var body: some Scene {
        MenuBarExtra {
            NavigationStack(path: $router.paths) {
                router.navigate(to: .home)
                    .navigationDestination(for: Screen.self) { screen in
                        router.navigate(to: screen)
                    }
            }
            .frame(width: WIDTH, height: HEIGHT)
            .environment(router)
            .environment(service)
        } label: {
            Image(systemName: "headphones").imageScale(.large)
        }.menuBarExtraStyle(.window)
    }
}
