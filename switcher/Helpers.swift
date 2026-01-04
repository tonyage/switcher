//
//  Helpers.swift
//  switcher
//
//  Created by Tony Do on 7/23/25.
//

import CoreAudio

extension AudioChannelLayout {
    /// Hopefully safe and idiomatic swift way of wrapping unsafe pointers to memory
    /// for walking C arrays
    func channelDescriptions() -> UnsafeBufferPointer<AudioChannelDescription> {
        UnsafeBufferPointer(
            start: UnsafeRawPointer(withUnsafePointer(to: self) { $0 })?
                .advanced(by: MemoryLayout<AudioChannelLayout>.size)
                .assumingMemoryBound(to: AudioChannelDescription.self),
            count: Int(mNumberChannelDescriptions)
        )
    }
}
