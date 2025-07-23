//
//  Listener.swift
//  switcher
//
//  Created by Tony Do on 7/23/25.
//

import Combine
import CoreAudio
import Foundation

final class AudioHardwareListener {
    private let subject = PassthroughSubject<Void, Never>()
    
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    
    var publisher: AnyPublisher<Void, Never> {
        subject.eraseToAnyPublisher()
    }
    
    nonisolated let dispatchQueue = DispatchQueue(
        label: "switcher.AudioHardwareListener.coreaudio"
    )
    nonisolated let listener: AudioObjectPropertyListenerBlock
    
    init() {
        listener = { [weak subject] _, _ in subject?.send() }
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            dispatchQueue,
            listener
        )
    }
    
    deinit {
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            dispatchQueue,
            listener
        )
    }
}
