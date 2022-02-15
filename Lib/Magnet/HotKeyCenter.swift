//
//  HotKeyCenter.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Carbon
import Cocoa
import Combine
import Foundation

private extension NSRecursiveLock {
    @inline(__always) func aroundThrows<T>(
        timeout: TimeInterval = 10,
        ignoreMainThread: Bool = false,
        _ closure: () throws -> T
    ) throws -> T {
        if ignoreMainThread, Thread.isMainThread {
            return try closure()
        }

        let locked = lock(before: Date().addingTimeInterval(timeout))
        defer { if locked { unlock() } }

        return try closure()
    }

    @inline(__always) func around<T>(timeout: TimeInterval = 10, ignoreMainThread: Bool = false, _ closure: () -> T) -> T {
        if ignoreMainThread, Thread.isMainThread {
            return closure()
        }

        let locked = lock(before: Date().addingTimeInterval(timeout))
        defer { if locked { unlock() } }

        return closure()
    }

    @inline(__always) func around(timeout: TimeInterval = 10, ignoreMainThread: Bool = false, _ closure: () -> Void) {
        if ignoreMainThread, Thread.isMainThread {
            return closure()
        }

        let locked = lock(before: Date().addingTimeInterval(timeout))
        defer { if locked { unlock() } }

        closure()
    }
}

extension UserDefaults {
    @objc var keyRepeat: Double {
        get { return double(forKey: "KeyRepeat") }
        set { set(newValue, forKey: "KeyRepeat") }
    }

    @objc var initialKeyRepeat: Double {
        get { return double(forKey: "InitialKeyRepeat") }
        set { set(newValue, forKey: "InitialKeyRepeat") }
    }
}

public final class HotKeyCenter {
    // MARK: - Properties

    private let lock = NSRecursiveLock()
    public static let shared = HotKeyCenter()

    private var hotKeys = [String: HotKey]()
    private var hotKeyCount: UInt32 = 0
    private let modifierEventHandler: ModifierEventHandler
    private let notificationCenter: NotificationCenter
    private var keyHoldInvoker: Timer?
    private var keyHoldInvokeCreator: DispatchWorkItem?
    public var detectKeyHold = true

    private static var keyRepeatIntervalObserver = UserDefaults.standard
        .publisher(for: \.keyRepeat)
        .sink { interval in
            HotKeyCenter.keyRepeatInterval = max(interval, 2) * 0.015
        }

    public static var keyRepeatInterval = max(UserDefaults.standard.keyRepeat, 2) * 0.015

    private static var initialKeyRepeatIntervalObserver = UserDefaults.standard
        .publisher(for: \.initialKeyRepeat)
        .sink { interval in
            HotKeyCenter.initialKeyRepeatInterval = max(interval, 15) * 0.015
        }

    public static var initialKeyRepeatInterval = max(UserDefaults.standard.initialKeyRepeat, 15) * 0.015

    // MARK: - Initialize

    init(modifierEventHandler: ModifierEventHandler = .init(), notificationCenter: NotificationCenter = .default, detectKeyHold: Bool = true) {
        self.modifierEventHandler = modifierEventHandler
        self.notificationCenter = notificationCenter
        self.detectKeyHold = detectKeyHold

        installHotKeyEventHandler()

        installModifiersChangedEventHandlerIfNeeded()
        observeApplicationTerminate()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }
}

// MARK: - Register & Unregister

public extension HotKeyCenter {
    @discardableResult
    func register(with hotKey: HotKey) -> Bool {
        let exists = lock.around { () -> Bool in
            guard !hotKeys.keys.contains(hotKey.identifier) else { return true }
            guard !hotKeys.values.contains(hotKey) else { return true }

            hotKeys[hotKey.identifier] = hotKey
            return false
        }
        guard !exists else { return false }
        guard !hotKey.keyCombo.doubledModifiers else { return true }
        /*
         *  Normal macOS shortcut
         *
         *  Discussion:
         *    When registering a hotkey, a KeyCode that conforms to the
         *    keyboard layout at the time of registration is registered.
         *    To register a `v` on the QWERTY keyboard, `9` is registered,
         *    and to register a `v` on the Dvorak keyboard, `47` is registered.
         *    Therefore, if you change the keyboard layout after registering
         *    a hot key, the hot key is not assigned to the correct key.
         *    To solve this problem, you need to re-register the hotkeys
         *    when you change the layout, but it's not supported by the
         *    Apple Genuine app either, so it's not supported now.
         */
        let hotKeyId = EventHotKeyID(signature: UTGetOSTypeFromString("Magnet" as CFString), id: hotKeyCount)
        var carbonHotKey: EventHotKeyRef?
        let error = RegisterEventHotKey(
            UInt32(hotKey.keyCombo.currentKeyCode),
            UInt32(hotKey.keyCombo.modifiers),
            hotKeyId,
            GetEventDispatcherTarget(),
            0,
            &carbonHotKey
        )
        guard error == noErr else {
            if hotKey.hotKeyRef != nil {
                unregister(with: hotKey)
            }
            return false
        }
        hotKey.hotKeyId = hotKeyId.id
        hotKey.hotKeyRef = carbonHotKey
        hotKeyCount += 1

        return true
    }

    func unregister(with hotKey: HotKey) {
        guard let carbonHotKey = hotKey.hotKeyRef else {
            return
        }
        UnregisterEventHotKey(carbonHotKey)
        _ = lock.around {
            hotKeys.removeValue(forKey: hotKey.identifier)
        }
        hotKey.hotKeyId = nil
        hotKey.hotKeyRef = nil
    }

    @discardableResult
    func unregisterHotKey(with identifier: String) -> Bool {
        return lock.around {
            guard let hotKey = hotKeys[identifier] else { return false }
            unregister(with: hotKey)
            return true
        }
    }

    func unregisterAll() {
        lock.around {
            hotKeys.forEach { unregister(with: $1) }
        }
    }
}

// MARK: - Terminate

extension HotKeyCenter {
    private func observeApplicationTerminate() {
        notificationCenter.addObserver(
            self,
            selector: #selector(HotKeyCenter.applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    @objc func applicationWillTerminate() {
        keyHoldInvokeCreator?.cancel()
        keyHoldInvoker?.invalidate()
        unregisterAll()
    }
}

// MARK: - HotKey Events

var pressedEventHandler: EventHandlerRef?
var pressedEventType = EventTypeSpec()
var pressedEventHandlerRunning = false

var releasedEventHandler: EventHandlerRef?
var releasedEventType = EventTypeSpec()
var releasedEventHandlerRunning = false

public extension HotKeyCenter {
    func pauseEventHandler() {
        guard pressedEventHandlerRunning, let pressedEventHandler = pressedEventHandler else {
            return
        }
        pressedEventHandlerRunning = false
        RemoveEventTypesFromHandler(pressedEventHandler, 1, &pressedEventType)
    }

    func resumeEventHandler() {
        guard !pressedEventHandlerRunning else {
            return
        }
        pressedEventHandlerRunning = true
        AddEventTypesToHandler(pressedEventHandler, 1, &pressedEventType)
    }
}

private extension HotKeyCenter {
    func installPressedEventHandler() {
        pressedEventType.eventClass = OSType(kEventClassKeyboard)
        pressedEventType.eventKind = OSType(kEventHotKeyPressed)

        InstallEventHandler(GetEventDispatcherTarget(), { callRef, inEvent, _ -> OSStatus in
            let result = HotKeyCenter.shared.sendPressedKeyboardEvent(inEvent!)
            guard result != eventNotHandledErr else {
                return CallNextEventHandler(callRef, inEvent!)
            }
            return result
        }, 1, &pressedEventType, nil, &pressedEventHandler)
        pressedEventHandlerRunning = true
    }

    func installReleasedEventHandler() {
        releasedEventType.eventClass = OSType(kEventClassKeyboard)
        releasedEventType.eventKind = OSType(kEventHotKeyReleased)
        InstallEventHandler(GetEventDispatcherTarget(), { _, inEvent, _ -> OSStatus in
            HotKeyCenter.shared.sendReleasedKeyboardEvent(inEvent!)
        }, 1, &releasedEventType, nil, &releasedEventHandler)
        releasedEventHandlerRunning = true
    }

    func installHotKeyEventHandler() {
        installPressedEventHandler()
        installReleasedEventHandler()
    }

    func sendReleasedKeyboardEvent(_ event: EventRef) -> OSStatus {
        assert(Int(GetEventClass(event)) == kEventClassKeyboard, "Unknown event class")

        var hotKeyId = EventHotKeyID()
        let error = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamName(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyId
        )

        guard error == noErr else { return error }
        assert(hotKeyId.signature == UTGetOSTypeFromString("Magnet" as CFString), "Invalid hot key id")

        switch GetEventKind(event) {
        case EventParamName(kEventHotKeyReleased):
            keyHoldInvoker?.invalidate()
            keyHoldInvokeCreator?.cancel()
        default:
            assertionFailure("Unknown event kind")
        }
        return noErr
    }

    func sendPressedKeyboardEvent(_ event: EventRef) -> OSStatus {
        assert(Int(GetEventClass(event)) == kEventClassKeyboard, "Unknown event class")

        var hotKeyId = EventHotKeyID()
        let error = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamName(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyId
        )

        guard error == noErr else { return error }
        assert(hotKeyId.signature == UTGetOSTypeFromString("Magnet" as CFString), "Invalid hot key id")

        let hotKey = lock.around { hotKeys.values.first(where: { $0.hotKeyId == hotKeyId.id }) }
        var result = noErr

        switch GetEventKind(event) {
        case EventParamName(kEventHotKeyPressed):
            if let hotKey = hotKey {
                result = hotKey.invoke()
                if detectKeyHold, hotKey.detectKeyHold {
                    keyHoldInvokeCreator = DispatchWorkItem { [weak self] in
                        guard let self = self, let creator = self.keyHoldInvokeCreator, !creator.isCancelled else { return }

                        self.keyHoldInvoker = Timer.scheduledTimer(withTimeInterval: HotKeyCenter.keyRepeatInterval, repeats: true) { [weak self] timer in
                            guard let self = self,
                                  let hotKey = self.lock.around({ self.hotKeys.values.first(where: { $0.hotKeyId == hotKeyId.id }) })
                            else {
                                timer.invalidate()
                                return
                            }
                            _ = hotKey.invoke()
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + HotKeyCenter.initialKeyRepeatInterval, execute: keyHoldInvokeCreator!)
                }
            }
        default:
            assertionFailure("Unknown event kind")
        }
        return result
    }
}

// MARK: - Double Tap Modifier Event

private extension HotKeyCenter {
    func installModifiersChangedEventHandlerIfNeeded() {
        NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.modifierEventHandler.handleModifiersEvent(with: event.modifierFlags, timestamp: event.timestamp)
        }
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event -> NSEvent? in
            self?.modifierEventHandler.handleModifiersEvent(with: event.modifierFlags, timestamp: event.timestamp)
            return event
        }
        modifierEventHandler.doubleTapped = { [weak self] tappedModifierFlags in
            guard let self = self else { return }
            self.lock.around {
                self.hotKeys.values
                    .filter { $0.keyCombo.doubledModifiers }
                    .filter { $0.keyCombo.modifiers == tappedModifierFlags.carbonModifiers() }
                    .forEach { _ = $0.invoke() }
            }
        }
    }
}
