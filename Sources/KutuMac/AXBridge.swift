import AppKit
import ApplicationServices
import KutuCore

/// Private, stable since 10.x, and the only way to correlate an AX window with
/// a window-server id. Isolated here so a future replacement touches one file.
@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindowPrivate(_ element: AXUIElement,
                                         _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

public struct ManagedWindow: Sendable {
    public let ref: KutuCore.WindowRef
    public let element: AXUIElement
    public init(ref: KutuCore.WindowRef, element: AXUIElement) {
        self.ref = ref
        self.element = element
    }
}

public enum AXBridge {
    /// Applications that hang must not hang kutu. Every element kutu talks to
    /// gets a hard messaging deadline.
    public static let messagingTimeout: Float = 0.25

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    public static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    public static func appElement(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    public static func windowID(of element: AXUIElement) -> WindowID? {
        var id: CGWindowID = 0
        guard AXUIElementGetWindowPrivate(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    public static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    public static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    public static func position(_ element: AXUIElement) -> CGPoint? {
        axValue(element, kAXPositionAttribute as String, .cgPoint, CGPoint.zero)
    }

    public static func size(_ element: AXUIElement) -> CGSize? {
        axValue(element, kAXSizeAttribute as String, .cgSize, CGSize.zero)
    }

    @discardableResult
    public static func setPosition(_ element: AXUIElement, _ point: CGPoint) -> Bool {
        var value = point
        guard let wrapped = AXValueCreate(.cgPoint, &value) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, wrapped) == .success
    }

    @discardableResult
    public static func raise(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    }

    public static func isFullScreen(_ element: AXUIElement) -> Bool {
        bool(element, "AXFullScreen") ?? false
    }

    /// Windows of one application, filtered to real, user-movable windows.
    public static func standardWindows(pid: pid_t, bundleID: String, appName: String) -> [ManagedWindow] {
        let app = appElement(pid: pid)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
              let elements = raw as? [AXUIElement] else { return [] }

        return elements.compactMap { element in
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            guard string(element, kAXRoleAttribute as String) == "AXWindow",
                  string(element, kAXSubroleAttribute as String) == "AXStandardWindow",
                  let id = windowID(of: element),
                  let origin = position(element),
                  let extent = size(element) else { return nil }
            let ref = KutuCore.WindowRef(
                id: id,
                pid: pid,
                bundleID: bundleID,
                appName: appName,
                title: string(element, kAXTitleAttribute as String) ?? "",
                frame: CGRect(origin: origin, size: extent),
                isFullScreen: isFullScreen(element))
            return ManagedWindow(ref: ref, element: element)
        }
    }

    /// Every managed window on the system. Finder is excluded because its
    /// "window" list includes the desktop, which must never be touched.
    public static func allStandardWindows() -> [ManagedWindow] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.bundleIdentifier != "com.apple.finder" }
            .flatMap { app in
                standardWindows(pid: app.processIdentifier,
                                bundleID: app.bundleIdentifier ?? "",
                                appName: app.localizedName ?? "")
            }
    }

    private static func axValue<T>(_ element: AXUIElement, _ attribute: String,
                                   _ type: AXValueType, _ empty: T) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let value = raw, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = empty
        guard AXValueGetValue((value as! AXValue), type, &result) else { return nil }
        return result
    }
}
