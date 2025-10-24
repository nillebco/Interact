import Foundation

struct ShortcutInput {
    var key: String = ""
    var useCommand = false
    var useOption = false
    var useControl = false
    var useShift = false

    var modifiers: Set<KeyboardModifier> {
        var collection = Set<KeyboardModifier>()
        if useCommand { collection.insert(.command) }
        if useOption { collection.insert(.option) }
        if useControl { collection.insert(.control) }
        if useShift { collection.insert(.shift) }
        return collection
    }

    mutating func reset() {
        key = ""
        useCommand = false
        useOption = false
        useControl = false
        useShift = false
    }
}
