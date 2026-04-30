import AppKit

/// `NSStatusBarButton` + `NSEvent.addLocalMonitorForEvents` is unreliable for secondary clicks:
/// status items live in `NSStatusBarWindow`; those events often never reach the app’s local monitor
/// (especially with `LSUIElement`). A custom view receives `mouseDown` / `rightMouseDown` directly.
@MainActor
protocol StatusItemHostViewDelegate: AnyObject {
    func statusItemHostViewDidLeftClick(_ view: StatusItemHostView)
    func statusItemHostViewDidRightClick(_ view: StatusItemHostView)
}

@MainActor
final class StatusItemHostView: NSView {
    weak var delegate: StatusItemHostViewDelegate?

    private let textField: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.isBordered = false
        tf.drawsBackground = false
        tf.backgroundColor = .clear
        tf.isEditable = false
        tf.isSelectable = false
        tf.lineBreakMode = .byClipping
        tf.maximumNumberOfLines = 1
        tf.cell?.usesSingleLineMode = true
        return tf
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Keep hit testing on this view so the label never swallows clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    func update(attributedTitle: NSAttributedString) {
        textField.attributedStringValue = attributedTitle
        let thickness = NSStatusBar.system.thickness
        let padX: CGFloat = 8
        let textRect = attributedTitle.boundingRect(
            with: NSSize(width: 10_000, height: thickness),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let w = ceil(textRect.width) + padX * 2
        let frame = NSRect(x: 0, y: 0, width: w, height: thickness)
        if frame.size != self.frame.size {
            self.frame = frame
        }
        textField.frame = NSRect(
            x: padX,
            y: floor((thickness - ceil(textRect.height)) / 2),
            width: max(0, w - padX * 2),
            height: ceil(textRect.height)
        )
    }

    override func mouseDown(with event: NSEvent) {
        if event.buttonNumber == 0 {
            delegate?.statusItemHostViewDidLeftClick(self)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.statusItemHostViewDidRightClick(self)
    }
}
