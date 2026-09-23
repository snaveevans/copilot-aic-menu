import AppKit

@MainActor
final class TokenInputView: NSView {
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 38, width: 370, height: 24))

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 370, height: 66))
        field.placeholderString = "github_pat_…"
        addSubview(field)

        let pasteButton = NSButton(title: "Paste from Clipboard", target: self, action: #selector(pasteFromClipboard))
        pasteButton.frame = NSRect(x: 0, y: 0, width: 170, height: 30)
        addSubview(pasteButton)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func pasteFromClipboard(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }
        field.stringValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        window?.makeFirstResponder(field)
    }
}
