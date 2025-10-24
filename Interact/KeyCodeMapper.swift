import Carbon.HIToolbox
import CoreGraphics

enum KeyCodeMapper {
    private static let mapping: [String: CGKeyCode] = [
        "a": CGKeyCode(kVK_ANSI_A),
        "b": CGKeyCode(kVK_ANSI_B),
        "c": CGKeyCode(kVK_ANSI_C),
        "d": CGKeyCode(kVK_ANSI_D),
        "e": CGKeyCode(kVK_ANSI_E),
        "f": CGKeyCode(kVK_ANSI_F),
        "g": CGKeyCode(kVK_ANSI_G),
        "h": CGKeyCode(kVK_ANSI_H),
        "i": CGKeyCode(kVK_ANSI_I),
        "j": CGKeyCode(kVK_ANSI_J),
        "k": CGKeyCode(kVK_ANSI_K),
        "l": CGKeyCode(kVK_ANSI_L),
        "m": CGKeyCode(kVK_ANSI_M),
        "n": CGKeyCode(kVK_ANSI_N),
        "o": CGKeyCode(kVK_ANSI_O),
        "p": CGKeyCode(kVK_ANSI_P),
        "q": CGKeyCode(kVK_ANSI_Q),
        "r": CGKeyCode(kVK_ANSI_R),
        "s": CGKeyCode(kVK_ANSI_S),
        "t": CGKeyCode(kVK_ANSI_T),
        "u": CGKeyCode(kVK_ANSI_U),
        "v": CGKeyCode(kVK_ANSI_V),
        "w": CGKeyCode(kVK_ANSI_W),
        "x": CGKeyCode(kVK_ANSI_X),
        "y": CGKeyCode(kVK_ANSI_Y),
        "z": CGKeyCode(kVK_ANSI_Z),
        "0": CGKeyCode(kVK_ANSI_0),
        "1": CGKeyCode(kVK_ANSI_1),
        "2": CGKeyCode(kVK_ANSI_2),
        "3": CGKeyCode(kVK_ANSI_3),
        "4": CGKeyCode(kVK_ANSI_4),
        "5": CGKeyCode(kVK_ANSI_5),
        "6": CGKeyCode(kVK_ANSI_6),
        "7": CGKeyCode(kVK_ANSI_7),
        "8": CGKeyCode(kVK_ANSI_8),
        "9": CGKeyCode(kVK_ANSI_9),
        "-": CGKeyCode(kVK_ANSI_Minus),
        "=": CGKeyCode(kVK_ANSI_Equal),
        "[": CGKeyCode(kVK_ANSI_LeftBracket),
        "]": CGKeyCode(kVK_ANSI_RightBracket),
        "\\": CGKeyCode(kVK_ANSI_Backslash),
        ";": CGKeyCode(kVK_ANSI_Semicolon),
        "'": CGKeyCode(kVK_ANSI_Quote),
        "`": CGKeyCode(kVK_ANSI_Grave),
        ",": CGKeyCode(kVK_ANSI_Comma),
        ".": CGKeyCode(kVK_ANSI_Period),
        "/": CGKeyCode(kVK_ANSI_Slash),
        "space": CGKeyCode(kVK_Space),
        "spacebar": CGKeyCode(kVK_Space),
        "tab": CGKeyCode(kVK_Tab),
        "escape": CGKeyCode(kVK_Escape),
        "esc": CGKeyCode(kVK_Escape),
        "return": CGKeyCode(kVK_Return),
        "enter": CGKeyCode(kVK_Return),
        "delete": CGKeyCode(kVK_Delete),
        "backspace": CGKeyCode(kVK_Delete),
        "forwarddelete": CGKeyCode(kVK_ForwardDelete),
        "home": CGKeyCode(kVK_Home),
        "end": CGKeyCode(kVK_End),
        "pageup": CGKeyCode(kVK_PageUp),
        "pagedown": CGKeyCode(kVK_PageDown),
        "up": CGKeyCode(kVK_UpArrow),
        "down": CGKeyCode(kVK_DownArrow),
        "left": CGKeyCode(kVK_LeftArrow),
        "right": CGKeyCode(kVK_RightArrow),
        "f1": CGKeyCode(kVK_F1),
        "f2": CGKeyCode(kVK_F2),
        "f3": CGKeyCode(kVK_F3),
        "f4": CGKeyCode(kVK_F4),
        "f5": CGKeyCode(kVK_F5),
        "f6": CGKeyCode(kVK_F6),
        "f7": CGKeyCode(kVK_F7),
        "f8": CGKeyCode(kVK_F8),
        "f9": CGKeyCode(kVK_F9),
        "f10": CGKeyCode(kVK_F10),
        "f11": CGKeyCode(kVK_F11),
        "f12": CGKeyCode(kVK_F12)
    ]

    static func keyCode(for input: String) -> CGKeyCode? {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.count == 1, let character = normalized.first, character.isLetter || character.isNumber {
            return mapping[String(character)]
        }

        return mapping[normalized]
    }
}
