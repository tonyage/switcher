//
//  Mixer.swift
//  switcher
//
//  Created by tonyage on 10/16/26.
//

import AppKit
import CoreAudio
import Darwin
import Synchronization
import os.log

private let mixerLog = Logger(subsystem: "com.tonyage.switcher", category: "mixer")
private let volumesKey = "mixerVolumes"
private let heardKey = "mixerHeardChannels"

private let responsibilityLookup: (@convention(c) (pid_t) -> pid_t)? = {
    guard let symbol = dlsym(
        UnsafeMutableRawPointer(bitPattern: -2), // RTLD_DEFAULT
        "responsibility_get_pid_responsible_for_pid"
    ) else { return nil }
    return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
}()

/// Settings key for playing a sound when a mixer channel's volume changes.
let playVolumeFeedbackKey = "playVolumeFeedback"

/// Plays the system volume "blip" at a channel's level so you can hear where you
/// set it. switcher's own output is never tapped, so this is only scaled once.
@MainActor
enum VolumeFeedback {
    private static let sound: NSSound? = NSSound(
        contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
        byReference: true
    ) ?? NSSound(named: "Pop")

    static func play(at volume: Float32) {
        guard let sound else { return }
        sound.stop()
        sound.volume = max(0, min(volume, 1))
        sound.play()
    }
}

/// One row in the mixer: the processes of an app that share a role. Most apps have
/// a single channel, while e.g. Discord plays voice chat from its renderer and
/// notification sounds from a separate audio helper, so each gets its own slider.
struct MixerApp: Identifiable, Hashable {
    /// `appID|role`, used to key saved volumes.
    let id: String
    /// Bundle identifier of the outermost app bundle, or its path if it has none.
    let appID: String
    let name: String
    /// Set when the app has more than one channel listed.
    let channel: String?
    let bundleURL: URL
    /// Core Audio process objects in this channel.
    let processes: [AudioObjectID]
    let isPlaying: Bool
}

/// Channels whose purpose is known; listed whenever their process is running.
/// Anything else is labelled from the helper's bundle identifier (e.g. "Renderer").
private let knownChannels = [
    "com.hnc.Discord.helper.Renderer": "Voice chat",
    "com.hnc.Discord.helper": "Notifications",
]

/// Per application volume control built on Core Audio process taps (macOS 14.2+).
///
/// Apps at 100% are left alone. Once a channel is turned down, its processes are
/// tapped with `mutedWhenTapped` so the original output is silenced, and the
/// tapped audio is replayed on the default output device scaled by the gain.
@MainActor
@Observable
final class MixerService {
    private(set) var apps: [MixerApp] = []
    private(set) var volumes: [String: Float32] = [:]

    private let listener: AudioHardwareListener
    private var taps: [String: ProcessTap] = [:]
    /// Channels that have ever played audio. Persisted so apps are listed while
    /// running even if they've been quiet since switcher launched.
    private var heard: Set<String> = []
    private var pollTask: Task<Void, Never>?
    private let defaults: UserDefaults

    init(listener: AudioHardwareListener, defaults: UserDefaults = .standard) {
        self.listener = listener
        self.defaults = defaults
        if let stored = defaults.dictionary(forKey: volumesKey) as? [String: Float32] {
            volumes = stored
        }
        heard = Set(defaults.stringArray(forKey: heardKey) ?? [])
        refresh()
        registerListeners()
        startPolling()
    }

    func volume(for app: MixerApp) -> Float32 {
        volumes[app.id] ?? 1
    }

    func setVolume(_ volume: Float32, for app: MixerApp) {
        let clamped = max(0, min(volume, 1))
        volumes[app.id] = clamped >= 1 ? nil : clamped
        defaults.set(volumes, forKey: volumesKey)
        mixerLog.debug("Set \(app.id, privacy: .public) to \(clamped)")
        reconcileTap(for: app)
    }

    private func registerListeners() {
        listener.onProcessesChanged = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        listener.onDeviceChanged = { [weak self] in
            Task { @MainActor in self?.rebuildTaps() }
        }
        listener.start()
    }

    /// The HAL doesn't reliably notify when an existing process starts or stops
    /// output, so poll for it. Cheap: a few property reads per process.
    private func startPolling() {
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.refresh()
            }
        }
    }

    /// Re-reads the HAL process list and keeps rows and taps in sync with it.
    private func refresh() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        typealias Channel = (
            appID: String, role: String, name: String, url: URL,
            processes: [AudioObjectID], playing: Bool
        )
        var channels: [String: Channel] = [:]

        for object in audioProcessObjects() {
            guard let pid = processPID(object), pid != ownPID,
                  let bundleURL = appBundleURL(for: pid) else { continue }

            let appID = Bundle(url: bundleURL)?.bundleIdentifier ?? bundleURL.path
            // Skip other running copies of switcher too (e.g. a debug build).
            guard appID != Bundle.main.bundleIdentifier else { continue }
            let role = processBundleID(object) ?? executablePath(for: pid)?.lastPathComponent ?? appID
            let id = "\(appID)|\(role)"
            let playing = isRunningOutput(object)

            if var entry = channels[id] {
                entry.processes.append(object)
                entry.playing = entry.playing || playing
                channels[id] = entry
            } else {
                let name = FileManager.default.displayName(atPath: bundleURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                channels[id] = (appID, role, name, bundleURL, [object], playing)
            }
        }

        let newlyHeard = channels.filter { $0.value.playing && !heard.contains($0.key) }.keys
        if !newlyHeard.isEmpty {
            heard.formUnion(newlyHeard)
            defaults.set(Array(heard).sorted(), forKey: heardKey)
        }

        // Only channels that output sound (or are known to), plus any that were
        // turned down so they can always be turned back up.
        let visible = channels.filter { id, entry in
            heard.contains(id) || volumes[id] != nil || knownChannels[entry.role] != nil
        }
        let channelCounts = Dictionary(grouping: visible.values, by: \.appID).mapValues(\.count)
        let rows = visible
            .map { id, entry in
                MixerApp(
                    id: id,
                    appID: entry.appID,
                    name: entry.name,
                    channel: channelCounts[entry.appID, default: 0] > 1
                        ? channelLabel(role: entry.role, appID: entry.appID)
                        : nil,
                    bundleURL: entry.url,
                    processes: entry.processes.sorted(),
                    isPlaying: entry.playing
                )
            }
            .sorted {
                // Alphabetical by app, then channel, so rows never move when
                // something starts or stops playing.
                let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                if $0.appID != $1.appID { return $0.appID < $1.appID }
                return ($0.channel ?? "") < ($1.channel ?? "")
            }
        if rows != apps { apps = rows }

        // Drop taps for channels that went away, then make sure the rest match.
        let current = Set(apps.map(\.id))
        for id in taps.keys where !current.contains(id) {
            taps.removeValue(forKey: id)?.invalidate()
        }
        apps.forEach(reconcileTap(for:))
    }

    private func channelLabel(role: String, appID: String) -> String {
        if let known = knownChannels[role] { return known }
        if role == appID { return "Main" }
        let last = role.split(separator: ".").last.map(String.init) ?? role
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    /// Output device changed: every tap's aggregate points at the old device.
    private func rebuildTaps() {
        taps.values.forEach { $0.invalidate() }
        taps.removeAll()
        apps.forEach(reconcileTap(for:))
    }

    private func reconcileTap(for app: MixerApp) {
        guard let volume = volumes[app.id] else {
            taps.removeValue(forKey: app.id)?.invalidate()
            return
        }
        guard let outputUID = defaultOutputUID() else {
            mixerLog.error("No default output device, can't tap \(app.id, privacy: .public)")
            return
        }

        if let tap = taps[app.id],
           tap.processes == app.processes,
           tap.outputUID == outputUID {
            tap.gain = volume
            return
        }

        taps.removeValue(forKey: app.id)?.invalidate()
        taps[app.id] = ProcessTap(
            name: app.name,
            processes: app.processes,
            outputUID: outputUID,
            gain: volume
        )
        if taps[app.id] != nil {
            mixerLog.info("Tapped \(app.id, privacy: .public) processes \(app.processes, privacy: .public) on \(outputUID, privacy: .public)")
        }
    }
}

/// CORE AUDIO PROCESS HELPERS
private extension MixerService {
    func audioProcessObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr
        else { return [] }

        var objects = Array(
            repeating: AudioObjectID(0),
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr
        else { return [] }
        return objects
    }

    func processPID(_ object: AudioObjectID) -> pid_t? {
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr,
              pid > 0 else { return nil }
        return pid
    }

    func processBundleID(_ object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: unmanaged))
        let result = withUnsafeMutablePointer(to: &unmanaged) { ptr -> OSStatus in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, ptr)
        }
        guard result == noErr, let id = unmanaged?.takeRetainedValue() as String?,
              !id.isEmpty else { return nil }
        return id
    }

    func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectGetPropertyData(
            object, &address, 0, nil, &size, &running
        ) == noErr && running != 0
    }

    /// Resolves a pid to the outermost `.app` bundle of the app responsible for it
    /// so helper processes are grouped under their parent app. This covers helpers
    /// inside the bundle (e.g. browser renderers) and ones outside it, like the
    /// WebKit GPU process that plays Safari's audio. Processes with no app bundle
    /// (daemons, CLI tools) are skipped.
    func appBundleURL(for pid: pid_t) -> URL? {
        let owner = responsiblePID(for: pid)
        let running = NSRunningApplication(processIdentifier: owner)
        let url = running?.bundleURL ?? running?.executableURL ?? executablePath(for: owner)
        guard let url else { return nil }

        var outer = URL(fileURLWithPath: "/")
        for component in url.pathComponents.dropFirst() {
            outer.appendPathComponent(component)
            if component.hasSuffix(".app") { return outer }
        }
        return nil
    }

    /// The process macOS holds responsible for `pid` (an XPC service's host app).
    /// Private SPI looked up at runtime; falls back to `pid` when unavailable.
    func responsiblePID(for pid: pid_t) -> pid_t {
        guard let lookup = responsibilityLookup else { return pid }
        let owner = lookup(pid)
        return owner > 0 ? owner : pid
    }

    func executablePath(for pid: pid_t) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    func defaultOutputUID() -> String? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr else { return nil }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var unmanaged: Unmanaged<CFString>?
        size = UInt32(MemoryLayout.size(ofValue: unmanaged))
        let result = withUnsafeMutablePointer(to: &unmanaged) { ptr -> OSStatus in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, ptr)
        }
        guard result == noErr, let uid = unmanaged?.takeRetainedValue() else { return nil }
        return uid as String
    }
}

/// Gain shared between the main thread and the realtime IO thread. Stored as the
/// float's bit pattern since `Atomic` has no floating point support.
private final class Gain: Sendable {
    private let target: Atomic<UInt32>
    private let current: Atomic<UInt32>

    init(_ value: Float32) {
        target = Atomic(value.bitPattern)
        current = Atomic(value.bitPattern)
    }

    var value: Float32 {
        get { Float32(bitPattern: target.load(ordering: .relaxed)) }
        set { target.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// Returns (start, end) gain for the next buffer and advances, so slider
    /// moves ramp across a buffer instead of clicking.
    func advance() -> (Float32, Float32) {
        let start = Float32(bitPattern: current.load(ordering: .relaxed))
        let end = value
        current.store(end.bitPattern, ordering: .relaxed)
        return (start, end)
    }
}

/// A process tap + private aggregate device that replays the tapped processes'
/// audio on an output device at a given gain. Torn down on `invalidate()`.
final class ProcessTap: @unchecked Sendable {
    let processes: [AudioObjectID]
    let outputUID: String

    private let gainBox: Gain
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "switcher.ProcessTap", qos: .userInteractive)

    var gain: Float32 {
        get { gainBox.value }
        set { gainBox.value = newValue }
    }

    init?(name: String, processes: [AudioObjectID], outputUID: String, gain: Float32) {
        self.processes = processes
        self.outputUID = outputUID
        self.gainBox = Gain(gain)

        do {
            try start(name: name)
        } catch {
            mixerLog.error("Failed to tap \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            invalidate()
            return nil
        }
    }

    deinit { invalidate() }

    private func start(name: String) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "switcher: \(name)"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true

        try check(AudioHardwareCreateProcessTap(description, &tapID), "create tap")
        let tapChannels = Int(tapFormat()?.mChannelsPerFrame ?? 2)

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "switcher mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ],
            ],
        ]
        try check(
            AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
            "create aggregate device"
        )

        let gain = gainBox
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
                _, input, _, output, _ in
                ProcessTap.render(
                    input: UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)),
                    output: UnsafeMutableAudioBufferListPointer(output),
                    sourceChannels: tapChannels,
                    gain: gain.advance()
                )
            },
            "create IO proc"
        )
        try check(AudioDeviceStart(aggregateID, procID), "start device")
    }

    func invalidate() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func tapFormat() -> AudioStreamBasicDescription? {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr
        else { return nil }
        return format
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "\(step) failed (\(status))"]
            )
        }
    }

    /// Realtime render: copies the tap's channels (the last `sourceChannels` of the
    /// aggregate's input, after any input channels of the output sub-device) to the
    /// first output channels with gain applied. Extra output channels are silenced.
    /// Both sides are Float32, interleaved or not. No allocation or locking here.
    static func render(
        input: UnsafeMutableAudioBufferListPointer,
        output: UnsafeMutableAudioBufferListPointer,
        sourceChannels: Int,
        gain: (start: Float32, end: Float32)
    ) {
        var inputChannels = 0
        for buffer in input { inputChannels += Int(buffer.mNumberChannels) }
        let sourceOffset = max(0, inputChannels - sourceChannels)

        var outChannel = 0
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0,
                  let out = buffer.mData?.assumingMemoryBound(to: Float32.self)
            else { continue }
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * channels)

            for c in 0..<channels {
                defer { outChannel += 1 }
                guard outChannel < sourceChannels,
                      let source = channel(sourceOffset + outChannel, in: input)
                else {
                    for f in 0..<frames { out[f * channels + c] = 0 }
                    continue
                }

                let count = min(frames, source.frames)
                let step = count > 0 ? (gain.end - gain.start) / Float32(count) : 0
                for f in 0..<count {
                    let g = gain.start + step * Float32(f)
                    out[f * channels + c] = source.data[f * source.stride] * g
                }
                for f in count..<frames { out[f * channels + c] = 0 }
            }
        }
    }

    private static func channel(
        _ index: Int,
        in list: UnsafeMutableAudioBufferListPointer
    ) -> (data: UnsafePointer<Float32>, stride: Int, frames: Int)? {
        var base = 0
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            if index < base + channels {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float32.self)
                else { return nil }
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * channels)
                return (UnsafePointer(data + (index - base)), channels, frames)
            }
            base += channels
        }
        return nil
    }
}
