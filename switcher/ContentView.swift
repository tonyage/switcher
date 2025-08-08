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
    @State private var outputDevices: Set<Device.ID> = []
    @State private var inputDevices: Set<Device.ID> = []

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
                Devices(
                    devices: service.outputDevices,
                    selection: $outputDevices,
                    selector: kAudioHardwarePropertyDefaultOutputDevice
                )
            case .Input:
                Devices(
                    devices: service.inputDevices,
                    selection: $inputDevices,
                    selector: kAudioHardwarePropertyDefaultInputDevice
                )
            }
        }.padding().background(.background).overlay {
            RoundedRectangle(
                cornerRadius: 8, style: .continuous
            ).strokeBorder(.white.opacity(0.12))
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
            About()
        }.padding().background(.background)
    }
}

fileprivate struct About: View {
    private var version: String {
        let dict = Bundle.main.infoDictionary
        let ver = dict?["CFBundleShortVersionString"] as? String ?? "?.?.?"
        return "v\(ver)"
    }
    
    var body: some View {
        HStack {
            Spacer()
            Text(version).font(.footnote).foregroundStyle(.secondary)
        }.padding(.vertical, 1).padding(.horizontal, 1)
    }
}

fileprivate struct Devices: View {
    @EnvironmentObject private var service: AudioDeviceService
    let devices: [Device]
    @Binding var selection: Set<Device.ID>
    var selector: AudioObjectPropertySelector
    
    var body: some View {
        Table(devices, selection: $selection) {
            TableColumn("Name", value: \.name)
            TableColumn("Type", value: \.transport)
        }.onChange(of: selection) { _, newSelection in
            if let id = newSelection.first {
                service.set(to: id, selector: selector)
            }
        }
    }
}

fileprivate struct VolumeSlider: View {
    @EnvironmentObject private var service: AudioDeviceService
    @State private var volume: Double = 0.75
    @State private var muted: Bool = false
    
    var body: some View {
        let device = service.getDevice(source: .Output)
        let volumeBinding = Binding(
            get: { volume },
            set: { newVolume in
                volume = newVolume
                if let id = device {
                    service.setMasterVolume(newVolume, on: id)
                }
            }
        )
        let muteBinding = Binding(
            get: { muted },
            set: { flag in
                muted = flag
                if let id = device { service.muteDevice(flag, on: id) }
            }
        )
        VStack(alignment: .trailing) {
            HStack {
                Text("Output Volume")
                Spacer(minLength: 100)
                Image(systemName: "speaker.fill")
                Slider(
                    value: volumeBinding,
                    in: 0...1,
                    step: 0.15
                ).disabled(muted)
                Image(systemName: "speaker.wave.3.fill")
            }
            Toggle("Mute", isOn: muteBinding).toggleStyle(.checkbox)
        }.padding().background(.background).overlay {
            RoundedRectangle(
                cornerRadius: 8, style: .continuous
            ).strokeBorder(.white.opacity(0.12))
        }.task(id: device) {
            guard let id = device else { return }
            if let sysVol = service.masterVolume() { volume = sysVol }
            if let sysMute = service.isDeviceMuted(id: id) { muted = sysMute }
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
