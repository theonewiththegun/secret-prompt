import AppKit

struct RGBA: Equatable {
    var hex: UInt32
    var alpha: CGFloat = 1

    var color: NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }

    var text: String {
        alpha == 1
            ? String(format: "#%06X", hex)
            : String(format: "#%06X%02X", hex, Int((alpha * 255).rounded()))
    }

    // #RRGGBB or #RRGGBBAA, the # optional.
    init?(parsing raw: String) {
        let digits = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt32(digits, radix: 16)
        else { return nil }
        if digits.count == 8 {
            hex = value >> 8
            alpha = CGFloat(value & 0xFF) / 255
        } else {
            hex = value
        }
    }

    init(_ hex: UInt32) { self.hex = hex }
}

struct Theme {
    // The order --dump-theme prints them in, and the only keys besides theme, appearance, opacity.
    static let roles = ["background", "surface", "raised", "muted", "subtext", "command", "text", "accent", "error"]

    var name: String
    var dark: Bool
    var colors: [String: RGBA]
    var opacity: CGFloat = 0.55

    subscript(role: String) -> NSColor { colors[role]!.color }

    static func catppuccin(_ name: String, dark: Bool, _ hexes: [UInt32]) -> Theme {
        Theme(name: name, dark: dark, colors: Dictionary(uniqueKeysWithValues: zip(roles, hexes.map(RGBA.init))))
    }

    // Catppuccin base, surface0, surface1, overlay0, subtext0, subtext1, text, mauve, red.
    static let presets: [String: Theme] = [
        "catppuccin-mocha": catppuccin("catppuccin-mocha", dark: true, [
            0x1E1E2E, 0x313244, 0x45475A, 0x6C7086, 0xA6ADC8, 0xBAC2DE, 0xCDD6F4, 0xCBA6F7, 0xF38BA8,
        ]),
        "catppuccin-macchiato": catppuccin("catppuccin-macchiato", dark: true, [
            0x24273A, 0x363A4F, 0x494D64, 0x6E738D, 0xA5ADCB, 0xB8C0E0, 0xCAD3F5, 0xC6A0F6, 0xED8796,
        ]),
        "catppuccin-frappe": catppuccin("catppuccin-frappe", dark: true, [
            0x303446, 0x414559, 0x51576D, 0x737994, 0xA5ADCE, 0xB5BFE2, 0xC6D0F5, 0xCA9EE6, 0xE78284,
        ]),
        "catppuccin-latte": catppuccin("catppuccin-latte", dark: false, [
            0xEFF1F5, 0xCCD0DA, 0xBCC0CC, 0x9CA0B0, 0x6C6F85, 0x5C5F77, 0x4C4F69, 0x8839EF, 0xD20F39,
        ]),
    ]

    static let fallback = "catppuccin-mocha"

    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    static func preset(_ name: String) -> Theme? {
        name == "system"
            ? presets[systemIsDark ? "catppuccin-mocha" : "catppuccin-latte"]
            : presets[name]
    }

    static var configPath: String {
        let env = ProcessInfo.processInfo.environment
        if let path = env["SECRET_PROMPT_CONFIG"], !path.isEmpty { return path }
        let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory() + "/.config"
        return base + "/secret-prompt/config"
    }

    // A broken line warns and falls back rather than failing: this file must
    // never be the reason a sudo prompt does not appear.
    static func load(from path: String = configPath) -> Theme {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return presets[fallback]!
        }
        func warn(_ line: Int, _ why: String) {
            FileHandle.standardError.write(Data("secret-prompt: \(path):\(line): \(why), ignored\n".utf8))
        }

        var entries: [(line: Int, key: String, value: String)] = []
        for (index, raw) in contents.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else {
                warn(index + 1, "expected key = value")
                continue
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.first == "\"", value.last == "\"" {
                value = String(value.dropFirst().dropLast())
            }
            entries.append((index + 1, key, value))
        }

        // The preset first, wherever it sits in the file, so overrides always land on top of it.
        var theme = presets[fallback]!
        for entry in entries where entry.key == "theme" {
            if let named = preset(entry.value.lowercased()) {
                theme = named
            } else {
                let known = (["system"] + presets.keys.sorted()).joined(separator: ", ")
                warn(entry.line, "unknown theme '\(entry.value)' (known: \(known))")
            }
        }
        for entry in entries {
            switch entry.key {
            case "theme":
                continue
            case "appearance":
                switch entry.value.lowercased() {
                case "dark": theme.dark = true
                case "light": theme.dark = false
                default: warn(entry.line, "appearance must be dark or light, got '\(entry.value)'")
                }
            case "opacity":
                if let value = Double(entry.value), (0...1).contains(value) {
                    theme.opacity = CGFloat(value)
                } else {
                    warn(entry.line, "opacity must be a number from 0 to 1, got '\(entry.value)'")
                }
            case let role where roles.contains(role):
                if let color = RGBA(parsing: entry.value) {
                    theme.colors[role] = color
                } else {
                    warn(entry.line, "\(role) must be #RRGGBB or #RRGGBBAA, got '\(entry.value)'")
                }
            default:
                warn(entry.line, "unknown key '\(entry.key)'")
            }
        }
        return theme
    }

    // The same key = value shape the config reads, so the output can seed one.
    func dump(path: String) -> String {
        let found = FileManager.default.fileExists(atPath: path)
        var lines = [
            "# \(path)\(found ? "" : " (not found, defaults shown)")",
            "theme = \(name)",
            "appearance = \(dark ? "dark" : "light")",
            "opacity = \(String(format: "%.2f", opacity))",
        ]
        lines += Theme.roles.map { "\($0) = \(colors[$0]!.text)" }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension Theme {
    // The panel's own translucency, multiplied into whatever alpha the user gave the role.
    func faded(_ role: String, _ factor: CGFloat) -> NSColor {
        let rgba = colors[role]!
        return rgba.color.withAlphaComponent(rgba.alpha * factor)
    }
}
