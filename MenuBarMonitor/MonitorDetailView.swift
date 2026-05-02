import AppKit
import SwiftUI

struct MonitorDetailView: View {
    @ObservedObject var model: MonitorModel

    @State private var ramPurgeBusy = false
    @State private var ramPurgeStatus: String?
    @State private var ramPurgeClearTask: Task<Void, Never>?
    @State private var showQuitAllConfirmation = false

    private var m: SystemMetricsSnapshot { model.systemMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("detail.liveSystem"))
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(topFiveRows) { row in
                    metricGridCell(row)
                }
            }

            Text(L10n.t("detail.coreLoads"))
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 8) {
                ForEach(corePairRows, id: \.slot) { row in
                    HStack(spacing: 8) {
                        coreCell(label: row.eLabel, value: row.eValue, color: row.eColor)
                        coreCell(label: row.pLabel, value: row.pValue, color: row.pColor)
                    }
                }
            }

            Divider()
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("quitAll.hint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showQuitAllConfirmation = true
                } label: {
                    Text(L10n.t("quitAll.button"))
                }
                .buttonStyle(NeonActionButtonStyle(palette: .shutdownWarm, isDimmed: false))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(minWidth: 340, minHeight: 420)
        .confirmationDialog(
            L10n.t("quitAll.confirmTitle"),
            isPresented: $showQuitAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.t("quitAll.confirmAction"), role: .destructive) {
                quitAllRegularUserApps()
            }
            Button(L10n.t("quitAll.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("quitAll.confirmMessage"))
        }
    }

    private var topFiveRows: [TopFiveRow] {
        [
            TopFiveRow(
                kind: .cpu,
                title: L10n.t("detail.cpuUsage"),
                value: pctOrDash(m.overallCpuPercent),
                color: loadColor(m.overallCpuPercent)
            ),
            TopFiveRow(
                kind: .ram,
                title: L10n.t("detail.ramUsage"),
                value: pctOrDash(m.ramUsedPercent),
                color: loadColor(m.ramUsedPercent)
            ),
            TopFiveRow(
                kind: .memoryPressure,
                title: L10n.t("detail.memoryPressure"),
                value: pctMemoryProxy(m.memoryProxyPercent),
                color: loadColor(m.memoryProxyPercent)
            ),
            TopFiveRow(
                kind: .thermal,
                title: L10n.t("detail.thermalState"),
                value: thermalValueLine,
                color: thermalColor(m.thermalState)
            ),
        ]
    }

    private var thermalValueLine: String {
        m.thermalLabelTR
    }

    private var corePairRows: [CorePairRow] {
        let eCores = m.cpuCores.filter { $0.label.hasPrefix("E") }
        let pCores = m.cpuCores.filter { $0.label.hasPrefix("P") }
        let rowCount = max(4, max(eCores.count, pCores.count))

        return (0..<rowCount).map { idx in
            let e = idx < eCores.count ? eCores[idx] : nil
            let p = idx < pCores.count ? pCores[idx] : nil
            return CorePairRow(
                slot: idx,
                eLabel: e?.label ?? "E\(idx)",
                eValue: e.map { String(format: "%.0f%%", min(100, max(0, $0.usagePercent))) } ?? "—",
                eColor: e.map { loadColor($0.usagePercent) } ?? .secondary,
                pLabel: p?.label ?? "P\(idx)",
                pValue: p.map { String(format: "%.0f%%", min(100, max(0, $0.usagePercent))) } ?? "—",
                pColor: p.map { loadColor($0.usagePercent) } ?? .secondary
            )
        }
    }

    @ViewBuilder
    private func metricGridCell(_ row: TopFiveRow) -> some View {
        switch row.kind {
        case .ram:
            ramUsageCell(row)
        default:
            standardMetricCell(row)
        }
    }

    private func standardMetricCell(_ row: TopFiveRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(row.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(row.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func ramUsageCell(_ row: TopFiveRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    runRamPurge()
                } label: {
                    Text(ramPurgeBusy ? L10n.t("ram.purge.working") : L10n.t("ram.clean"))
                }
                .disabled(ramPurgeBusy)
                .buttonStyle(NeonActionButtonStyle(palette: .memoryCool, isDimmed: ramPurgeBusy, compact: true))
            }
            Text(row.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(row.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let status = ramPurgeStatus, !status.isEmpty {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(ramPurgeStatusColor(status))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: ramPurgeStatus)
    }

    private func ramPurgeStatusColor(_ status: String) -> Color {
        if status.contains("✓") { return .green }
        return .orange
    }

    private func quitAllRegularUserApps() {
        let currentPID = NSRunningApplication.current.processIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications {
            guard app.processIdentifier != currentPID else { continue }
            guard app.activationPolicy == .regular else { continue }
            guard !app.isTerminated else { continue }
            if app.bundleIdentifier == "com.apple.finder" { continue }
            if let bid = app.bundleIdentifier, let ownBundleID, bid == ownBundleID { continue }
            _ = app.terminate()
        }
    }

    private func runRamPurge() {
        ramPurgeClearTask?.cancel()
        ramPurgeClearTask = nil
        ramPurgeBusy = true
        ramPurgeStatus = nil
        let source = #"do shell script "purge" with administrator privileges"#
        DispatchQueue.global(qos: .userInitiated).async {
            var errorDict: NSDictionary?
            let script = NSAppleScript(source: source)
            _ = script?.executeAndReturnError(&errorDict)
            DispatchQueue.main.async {
                ramPurgeBusy = false
                if let err = errorDict {
                    let msg = err[NSAppleScript.errorMessage] as? String ?? L10n.t("ram.purge.errorUnknown")
                    if msg.localizedCaseInsensitiveContains("canceled") || msg.localizedCaseInsensitiveContains("iptal") {
                        let text = L10n.t("ram.purge.canceled")
                        ramPurgeStatus = text
                        scheduleRamPurgeStatusAutoClear(expected: text)
                    } else {
                        let text = String(format: L10n.t("ram.purge.errorFormat"), msg)
                        ramPurgeStatus = text
                        scheduleRamPurgeStatusAutoClear(expected: text)
                    }
                } else {
                    let text = L10n.t("ram.purge.success")
                    ramPurgeStatus = text
                    scheduleRamPurgeStatusAutoClear(expected: text)
                }
            }
        }
    }

    private func scheduleRamPurgeStatusAutoClear(expected: String, delaySeconds: Double = 5) {
        ramPurgeClearTask?.cancel()
        ramPurgeClearTask = Task { @MainActor in
            let nanos = UInt64(delaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            if ramPurgeStatus == expected {
                withAnimation(.easeOut(duration: 0.35)) {
                    ramPurgeStatus = nil
                }
            }
            ramPurgeClearTask = nil
        }
    }

    private func coreCell(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func pctOrDash(_ v: Double?) -> String {
        guard let v else { return "—" }
        return String(format: "%.0f %%", min(100, max(0, v)))
    }

    private func pctMemoryProxy(_ v: Double) -> String {
        String(format: "%.0f %%", min(100, max(0, v)))
    }

    private func loadColor(_ value: Double?) -> Color {
        guard let v = value else { return .secondary }
        switch min(100, max(0, v)) {
        case ..<55: return .green
        case ..<75: return .yellow
        case ..<90: return .orange
        default: return .red
        }
    }

    private func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }
}

// MARK: - Neon action buttons

private enum NeonPalette {
    case memoryCool
    case shutdownWarm

    var gradientColors: [Color] {
        switch self {
        case .memoryCool:
            return [
                Color(red: 0.25, green: 0.55, blue: 1.0),
                Color(red: 0.45, green: 0.35, blue: 1.0),
                Color(red: 0.15, green: 0.82, blue: 0.88),
                Color(red: 0.35, green: 0.95, blue: 0.55),
                Color(red: 0.25, green: 0.55, blue: 1.0),
            ]
        case .shutdownWarm:
            return [
                Color(red: 1.0, green: 0.45, blue: 0.2),
                Color(red: 1.0, green: 0.25, blue: 0.55),
                Color(red: 0.95, green: 0.75, blue: 0.2),
                Color(red: 1.0, green: 0.35, blue: 0.15),
                Color(red: 1.0, green: 0.45, blue: 0.2),
            ]
        }
    }

    var glowColor: Color {
        switch self {
        case .memoryCool: return .cyan
        case .shutdownWarm: return .orange
        }
    }
}

private struct NeonActionButtonStyle: ButtonStyle {
    var palette: NeonPalette
    var isDimmed: Bool
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let hPad: CGFloat = compact ? 8 : 14
        let vPad: CGFloat = compact ? 4 : 8
        let font: Font = compact
            ? .system(size: 10, weight: .bold, design: .rounded)
            : .system(size: 12, weight: .bold, design: .rounded)
        let corner: CGFloat = compact ? 8 : 11

        return TimelineView(.animation(minimumInterval: 1.0 / 36.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let spinDegrees = (t.truncatingRemainder(dividingBy: compact ? 3.6 : 4.8) / (compact ? 3.6 : 4.8)) * 360.0
            let glowPulse = (sin(t * 2.4) + 1) * 0.5

            configuration.label
                .font(font)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(
                                AngularGradient(
                                    gradient: Gradient(colors: palette.gradientColors),
                                    center: .center,
                                    angle: .degrees(spinDegrees)
                                )
                            )
                            .opacity(isDimmed ? 0.52 : 1)
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.55),
                                        .white.opacity(0.08),
                                        .white.opacity(0.35),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                }
                .shadow(
                    color: palette.glowColor.opacity(0.32 + glowPulse * 0.38),
                    radius: 5 + glowPulse * 9,
                    y: 2
                )
                .scaleEffect(configuration.isPressed ? (compact ? 0.93 : 0.96) : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.68), value: configuration.isPressed)
        }
    }
}

private enum MetricKind: String {
    case cpu
    case ram
    case memoryPressure
    case thermal
}

private struct TopFiveRow: Identifiable {
    var id: MetricKind { kind }
    let kind: MetricKind
    let title: String
    let value: String
    let color: Color
}

private struct CorePairRow {
    let slot: Int
    let eLabel: String
    let eValue: String
    let eColor: Color
    let pLabel: String
    let pValue: String
    let pColor: Color
}
