// secret-prompt: a translucent themed panel that asks for one secret and
// prints it to stdout (exit 0), or exits 1 on cancel. Meant to be called by
// asudo and with-secret, never bare by an agent. See docs/design.md.
import AppKit

func roundedMask(radius: CGFloat) -> NSImage {
    let edge = radius * 2 + 1
    let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

func pill(_ title: String, fill: NSColor, ink: NSColor, key: String, action: Selector, target: AnyObject) -> NSButton {
    let button = NSButton(title: title, target: target, action: action)
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.backgroundColor = fill.cgColor
    button.layer?.cornerRadius = 8
    button.attributedTitle = NSAttributedString(
        string: title,
        attributes: [.foregroundColor: ink, .font: NSFont.systemFont(ofSize: 13, weight: .semibold)])
    button.keyEquivalent = key
    button.translatesAutoresizingMaskIntoConstraints = false
    button.heightAnchor.constraint(equalToConstant: 32).isActive = true
    return button
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.alignment = .center
    return field
}

final class Prompt: NSObject, NSApplicationDelegate {
    let options: Options
    let theme: Theme
    let width: CGFloat
    let panel: Panel
    let field = NSSecureTextField()
    let plain = NSTextField()
    let eye = NSButton()
    var revealed = false
    var activeField: NSTextField { revealed ? plain : field }

    init(_ options: Options, _ theme: Theme) {
        self.options = options
        self.theme = theme
        width = options.command == nil ? 360 : 420
        panel = Panel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 260),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }

    func applicationDidFinishLaunching(_: Notification) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let capturable = ProcessInfo.processInfo.environment["SECRET_PROMPT_CAPTURABLE"] == "1"
        panel.sharingType = capturable ? .readOnly : .none
        panel.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)

        let blur = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        // The window server blurs the whole rect; only maskImage rounds the blur and the shadow.
        blur.maskImage = roundedMask(radius: 16)
        panel.contentView = blur

        let tint = NSView(frame: blur.bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.layer?.backgroundColor = theme.faded("background", theme.opacity).cgColor
        tint.layer?.cornerRadius = 16
        tint.layer?.borderWidth = 1
        tint.layer?.borderColor = theme.faded("raised", 0.7).cgColor
        blur.addSubview(tint)

        let icon = NSImageView()
        let symbol = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        icon.image = (NSImage(systemSymbolName: options.icon, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil))?
            .withSymbolConfiguration(symbol)
        icon.contentTintColor = theme["accent"]

        var views: [NSView] = [icon, label(options.title, size: 15, weight: .semibold, color: theme["text"])]
        var gaps: [NSView: CGFloat] = [icon: 14]
        if let message = options.message {
            views.append(label(message, size: 12, weight: .regular, color: theme["subtext"]))
        }
        if let command = options.command {
            let well = commandWell(command)
            gaps[views.last!] = 14
            views.append(well)
        }
        if let error = options.error {
            gaps[views.last!] = 12
            views.append(label(error, size: 12, weight: .medium, color: theme["error"]))
        }
        gaps[views.last!] = 20

        let input = inputWell()
        let buttons = NSStackView(views: [
            pill("Cancel", fill: theme["raised"], ink: theme["text"], key: "\u{1b}", action: #selector(cancel(_:)), target: self),
            pill(options.button, fill: theme["accent"], ink: theme["background"], key: "\r", action: #selector(submit(_:)), target: self),
        ])
        buttons.distribution = .fillEqually
        buttons.spacing = 10
        views += [input, buttons]
        gaps[input] = 16

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        for (view, gap) in gaps { stack.setCustomSpacing(gap, after: view) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: blur.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -28),
        ])
        for view in views.dropFirst() {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        blur.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: width, height: stack.fittingSize.height + 56))

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: area.midX - panel.frame.width / 2,
                y: area.midY - panel.frame.height / 2 + area.height * 0.08))
        }

        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        (panel.fieldEditor(true, for: field) as? NSTextView)?.insertionPointColor = theme["accent"]
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }, completionHandler: { [self] in
            if options.error != nil { shake() }
        })
    }

    func commandWell(_ command: String) -> NSView {
        let text = NSTextField(wrappingLabelWithString: command)
        text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.textColor = theme["command"]
        text.maximumNumberOfLines = 3
        text.cell?.truncatesLastVisibleLine = true
        text.lineBreakMode = .byWordWrapping
        text.toolTip = command
        text.translatesAutoresizingMaskIntoConstraints = false
        return well(around: text, fill: theme.faded("surface", 0.7), border: nil, inset: 8)
    }

    func inputWell() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(eye)
        for input in [field, plain] {
            input.isBordered = false
            input.drawsBackground = false
            input.focusRingType = .none
            input.textColor = theme["text"]
            input.font = .systemFont(ofSize: 14)
            input.placeholderAttributedString = NSAttributedString(
                string: options.placeholder,
                attributes: [.foregroundColor: theme["muted"], .font: NSFont.systemFont(ofSize: 14)])
            input.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(input)
            NSLayoutConstraint.activate([
                input.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                input.trailingAnchor.constraint(equalTo: eye.leadingAnchor, constant: -8),
                input.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
        }
        plain.isHidden = true

        eye.isBordered = false
        eye.target = self
        eye.action = #selector(toggleReveal(_:))
        eye.refusesFirstResponder = true
        eye.keyEquivalent = "h"
        eye.keyEquivalentModifierMask = [.command, .shift]
        eye.contentTintColor = theme["muted"]
        eye.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            eye.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            eye.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            eye.widthAnchor.constraint(equalToConstant: 20),
            row.heightAnchor.constraint(equalTo: field.heightAnchor),
        ])
        showEye()

        let box = well(around: row, fill: theme.faded("surface", 0.9), border: theme["accent"], inset: 9)
        box.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return box
    }

    func well(around content: NSView, fill: NSColor, border: NSColor?, inset: CGFloat) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = fill.cgColor
        box.layer?.cornerRadius = 8
        if let border {
            box.layer?.borderWidth = 1.5
            box.layer?.borderColor = border.cgColor
        }
        box.addSubview(content)
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -12),
            content.topAnchor.constraint(greaterThanOrEqualTo: box.topAnchor, constant: inset),
            content.bottomAnchor.constraint(lessThanOrEqualTo: box.bottomAnchor, constant: -inset),
            content.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    func shake() {
        let origin = panel.frame.origin
        let path = CGMutablePath()
        path.move(to: origin)
        for offset: CGFloat in [-10, 8, -6, 4, -2] {
            path.addLine(to: CGPoint(x: origin.x + offset, y: origin.y))
        }
        path.addLine(to: origin)
        let animation = CAKeyframeAnimation()
        animation.path = path
        animation.duration = 0.35
        panel.animations = ["frameOrigin": animation]
        panel.animator().setFrameOrigin(origin)
    }

    func showEye() {
        let symbol = revealed ? "eye.slash" : "eye"
        eye.image = NSImage(systemSymbolName: symbol, accessibilityDescription: revealed ? "Hide" : "Show")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .medium))
        eye.toolTip = revealed ? "Hide (⌘⇧H)" : "Show (⌘⇧H)"
    }

    // Two fields rather than one toggled: NSSecureTextField cannot show its text.
    // The hidden one is emptied, so the value only ever lives in the visible one.
    @objc func toggleReveal(_: Any?) {
        let value = activeField.stringValue
        activeField.stringValue = ""
        revealed.toggle()
        activeField.stringValue = value
        field.isHidden = revealed
        plain.isHidden = !revealed
        showEye()
        panel.makeFirstResponder(activeField)
        if let editor = activeField.currentEditor() as? NSTextView {
            editor.insertionPointColor = theme["accent"]
            editor.selectedRange = NSRange(location: (value as NSString).length, length: 0)
        }
    }

    @objc func submit(_: Any?) {
        FileHandle.standardOutput.write(Data((activeField.stringValue + "\n").utf8))
        exit(0)
    }

    @objc func cancel(_: Any?) { exit(1) }
}

// AppKit otherwise logs an exception in a delegate and carries on, leaving an
// invisible panel that sudo would wait on forever; crashing fails the caller.
UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--dump-theme"] {
    let path = Theme.configPath
    FileHandle.standardOutput.write(Data(Theme.load(from: path).dump(path: path).utf8))
    exit(0)
}
let options = Options(arguments)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = Prompt(options, Theme.load())
app.delegate = delegate
app.run()
