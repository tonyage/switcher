//
//  MixerTests.swift
//  switcherTests
//
//  Created by tonyage on 10/16/26.
//

import CoreAudio
import Foundation
@testable import switcher
import Testing

/// Owns Float32 storage backing an AudioBufferList for render tests.
private final class Buffers {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float32>] = []

    /// One buffer per entry, each with `channels` interleaved channels.
    init(frames: Int, layout: [Int], fill: (Int, Int) -> Float32 = { _, _ in 0 }) {
        list = AudioBufferList.allocate(maximumBuffers: layout.count)
        var channelBase = 0
        for (i, channels) in layout.enumerated() {
            let data = UnsafeMutablePointer<Float32>.allocate(capacity: frames * channels)
            for f in 0..<frames {
                for c in 0..<channels { data[f * channels + c] = fill(channelBase + c, f) }
            }
            storage.append(data)
            list[i] = AudioBuffer(
                mNumberChannels: UInt32(channels),
                mDataByteSize: UInt32(frames * channels * MemoryLayout<Float32>.size),
                mData: data
            )
            channelBase += channels
        }
    }

    func sample(buffer: Int, frame: Int, channel: Int) -> Float32 {
        storage[buffer][frame * Int(list[buffer].mNumberChannels) + channel]
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }
}

@Suite
struct MixerRenderTests {
    @Test("Applies constant gain to interleaved stereo")
    func constantGain() {
        let input = Buffers(frames: 4, layout: [2]) { c, _ in c == 0 ? 1 : -1 }
        let output = Buffers(frames: 4, layout: [2])

        ProcessTap.render(input: input.list, output: output.list, sourceChannels: 2, gain: (0.5, 0.5))

        for f in 0..<4 {
            #expect(output.sample(buffer: 0, frame: f, channel: 0) == 0.5)
            #expect(output.sample(buffer: 0, frame: f, channel: 1) == -0.5)
        }
    }

    @Test("Ramps between start and end gain across the buffer")
    func gainRamp() {
        let input = Buffers(frames: 4, layout: [1]) { _, _ in 1 }
        let output = Buffers(frames: 4, layout: [1])

        ProcessTap.render(input: input.list, output: output.list, sourceChannels: 1, gain: (0, 1))

        let samples = (0..<4).map { output.sample(buffer: 0, frame: $0, channel: 0) }
        #expect(samples == [0, 0.25, 0.5, 0.75])
    }

    @Test("Uses the trailing tap channels when the sub-device also has inputs")
    func skipsDeviceInputs() {
        // Buffer 0 is a mic channel from the output sub-device, buffer 1 is the tap.
        let input = Buffers(frames: 2, layout: [1, 2]) { c, _ in Float32(c) }
        let output = Buffers(frames: 2, layout: [2])

        ProcessTap.render(input: input.list, output: output.list, sourceChannels: 2, gain: (1, 1))

        #expect(output.sample(buffer: 0, frame: 0, channel: 0) == 1)
        #expect(output.sample(buffer: 0, frame: 0, channel: 1) == 2)
    }

    @Test("Maps to non-interleaved output and silences extra channels")
    func nonInterleavedOutput() {
        let input = Buffers(frames: 2, layout: [2]) { _, _ in 1 }
        let output = Buffers(frames: 2, layout: [1, 1, 1]) { _, _ in 9 }

        ProcessTap.render(input: input.list, output: output.list, sourceChannels: 2, gain: (1, 1))

        #expect(output.sample(buffer: 0, frame: 1, channel: 0) == 1)
        #expect(output.sample(buffer: 1, frame: 1, channel: 0) == 1)
        #expect(output.sample(buffer: 2, frame: 1, channel: 0) == 0)
    }
}

@Suite
struct MixerServiceTests {
    private func defaults() -> UserDefaults {
        let name = "switcher.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let app = MixerApp(
        id: "com.example.app",
        appID: "com.example.app",
        name: "Example",
        channel: nil,
        bundleURL: URL(fileURLWithPath: "/Applications/Example.app"),
        processes: [],
        isPlaying: false
    )

    @Test("Apps default to full volume")
    func defaultVolume() async {
        let mixer = await MixerService(listener: AudioHardwareListener(), defaults: defaults())
        #expect(await mixer.volume(for: app) == 1)
    }

    @Test("Restores saved volumes on launch")
    func restoresVolumes() async {
        let store = defaults()
        store.set(["com.example.app": Float32(0.25)], forKey: "mixerVolumes")

        let mixer = await MixerService(listener: AudioHardwareListener(), defaults: store)
        #expect(await mixer.volume(for: app) == 0.25)
    }

    @Test("Saves and restores a channel's output device")
    func restoresRoutes() async {
        let store = defaults()
        let mixer = await MixerService(listener: AudioHardwareListener(), defaults: store)
        #expect(await mixer.outputDeviceUID(for: app) == nil)

        // A UID that isn't connected, so no tap is created.
        await mixer.setOutputDevice(uid: "switcher.tests.missing-device", for: app)
        let restored = await MixerService(listener: AudioHardwareListener(), defaults: store)
        #expect(await restored.outputDeviceUID(for: app) == "switcher.tests.missing-device")

        await restored.setOutputDevice(uid: nil, for: app)
        #expect(await restored.outputDeviceUID(for: app) == nil)
    }

    @Test("Discovered apps exclude switcher itself")
    func excludesSelf() async {
        let mixer = await MixerService(listener: AudioHardwareListener(), defaults: defaults())
        let ids = await mixer.apps.map(\.id)
        #expect(!ids.contains(Bundle.main.bundleIdentifier ?? "com.tonyage.switcher"))
    }
}
