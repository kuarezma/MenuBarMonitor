import AppKit
import Combine
import Foundation

@MainActor
final class MonitorModel: ObservableObject {
    static let shared = MonitorModel()

    /// Mantıksal durum düz metinde emoji; menü çubuğunda gerçek boyut için `NSTextAttachment` daire kullanılır (emoji punto ile küçülmez).
    private static let statusDotCharacters: Set<Character> = ["🟢", "🟡", "🟠", "🔴", "⚪"]
    /// Menü çubuğunda çizilen daire çapı (pt).
    private static let statusDotDiameterPoints: CGFloat = 9

    /// Harf/rakam (C, R, M~, sayılar): noktadan bağımsız; menü çubuğunda ~11–14 pt aralığı makul.
    private static let statusBarTextPointSize: CGFloat = 13

    private static var statusBarMonospaceFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: statusBarTextPointSize, weight: .semibold)
    }

    private static var statusBarTextAttributes: [NSAttributedString.Key: Any] {
        [.font: statusBarMonospaceFont, .foregroundColor: NSColor.labelColor]
    }

    /// Menü çubuğu: CPU, RAM, termal kodu, bellek vekili.
    @Published private(set) var menuBarLabel: String = "…"
    @Published private(set) var statusBarDisplayLabel: String = "⚪C– ⚪R– ⚪? ⚪M~–"
    @Published private(set) var statusBarAttributedTitle: NSAttributedString = MonitorModel.makeAttributedStatusBarLabel("⚪C– ⚪R– ⚪? ⚪M~–")

    /// Bir saniyede bir kez güncellenen birleşik sistem göstergeleri.
    @Published private(set) var systemMetrics: SystemMetricsSnapshot = .placeholder

    private var timerCancellable: AnyCancellable?

    private init() {
        start()
    }

    func start() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 3.0, tolerance: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        let metrics = SystemMetrics.poll()
        systemMetrics = metrics
        menuBarLabel = metrics.compactMenuBarLabel
        let plain = makeStatusBarDisplayLabel(metrics)
        statusBarDisplayLabel = plain
        statusBarAttributedTitle = Self.makeAttributedStatusBarLabel(plain)
    }

    private func makeStatusBarDisplayLabel(_ metrics: SystemMetricsSnapshot) -> String {
        let cpu = pctText(metrics.overallCpuPercent)
        let ram = pctText(metrics.ramUsedPercent)
        let mem = String(Int(clamped(metrics.memoryProxyPercent)))
        let t = thermalToken(metrics.thermalState)
        let cpuDot = loadDot(metrics.overallCpuPercent)
        let ramDot = loadDot(metrics.ramUsedPercent)
        let memDot = loadDot(metrics.memoryProxyPercent)
        let tDot = thermalDot(metrics.thermalState)
        return "\(cpuDot)C\(cpu) \(ramDot)R\(ram) \(tDot)\(t) \(memDot)M~\(mem)"
    }

    private func pctText(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(Int(clamped(value)))
    }

    private func clamped(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private func loadDot(_ value: Double?) -> String {
        guard let v = value else { return "⚪" }
        switch clamped(v) {
        case ..<55: return "🟢"
        case ..<75: return "🟡"
        case ..<90: return "🟠"
        default: return "🔴"
        }
    }

    private func thermalDot(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "🟢"
        case .fair: return "🟡"
        case .serious: return "🟠"
        case .critical: return "🔴"
        @unknown default: return "⚪"
        }
    }

    private func thermalToken(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "n"
        case .fair: return "f"
        case .serious: return "s"
        case .critical: return "k"
        @unknown default: return "?"
        }
    }

    /// Rakamlar/harfler `statusBarTextPointSize`; renkli gösterge `statusDotDiameterPoints` attachment.
    static func makeAttributedStatusBarLabel(_ plain: String) -> NSAttributedString {
        let textFont = Self.statusBarMonospaceFont
        let result = NSMutableAttributedString()
        for ch in plain {
            if Self.statusDotCharacters.contains(ch) {
                result.append(Self.attributedStatusDot(replacing: ch, textFont: textFont))
            } else {
                result.append(NSAttributedString(string: String(ch), attributes: Self.statusBarTextAttributes))
            }
        }
        return result
    }

    private static func statusDotNSColor(for ch: Character) -> NSColor {
        switch ch {
        case "🟢": return .systemGreen
        case "🟡": return .systemYellow
        case "🟠": return .systemOrange
        case "🔴": return .systemRed
        default: return .tertiaryLabelColor
        }
    }

    private static func statusDotImage(color: NSColor, diameter: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            color.setFill()
            let inset: CGFloat = 0.35
            NSBezierPath(ovalIn: rect.insetBy(dx: inset, dy: inset)).fill()
            return true
        }
    }

    /// Daireyi satırdaki yazıyla dikeyde ortalar: `NSTextAttachment.bounds.origin.y` satır kutusuna göre ayarlanır.
    private static func statusDotAttachmentBounds(textFont: NSFont, diameter d: CGFloat) -> NSRect {
        // Satır kutusu ortası (baz çizgisine göre); büyük harf + rakam bandına yakın optik merkez.
        let midY = (textFont.ascender + textFont.descender) / 2
        var y = midY - d / 2
        // İnce ayar: monospaced semibold ile küçük daireler bir tık aşağıda kalıyorsa hafif yukarı.
        y += 0.35
        return NSRect(x: 0, y: floor(y * 4) / 4, width: d, height: d)
    }

    private static func attributedStatusDot(replacing ch: Character, textFont: NSFont) -> NSAttributedString {
        let d = statusDotDiameterPoints
        let attachment = NSTextAttachment()
        attachment.image = statusDotImage(color: statusDotNSColor(for: ch), diameter: d)
        attachment.bounds = statusDotAttachmentBounds(textFont: textFont, diameter: d)
        let piece = NSMutableAttributedString(attachment: attachment)
        piece.addAttribute(.font, value: textFont, range: NSRange(location: 0, length: piece.length))
        return piece
    }
}
