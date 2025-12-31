//
//  ContentView.swift
//  switcher
//
//  Created by Tony Do on 7/14/25.
//

import CoreAudio
import ServiceManagement
import SwiftUI

enum SourceType: String, CaseIterable, Identifiable, Hashable {
    case Output
    case Input
    var id: Self { self }
}

struct ContentView: View {
    @State private var source: SourceType = .Output
    @EnvironmentObject private var service: AudioDeviceService
    
    @ViewBuilder
    private var devices: some View {
        Devices(
            devices: source == .Output
                ? service.outputDevices
                : service.inputDevices,
            selector: source == .Output
                ? kAudioHardwarePropertyDefaultOutputDevice
                : kAudioHardwarePropertyDefaultInputDevice,
            currentDevice: source == .Output
                ? service.currentOutputDevice
                : service.currentInputDevice,
            source: $source
        )
    }
    
    var body: some View {
        VStack {
            Text("switcher")
                .bold()
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            devices
            SoundManagement(source: $source)
            About()
        }
        .scenePadding()
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
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .buttonStyle(.borderless)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(source == selection ? .accentColor : Color.clear)
                }
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
    let selector: AudioObjectPropertySelector
    @State var currentDevice: Device.ID?
    @Binding var source: SourceType

    @ViewBuilder
    private var headerView: some View {
        SourcePicker(source: $source)
            .padding(10)
            .background(Color.clear)
    }

    @ViewBuilder
    private var sectionHeaderRow: some View {
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
    }

    @ViewBuilder
    private func deviceRow() -> some View {
        ForEach(devices.indices, id: \.self) { index in
            DeviceRow(
                device: devices[index],
                isSelected: devices[index].id == currentDevice,
                onSelect: {
                    currentDevice = devices[index].id
                    service.set(to: devices[index].id, selector: selector)
                }
            )
            .background(Rectangle().fill(isEven(index) ? .clear : .primary.opacity(0.1)))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section(header: headerView) {
                    sectionHeaderRow
                    deviceRow()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(RoundedRectangle(cornerRadius: 16).fill(.secondary.opacity(0.05)))
    }

    func isEven(_ index: Int) -> Bool {
        index % 2 == 0
    }
}

fileprivate struct DeviceRow: View {
    let device: Device
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            Text(device.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(device.transport)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .contentShape(.rect)
        .background {
            Rectangle()
                .fill(isSelected ? Color.accentColor : .clear)
        }
        .onTapGesture { onSelect() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// TODO: hook up sliders for volume, channel balance, and input gain, only mute works currently
/// will involve probing CoreAudio for acceptable values to set volume, service currently has no
/// logic for retrieving and setting channel balance values and input gain.
fileprivate struct SoundManagement: View {
    @EnvironmentObject private var service: AudioDeviceService
    @Binding var source: SourceType
    @State private var volume: Double = 0.5
    @State private var muted: Bool = false
    @State private var balance: Double = 1.0
    @State private var isEditing: Bool = false

    @ViewBuilder
    private var volumeSlider: some View {
        let device = service.getDevice(source: .Output)!
        HStack {
            Text("Output Volume")
            Spacer(minLength: 100)
            Image(systemName: "speaker.fill")
            Slider(
                value: $volume,
                in: 0...1.0,
                onEditingChanged: { editing in
                    isEditing = editing
                    if editing {
                        print("onEditingChanged: \(volume)")
                    } else {
                        print("setMasterVolume: \(volume)")
                        service.setMasterVolume(volume, on: device)
                    }
                }
            )
            .disabled(muted)
            Image(systemName: "speaker.wave.3.fill")
        }
        Toggle("Mute", isOn: $muted).toggleStyle(.checkbox)
    }
    
    @ViewBuilder
    private var balanceSlider: some View {
        HStack {
            Text("Balance")
            Spacer(minLength: 145)
            Slider(value: $balance, in: 0...2, step: 1)
        }
    }

    @ViewBuilder
    private var inputLevel: some View {
        VStack(alignment: .trailing) {
            HStack {
                Text("Input Level")
                Spacer(minLength: 90)
                InputLevel(level: 2.0)
            }
        }
    }

    var body: some View {
        let device = service.getDevice(source: .Output)
        VStack(alignment: .trailing, spacing: 8) {
            switch source {
                case .Output:
                    volumeSlider
                    Divider()
                    balanceSlider
                case .Input: inputLevel
            }
        }
        .task(id: device) {
            guard let id = device else { return }
            if let sysMute = service.isDeviceMuted(id: id) { muted = sysMute }
            if let sysVolume = service.masterVolume() {
                print("systemVolume: \(sysVolume)")
                volume = sysVolume
            }
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
        }
        .animation(.linear(duration: 0.05), value: level)
    }
}

#Preview("Devices") {
    ContentView().frame(width: WIDTH, height: HEIGHT).environmentObject(
        AudioDeviceService(listener: AudioHardwareListener())
    )
}
