//
//  ContentView.swift
//  switcher
//
//  Created by Tony Do on 7/14/25.
//

import Combine
import CoreAudio
import SwiftUI

enum SourceType: String, CaseIterable, Identifiable, Hashable {
    case Output
    case Input
    var id: Self { self }
}

struct ContentView: View {
    @Environment(AudioDeviceService.self) private var service
    @Environment(NavigationRouter.self) private var router
    @State private var source: SourceType = .Output

    @ViewBuilder
    private var appHeader: some View {
        HStack {
            Text("switcher")
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Button { router.push(.settings) } label: {
                Image(systemName: "gearshape").imageScale(.medium)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
    }
    
    @ViewBuilder
    private var devices: some View {
        Devices(
            devices: source == .Output
                ? service.outputDevices
                : service.inputDevices,
            selector: source == .Output
                ? kAudioHardwarePropertyDefaultOutputDevice
                : kAudioHardwarePropertyDefaultInputDevice,
            source: $source
        )
    }
    
    var body: some View {
        VStack {
            appHeader
            devices
            SoundManagement(source: $source)
            About()
        }
        .background(.clear)
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
        .background(Color.primary.opacity(0.1))
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
        .padding(.horizontal, 8)
    }
}

fileprivate struct Devices: View {
    @Environment(AudioDeviceService.self) private var service
    let devices: [Device]
    let selector: AudioObjectPropertySelector
    private var currentDevice: Device.ID? {
        source == .Output
            ? service.currentOutputDevice
            : service.currentInputDevice
    }
    
    @Binding var source: SourceType

    @ViewBuilder
    private var headerView: some View {
        SourcePicker(source: $source)
            .padding(10)
            .background(.ultraThinMaterial)
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
                    service.set(to: devices[index].id, selector: selector)
                }
            )
            .background(
                Rectangle()
                    .fill(
                        index % 2 == 0
                        ? .black.opacity(0.3)
                        : .primary.opacity(0.1)
                    )
            )
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
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.3)))
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

/// TODO: hook up sliders for channel balance and input gain, only mute and volume work currently
/// service currently has no logic for retrieving and setting channel balance values and
/// reading input gain.
fileprivate struct SoundManagement: View {
    @Environment(AudioDeviceService.self) private var service
    @Binding var source: SourceType
    @State private var volume: Float32 = 0.5
    @State private var muted: Bool = false
    @State private var balance: Float32 = 0.0
    @State private var isEditing: Bool = false

    @ViewBuilder
    private var volumeSlider: some View {
        let device = service.currentOutputDevice!
        HStack {
            Text("Output Volume")
            Spacer(minLength: 100)
            Image(systemName: "speaker.fill")
            Slider(
                value: $volume,
                in: 0...1.0,
                onEditingChanged: { editing in
                    isEditing = editing
                    service.setVolume(volume, on: device)
                }
            )
            .disabled(muted)
            Image(systemName: "speaker.wave.3.fill")
        }
        Toggle("Mute", isOn: $muted).onChange(of: muted) {
            service.muteDevice(muted, on: device)
        }.toggleStyle(.checkbox)
    }
    
    @ViewBuilder
    private var balanceSlider: some View {
        let device = service.currentOutputDevice!
        HStack {
            Text("Balance")
            Spacer(minLength: 145)
            Slider(
                value: $balance,
                in: 0...2,
                step: 0.5,
                onEditingChanged: { editing in
                    isEditing = editing
                    service.setBalance(balance, on: device)
                }
            )
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
            if let sysVolume = service.volume() {
                volume = sysVolume
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.3))
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
    @State @Previewable var router = NavigationRouter()
    NavigationStack(path: $router.paths) {
        router.navigate(to: .home)
            .navigationDestination(for: Screen.self) { screen in
                router.navigate(to: screen)
            }
    }
    .frame(width: WIDTH, height: HEIGHT)
    .environment(router)
    .environment(AudioDeviceService(listener: AudioHardwareListener()))
}
