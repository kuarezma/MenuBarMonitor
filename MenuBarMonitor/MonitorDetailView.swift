import AppKit
import SwiftUI

struct MonitorDetailView: View {
    @ObservedObject var model: MonitorModel

    @State private var ramPurgeBusy = false
    @State private var ramPurgeStatus: String?

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
        }
        .padding(10)
        .frame(minWidth: 340, minHeight: 360)
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
                Button(ramPurgeBusy ? L10n.t("ram.purge.working") : L10n.t("ram.clean")) {
                    runRamPurge()
                }
                .disabled(ramPurgeBusy)
                .controlSize(.mini)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func ramPurgeStatusColor(_ status: String) -> Color {
        if status.contains("✓") { return .green }
        return .orange
    }

    private func runRamPurge() {
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
                        ramPurgeStatus = L10n.t("ram.purge.canceled")
                    } else {
                        ramPurgeStatus = String(format: L10n.t("ram.purge.errorFormat"), msg)
                    }
                } else {
                    ramPurgeStatus = L10n.t("ram.purge.success")
                }
            }
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
