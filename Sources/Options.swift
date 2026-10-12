import Foundation

struct Options {
    var title = "Authentication required"
    var message: String?
    var command: String?
    var placeholder = "Password"
    var button = "Continue"
    var icon = "lock.fill"
    var error: String?

    static let usage = """
        usage: secret-prompt [--title T] [--message M] [--command C] [--placeholder P]
                             [--button B] [--icon SF-SYMBOL] [--error E] [PROMPT]
               secret-prompt --dump-theme
        """

    // A bare argument is what sudo passes an askpass: its own prompt, used as the placeholder.
    init(_ args: [String]) {
        var rest = args[...]
        while let arg = rest.popFirst() {
            guard arg.hasPrefix("--") else {
                let hint = arg.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                if !hint.isEmpty { placeholder = hint }
                continue
            }
            guard let value = rest.popFirst() else { Options.fail("\(arg) needs a value") }
            switch arg {
            case "--title": title = value
            case "--message": message = value
            case "--command": command = value
            case "--placeholder": placeholder = value
            case "--button": button = value
            case "--icon": icon = value
            case "--error": error = value
            default: Options.fail("unknown option \(arg)")
            }
        }
    }

    static func fail(_ why: String) -> Never {
        FileHandle.standardError.write(Data("secret-prompt: \(why)\n\(usage)\n".utf8))
        exit(2)
    }
}
