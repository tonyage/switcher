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
    @State private var currentDevice: Device.ID?

    @EnvironmentObject private var service: AudioDeviceService
    
    @ViewBuilder var inputLevel: some View {
        VStack(alignment: .trailing) {
            HStack {
                Text("Input Level")
                Spacer(minLength: 90)
                InputLevel(level: 2.0)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.05))
        )
    }

    @ViewBuilder var devices: some View {
        switch source {
        case .Output:
            Devices(
                devices: service.outputDevices,
                selector: kAudioHardwarePropertyDefaultOutputDevice,
                source: $source
            )
        case .Input:
            Devices(
                devices: service.inputDevices,
                selector: kAudioHardwarePropertyDefaultInputDevice,
                source: $source
            )
        }
    }
    
    var body: some View {
        VStack {
            Text("switcher")
                .bold()
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            devices
            if source == .Output {
                SoundManagement()
            } else { inputLevel }
            About()
        }
        .padding()
        .onAppear(perform: syncCurrentDevice)
    }
    
    private func syncCurrentDevice() {
        currentDevice = service.getDevice(source: source)
    }
}

fileprivate struct SourcePicker: View {
    @Binding var source: SourceType
    
    var body: some View {
        HStack {
            ForEach(SourceType.allCases, id: \.self) { selection in
                Button { source = selection } label: {
                    Text("\(selection.rawValue)")
                        .frame(maxWidth: .infinity)
                        .padding(4)
                }
                .foregroundStyle(.primary)
                .background(source == selection ? .accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.borderless)
            }
        }
        .background(Color(NSColor.darkGray))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 1)
    }
}

fileprivate struct Devices: View {
    @EnvironmentObject private var service: AudioDeviceService
    let devices: [Device]
    var selector: AudioObjectPropertySelector
    let columns: [GridItem] = Array(
        repeating: .init(.flexible(), alignment: .leading),
        count: 1
    )
    @Binding var source: SourceType
    
    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: columns,
                spacing: 0,
                pinnedViews: [.sectionHeaders]
            ) {
                Section(
                    header: SourcePicker(source: $source)
                        .padding(10)
                        .background(
                            UnevenRoundedRectangle(
                                cornerRadii: .init(topLeading: 16, topTrailing: 16)
                            ).fill(.clear))
                ) {
                    HStack {
                        Text("Name")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Type")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.1))

                    ForEach(devices.indices, id: \.self) { index in
                        HStack {
                            Text(devices[index].name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(devices[index].transport)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(8)
                        .contentShape(.rect)
                        .background(isEven(index) ? .clear : .primary.opacity(0.1))
                    }
                }
            }
        }
        .mask(RoundedRectangle(cornerRadius: 16))
        .background(RoundedRectangle(cornerRadius: 16).fill(.secondary.opacity(0.05)))
    }

    func isEven(_ index: Int) -> Bool {
        index % 2 == 0
    }
}

fileprivate struct DeviceRow: View {
    let device: Device
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Text(device.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(device.transport)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .contentShape(.rect)
    }
}

fileprivate struct SoundManagement: View {
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
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Text("Output Volume")
                Spacer(minLength: 100)
                Image(systemName: "speaker.fill")
                Slider(
                    value: volumeBinding,
                    in: 0...1,
                    step: 0.18
                ).disabled(muted)
                Image(systemName: "speaker.wave.3.fill")
            }
            Toggle("Mute", isOn: muteBinding).toggleStyle(.checkbox)
            Divider()
            HStack {
                Text("Balance")
                Spacer(minLength: 145)
                Slider(value: volumeBinding, in: 0...2, step: 1)
            }
        }.task(id: device) {
            guard let id = device else { return }
            if let sysVol = service.masterVolume() { volume = sysVol }
            if let sysMute = service.isDeviceMuted(id: id) { muted = sysMute }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.05))
        )
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
