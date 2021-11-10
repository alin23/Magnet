//
//  HotKey.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Cocoa
import Carbon

public final class HotKey: NSObject {

    // MARK: - Properties
    public let identifier: String
    public let keyCombo: KeyCombo
    public let callback: ((HotKey) -> Void)?
    public let target: AnyObject?
    public let action: Selector?
    public let actionQueue: ActionQueue
    public var detectKeyHold = false
    public var forwardNextEvent = false

    var hotKeyId: UInt32?
    var hotKeyRef: EventHotKeyRef?

    // MARK: - Enum Value
    public enum ActionQueue {
        case main
        case session

        public func execute(closure: @escaping () -> Void) {
            switch self {
            case .main:
                DispatchQueue.main.async {
                    closure()
                }
            case .session:
                closure()
            }
        }
    }

    // MARK: - Initialize
    public init(identifier: String, keyCombo: KeyCombo, target: AnyObject, action: Selector, actionQueue: ActionQueue = .main, detectKeyHold: Bool = false) {
        self.identifier = identifier
        self.keyCombo = keyCombo
        self.callback = nil
        self.target = target
        self.action = action
        self.actionQueue = actionQueue
        self.detectKeyHold = detectKeyHold
        super.init()
    }

    public init(identifier: String, keyCombo: KeyCombo, actionQueue: ActionQueue = .main, detectKeyHold: Bool = false, handler: @escaping ((HotKey) -> Void)) {
        self.identifier = identifier
        self.keyCombo = keyCombo
        self.callback = handler
        self.target = nil
        self.action = nil
        self.actionQueue = actionQueue
        self.detectKeyHold = detectKeyHold
        super.init()
    }

}

// MARK: - Invoke
public extension HotKey {
    func invoke() -> OSStatus {
        guard let callback = self.callback else {
            guard let target = self.target as? NSObject, let selector = self.action else { return OSStatus(eventNotHandledErr) }
            guard target.responds(to: selector) else { return OSStatus(eventNotHandledErr) }
            actionQueue.execute { [weak self] in
                guard let wSelf = self else { return }
                target.perform(selector, with: wSelf)
            }
            return OSStatus(noErr)
        }
        actionQueue.execute { [weak self] in
            guard let wSelf = self else { return }
            callback(wSelf)
        }

        if forwardNextEvent {
            forwardNextEvent = false
            return OSStatus(eventNotHandledErr)
        }

        return OSStatus(noErr)
    }
}

// MARK: - Register & UnRegister
public extension HotKey {
    @discardableResult
    func register() -> Bool {
        return HotKeyCenter.shared.register(with: self)
    }

    func unregister() {
        return HotKeyCenter.shared.unregister(with: self)
    }
}

// MARK: - override isEqual
public extension HotKey {
    override func isEqual(_ object: Any?) -> Bool {
        guard let hotKey = object as? HotKey else { return false }

        return self.identifier == hotKey.identifier &&
               self.keyCombo == hotKey.keyCombo &&
               self.hotKeyId == hotKey.hotKeyId &&
               self.hotKeyRef == hotKey.hotKeyRef
    }
}
