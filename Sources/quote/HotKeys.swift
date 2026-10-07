import Carbon
import Foundation

enum HotKeyID: UInt32 {
    case typeNote = 1
    case talk = 2
    case send = 3
}

@MainActor
final class HotKeyCenter {
    private var handlerRef: EventHandlerRef?
    private let onEvent: (HotKeyID) -> Void

    init(onEvent: @escaping (HotKeyID) -> Void) {
        self.onEvent = onEvent
    }

    func install() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard err == noErr else { return err }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            let id = HotKeyID(rawValue: hotKeyID.id) ?? .typeNote
            MainActor.assumeIsolated {
                center.onEvent(id)
            }
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )

        // ⌘G
        register(keyCode: 5, modifiers: UInt32(cmdKey), id: .typeNote)
        // ⌘E
        register(keyCode: 14, modifiers: UInt32(cmdKey), id: .talk)
        // ⌃⌘V
        register(keyCode: 9, modifiers: UInt32(cmdKey | controlKey), id: .send)
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: HotKeyID) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5154_4555), id: id.rawValue) // 'QTEU'
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }
}
