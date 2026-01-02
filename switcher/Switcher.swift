//
//  Switcher.swift
//  switcher
//
//  Created by Tony Do on 7/14/25.
//

import SwiftUI

internal let WIDTH: CGFloat = 460
internal let HEIGHT: CGFloat = 400

@main
struct Switcher: App {
    
    private let listener: AudioHardwareListener
    @State private var service: AudioDeviceService
    
    init() {
        let listener = AudioHardwareListener()
        self.listener = listener
        _service = State(
            wrappedValue: AudioDeviceService(listener: listener)
        )
    }
    
    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .frame(width: WIDTH, height: HEIGHT)
                .environment(service)
        } label: {
            Image(systemName: "headphones").imageScale(.large)
        }.menuBarExtraStyle(.window)
    }
}
