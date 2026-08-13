import AppKit
import Carbon.HIToolbox
import KutuCore

/// A process-wide hotkey. Carbon's RegisterEventHotKey is the only API that
/// works without asking for Input Monitoring on top of Accessibility.
public final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: () -> Void

    nonisolated(unsafe) private static var registry: [UInt32: HotKey] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1

    public init?(spec: String, handler: @escaping () -> Void) {
        guard let parsed = HotKeySpec.parse(spec) else { return nil }
        self.handler = handler

        var modifiers: UInt32 = 0
        if parsed.usesCommand { modifiers |= UInt32(cmdKey) }
        if parsed.usesOption { modifiers |= UInt32(optionKey) }
        if parsed.usesControl { modifiers |= UInt32(controlKey) }
        if parsed.usesShift { modifiers |= UInt32(shiftKey) }

        let id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.registry[id] = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            HotKey.registry[hotKeyID.id]?.handler()
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x6B757475), id: id)  // 'kutu'
        let status = RegisterEventHotKey(parsed.keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else {
            HotKey.registry.removeValue(forKey: id)
            return nil
        }
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    deinit { unregister() }
}
