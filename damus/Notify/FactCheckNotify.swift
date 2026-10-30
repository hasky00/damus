//
//  FactCheckNotify.swift
//  damus
//
//  Damus Labs: open the fact-check sheet for a note.
//

import Foundation

struct FactCheckNotify: Notify {
    typealias Payload = NostrEvent
    var payload: NostrEvent
}

extension NotifyHandler {
    static var fact_check: NotifyHandler<FactCheckNotify> {
        .init()
    }
}

extension Notifications {
    static func fact_check(_ note: NostrEvent) -> Notifications<FactCheckNotify> {
        .init(.init(payload: note))
    }
}
