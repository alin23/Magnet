## Upgrading from Magnet v2.x to 3.x

### `KeyCombo` initializer
The standard initializer, `KeyCombo(keyCode:carbonModifiers:)` & `KeyCombo(keyCode:cocoaModifiers:)`, is removed.  
This change was necessary to set the correct shortcut keys on non-QWERTY keyboards.

If you want to keep the same settings, use the following initializer.

```swift
KeyCombo(QWERTYKeyCode:carbonModifiers:)
KeyCombo(QWERTYKeyCode:cocoaModifiers:)
```

The recommended initializer in the future is to use enum of [Key](https://github.com/Clipy/Sauce/blob/v2.0.2/Lib/Sauce/Key.swift) which is independent of keyCode.

```swift
KeyCombo(key:carbonModifiers:)
KeyCombo(key:cocoaModifiers:)
```

This will set the correct shortcut for any keyboard layout you use.

### About key code
Previously `KeyCombo.keyCode` kept the KeyCode that was set during initialization.  
Starting from v3.0.0, `KeyCombo.currentKeyCode` returns the correct key code for the currently set keyboard layout.

```swift
let keyCombo = KeyCombo(key: v, cocoaModifiers: [.shift])
```

In QWERTY keyboard layout.

```swift
print(keyCombo.currentKeyCode) // return 9
```

In Dvorak keyboard layout.

```swift
print(keyCombo.currentKeyCode) // return 47
```

If you want to get the old `KeyCombo.keyCode`, change it to `KeyCombo.QWERTYKeyCode`.

### About characters
Previously, `KeyCombo.characters` did not add modifiers correctly.  
As of v3.0.0, `KeyCombo.characters` returns a string that takes into account the following qualifier.

```swift
let keyCombo = KeyCombo(key: .v, cocoaModifiers: [.command])
print(keyCombo.characters) // return v
let keyCombo = KeyCombo(key: .v, cocoaModifiers: [.shift])
print(keyCombo.characters) // return V
let keyCombo = KeyCombo(key: .v, cocoaModifiers: [.option])
print(keyCombo.characters) // return √
let keyCombo = KeyCombo(key: .v, cocoaModifiers: [.option, .shift])
print(keyCombo.characters) // return ◊
```

If you want to get the same string as before, use `KeyCombo.keyEquivalent.uppercased()`.

```swift
let keyCombo = KeyCombo(key: .v, cocoaModifiers: [.command])
print(keyCombo.keyEquivalent) // return v
let keyCombo = KeyCombo(key: .v, cocoaModifiers: [.shift])
print(keyCombo.keyEquivalent) // return V
let keyCombo = KeyCombo(key: .v, cocoaModifiers: [.option])
print(keyCombo.keyEquivalent) // return v
let keyCombo = KeyCombo(key: .v, cocoaModifiers: [.option, .shift])
print(keyCombo.keyEquivalent) // return V
```

**Important**  
`KeyCombo.keyEquivalent` is case-sensitive depending on whether the shift is typed or not.

### Removed `KeyCodeTransformer` and `KeyTransformer`
- `KeyCodeTransformer.shared.transformValue(:)` This method has been migrated to the [Sauce.framework](https://github.com/Clipy/Sauce/tree/v2.0.0#character).
- The methods of `KeyTransformer` have been migrated to their respective extensions.
  - https://github.com/Clipy/Magnet/blob/v3.0.4/Lib/Magnet/Extensions/IntExtension.swift
  - https://github.com/Clipy/Magnet/blob/v3.0.4/Lib/Magnet/Extensions/KeyExtension.swift
  - https://github.com/Clipy/Magnet/blob/v3.0.4/Lib/Magnet/Extensions/NSEventExtension.swift
