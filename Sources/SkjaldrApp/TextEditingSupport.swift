import AppKit

enum TextEditingAction: Equatable {
    case cut
    case copy
    case paste
    case selectAll

    var selector: Selector {
        switch self {
        case .cut:
            #selector(NSText.cut(_:))
        case .copy:
            #selector(NSText.copy(_:))
        case .paste:
            #selector(NSText.paste(_:))
        case .selectAll:
            #selector(NSText.selectAll(_:))
        }
    }
}

enum TextEditingShortcut {
    static func action(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> TextEditingAction? {
        let normalized = modifiers.intersection(.deviceIndependentFlagsMask)
        guard normalized == .command else { return nil }
        switch keyCode {
        case 7: return .cut
        case 8: return .copy
        case 9: return .paste
        case 0: return .selectAll
        default: return nil
        }
    }

    static func action(for event: NSEvent) -> TextEditingAction? {
        action(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }
}

@MainActor
enum TextEditingSupport {
    private static weak var activeEditor: NSTextView?

    static func isEditingText(_ responder: NSResponder?) -> Bool {
        textEditor(for: responder) != nil
    }

    @discardableResult
    static func performIfEditing(_ action: TextEditingAction) -> Bool {
        performIfEditing(
            action,
            responder: NSApp.keyWindow?.firstResponder
        )
    }

    @discardableResult
    static func performIfEditing(
        _ action: TextEditingAction,
        responder: NSResponder?
    ) -> Bool {
        guard let textView = textEditor(for: responder) ?? activeEditor,
              textView.window === NSApp.keyWindow
        else {
            return false
        }
        return NSApp.sendAction(
            action.selector,
            to: textView,
            from: nil
        )
    }

    static func enableSystemSpelling(
        from notification: Notification,
        in window: NSWindow?
    ) {
        let textView: NSTextView?
        if let editor = notification.object as? NSTextView {
            textView = editor
        } else if let textField = notification.object as? NSTextField {
            textView = textField.currentEditor() as? NSTextView
        } else {
            textView = nil
        }

        guard let textView, textView.window === window else { return }
        enableSystemSpelling(on: textView)
        activeEditor = textView
    }

    static func finishEditing(from notification: Notification) {
        let textView: NSTextView?
        if let editor = notification.object as? NSTextView {
            textView = editor
        } else if let textField = notification.object as? NSTextField {
            textView = textField.currentEditor() as? NSTextView
        } else {
            textView = nil
        }
        if textView == nil || textView === activeEditor {
            activeEditor = nil
        }
    }

    static func enableSystemSpelling(on textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = true
    }

    private static func textEditor(
        for responder: NSResponder?
    ) -> NSTextView? {
        if let textView = responder as? NSTextView {
            return textView
        }
        if let textField = responder as? NSTextField {
            return textField.currentEditor() as? NSTextView
        }
        return nil
    }
}
