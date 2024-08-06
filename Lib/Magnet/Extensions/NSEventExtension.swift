//
//  NSEventExtension.swift
//
//  Magnet
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Copyright © 2015-2020 Clipy Project.
//

import Carbon
import Cocoa
import Sauce

public extension NSEvent.ModifierFlags {
    static let leftCommand = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCMDKEYMASK))
    static let rightCommand = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCMDKEYMASK))
    static let leftOption = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELALTKEYMASK))
    static let rightOption = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERALTKEYMASK))
    static let leftShift = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELSHIFTKEYMASK))
    static let rightShift = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERSHIFTKEYMASK))
    static let leftControl = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCTLKEYMASK))
    static let rightControl = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCTLKEYMASK))
    static let fn = NSEvent.ModifierFlags(rawValue: UInt(0x80))
    static let hyper = NSEvent.ModifierFlags([.command, .control, .option, .shift])
    static let meh = NSEvent.ModifierFlags([.control, .option, .shift])
}

public extension NSEvent.ModifierFlags {
    var containsSupportedModifiers: Bool {
        !filterUnsupportedModifiers().isEmpty
    }

    var isSingleFlags: Bool {
        let commandSelected = contains(.command)
        let optionSelected = contains(.option)
        let controlSelected = contains(.control)
        let shiftSelected = contains(.shift)
        return [commandSelected, optionSelected, controlSelected, shiftSelected].trueCount == 1
    }

    var deviceIndependentFlags: NSEvent.ModifierFlags {
        return NSEvent.ModifierFlags(rawValue: rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)
    }

    /// Returns a new `NSEvent.ModifierFlags` instance that contains only the supported modifier flags.
    /// Supported modifier flags are `.command`, `.option`, `.control`, `.shift`, `.function`, `.leftCommand`, `.rightCommand`, `.leftOption`, `.rightOption`, `.leftShift`, `.rightShift`, `.leftControl`, and `.rightControl`.
    func filterUnsupportedModifiers() -> NSEvent.ModifierFlags {
        intersection([
            .command, .option, .control, .shift, .function,
            .leftCommand, .rightCommand,
            .leftOption, .rightOption,
            .leftShift, .rightShift,
            .leftControl, .rightControl,
        ])
    }

    func filterNotShiftModifiers() -> NSEvent.ModifierFlags {
        guard contains(.shift) else { return NSEvent.ModifierFlags(rawValue: 0) }
        return .shift
    }

    func keyEquivalentStrings() -> [String] {
        var strings = [String]()
        if contains(.control) {
            strings.append("⌃")
        }
        if contains(.option) {
            strings.append("⌥")
        }
        if contains(.shift) {
            strings.append("⇧")
        }
        if contains(.command) {
            strings.append("⌘")
        }
        return strings
    }
}

public let rightCmdKey = rightControlKey << 1

public extension Int {
    func carbonModifiersString(isSupportFunctionKey: Bool = false) -> [String] {
        var carbonModifiers: [String] = []
        if self & cmdKey != 0 {
            carbonModifiers.append("cmd")
        }
        if self & optionKey != 0 {
            carbonModifiers.append("option")
        }
        if self & controlKey != 0 {
            carbonModifiers.append("control")
        }
        if self & shiftKey != 0 {
            carbonModifiers.append("shift")
        }

        if self & rightCmdKey != 0 {
            carbonModifiers.append("rightCmd")
        }
        if self & rightOptionKey != 0 {
            carbonModifiers.append("rightOption")
        }
        if self & rightControlKey != 0 {
            carbonModifiers.append("rightControl")
        }
        if self & rightShiftKey != 0 {
            carbonModifiers.append("rightShift")
        }

        if self & Int(NSEvent.ModifierFlags.function.rawValue) != 0, isSupportFunctionKey {
            carbonModifiers.append("fn")
        }
        return carbonModifiers
    }
}

public extension NSEvent.ModifierFlags {
    func carbonString(isSupportFunctionKey: Bool = false) -> [String] {
        carbonModifiers(isSupportFunctionKey: isSupportFunctionKey).carbonModifiersString(isSupportFunctionKey: isSupportFunctionKey)
    }

    init(carbonModifiers: Int) {
        var result = NSEvent.ModifierFlags(rawValue: 0)
        if (carbonModifiers & cmdKey) != 0 {
            result.insert(.command)
            if (carbonModifiers & rightCmdKey) != 0 {
                result.insert(.rightCommand)
            } else {
                result.insert(.leftCommand)
            }
        }

        if (carbonModifiers & optionKey) != 0 {
            result.insert(.option)
            if (carbonModifiers & rightOptionKey) != 0 {
                result.insert(.rightOption)
            } else {
                result.insert(.leftOption)
            }
        }

        if (carbonModifiers & controlKey) != 0 {
            result.insert(.control)
            if (carbonModifiers & rightControlKey) != 0 {
                result.insert(.rightControl)
            } else {
                result.insert(.leftControl)
            }
        }

        if (carbonModifiers & shiftKey) != 0 {
            result.insert(.shift)
            if (carbonModifiers & rightShiftKey) != 0 {
                result.insert(.rightShift)
            } else {
                result.insert(.leftShift)
            }
        }

        self = result
    }

    func carbonModifiers(isSupportFunctionKey: Bool = false) -> Int {
        var carbonModifiers: Int = 0
        if contains(.command) {
            carbonModifiers |= cmdKey
        }
        if contains(.option) {
            carbonModifiers |= optionKey
        }
        if contains(.control) {
            carbonModifiers |= controlKey
        }
        if contains(.shift) {
            carbonModifiers |= shiftKey
        }

        if contains(.rightCommand) {
            carbonModifiers |= rightCmdKey
        }
        if contains(.rightOption) {
            carbonModifiers |= rightOptionKey
        }
        if contains(.rightControl) {
            carbonModifiers |= rightControlKey
        }
        if contains(.rightShift) {
            carbonModifiers |= rightShiftKey
        }

        if contains(.function), isSupportFunctionKey {
            carbonModifiers |= Int(NSEvent.ModifierFlags.function.rawValue)
        }
        return carbonModifiers
    }
}

private extension NSEvent.EventType {
    var isKeyboardEvent: Bool {
        return [.keyUp, .keyDown, .flagsChanged].contains(self)
    }
}

public extension NSEvent {
    /// Returns a matching `KeyCombo` for the event, if the event is a keyboard event and the key is recognized.
    var keyCombo: KeyCombo? {
        guard type.isKeyboardEvent else { return nil }
        guard let key = Sauce.shared.key(for: Int(self.keyCode)) else { return nil }
        return KeyCombo(key: key, cocoaModifiers: modifierFlags)
    }
}
