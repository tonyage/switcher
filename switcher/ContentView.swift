//
//  ContentView.swift
//  switcher
//
//  Created by Tony Do on 7/14/25.
//

import CoreAudio
import SwiftUI

struct ContentView: View {
    
    @State private var source: SourceType = .Output
    @State private var text: String = .init()
    @State private var outputDeviceIDs: Set<Device.ID> = []
    @State private var inputDeviceIDs: Set<Device.ID> = []

    @EnvironmentObject private var service: AudioDeviceService
    
    @ViewBuilder var picker: some View {
        VStack(spacing: 0) {
            Picker("SourceType", selection: $source) {
                ForEach(SourceType.allCases) {
                    Text($0.rawValue)
                }
            }.labelsHidden().pickerStyle(.segmented).tint(.blue)
            
            switch source {
            case .Output:
                table(
                    devices: service.outputDevices,
                    selection: $outputDeviceIDs,
                    selector: kAudioHardwarePropertyDefaultOutputDevice
                ).onChange(of: outputDeviceIDs) { _, newSelection in
                    if let selectedID = newSelection.first {
                        service.set(
                            to: selectedID,
                            selector: kAudioHardwarePropertyDefaultOutputDevice
                        )
                    }
                }
            case .Input:
                table(
                    devices: service.inputDevices,
                    selection: $inputDeviceIDs,
                    selector: kAudioHardwarePropertyDefaultInputDevice
                ).onChange(of: inputDeviceIDs) { _, newSelection in
                    if let selectedID = newSelection.first {
                        service.set(
                            to: selectedID,
                            selector: kAudioHardwarePropertyDefaultInputDevice
                        )
                    }
                }
            }
        }.padding().background(.background).overlay {
            RoundedRectangle(
                cornerRadius: 8, style: .continuous
            ).strokeBorder(.white.opacity(0.12))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder private func table(
        devices: [Device],
        selection: Binding<Set<Device.ID>>,
        selector: AudioObjectPropertySelector
    ) -> some View {
        Table(devices, selection: selection) {
            TableColumn("Name", value: \.name)
            TableColumn("Type", value: \.transport)
        }
    }
    
    @ViewBuilder var inputLevel: some View {
        VStack(alignment: .trailing) {
            HStack {
                Text("Input Level")
                Spacer(minLength: 100)
                InputLevel(level: 2.0)
            }
        }.padding().background(.background).overlay {
            RoundedRectangle(
                cornerRadius: 8, style: .continuous
            ).strokeBorder(.white.opacity(0.12))
        }
    }

    var body: some View {
        VStack {
            picker
            if source == .Output {
                VolumeSlider()
            } else { inputLevel }
        }.padding().background(.background)
    }
}

fileprivate struct VolumeSlider: View {
    @EnvironmentObject private var service: AudioDeviceService
    @State private var volume: Double = 0.75
    @State private var muted: Bool = false
    
    var body: some View {
        let binding = Binding(
            get: { volume },
            set: { newVolume in
                volume = newVolume
                if let id = service.defaultOutputDevice() {
                    service.setMasterVolume(newVolume, on: id)
                }
            }
        )
        VStack(alignment: .trailing) {
            HStack {
                Text("Output Volume")
                Spacer(minLength: 100)
                Image(systemName: "speaker.fill")
                Slider(value: binding, in: 0...1, step: 0.15).disabled(muted)
                Image(systemName: "speaker.wave.3.fill")
            }
            Toggle("Mute", isOn: $muted).toggleStyle(.checkbox)
        }.padding().background(.background).overlay {
            RoundedRectangle(
                cornerRadius: 8, style: .continuous
            ).strokeBorder(.white.opacity(0.12))
        }.task(id: service.masterVolume()) {
            if let systemVolume = service.masterVolume() {
                volume = systemVolume
            }
        }
    }
}

fileprivate struct InputLevel: View {
    var level: Double
    private let count = 15
    private let width: CGFloat = 6
    private let height: CGFloat = 14
    private let spacing: CGFloat = 10
    
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { idx in
                Capsule()
                    .frame(width: width, height: height)
                    .foregroundStyle(
                        idx < Int(level * Double(count))
                        ? .gray
                        : .gray.opacity(0.15)
                    )
            }
        }.animation(.linear(duration: 0.05), value: level)
    }
}

enum SourceType: String, CaseIterable, Identifiable, Hashable {
    case Output
    case Input
    
    var id: Self { self }
}

#Preview("Devices") {
    ContentView().frame(width: WIDTH, height: HEIGHT).environmentObject(
        AudioDeviceService(listener: AudioHardwareListener())
    )
}
