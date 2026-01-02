//
//  Listener.swift
//  switcher
//
//  Created by Tony Do on 7/23/25.
//

import Combine
import CoreAudio
import Foundation

typealias ListenerBlock = (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

/// Uncertain how useful this class is instead of treating the service also as a data
/// model and managing these lifecycles there. Works for now and is snappy.
final class AudioHardwareListener {
    private var blocks: [AudioObjectPropertySelector: ListenerBlock] = [:]
    
    var onDevicesChanged: (() -> Void)?
    var onDeviceChanged: (() -> Void)?
    
    private var selectors = [
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioHardwarePropertyDefaultInputDevice,
    ]
    
    nonisolated let dispatchQueue = DispatchQueue(
        label: "switcher.AudioHardwareListener.coreaudio"
    )
    
    private func handler(_ selector: AudioObjectPropertySelector) {
        switch selector {
            case kAudioHardwarePropertyDevices:
                onDevicesChanged?()
            case kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice:
                onDeviceChanged?()
            default:
                break
        }
    }
    
    func start() {
        for selector in selectors {
            addListener(selector: selector)
        }
    }
    
    func stop() {
        for selector in selectors {
            removeListener(selector: selector)
        }
    }
    
    deinit { stop() }
}

private extension AudioHardwareListener {
    func addListener(selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let block: ListenerBlock = { [weak self] _, _ in
            self?.handler(selector)
        }
        
        blocks[selector] = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            dispatchQueue,
            block
        )
    }

    func removeListener(selector: AudioObjectPropertySelector) {
        guard let block = blocks[selector] else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            dispatchQueue,
            block
        )
        
        blocks.removeValue(forKey: selector)
    }
}
