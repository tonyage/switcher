//
//  Helpers.swift
//  switcher
//
//  Created by Tony Do on 7/23/25.
//

import CoreAudio

private extension AudioObjectPropertyAddress {
    init(
        _ selector: AudioObjectPropertySelector,
        _ scope: AudioObjectPropertyScope,
        _ element: AudioObjectPropertyElement
    ) {
        self.init(mSelector: selector, mScope: scope, mElement: element)
    }
}
