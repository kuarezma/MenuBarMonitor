import Darwin
import Foundation

/// Yaklaşık üç saniyelik örneklemede hesaplanan sistem göstergeleri (CPU, RAM, bellek vekili, termal).
struct SystemMetricsSnapshot {
    var overallCpuPercent: Double?
    var ramUsedPercent: Double?
    /// Bellek veri yolu / yoğunluk vekili (0…100); `MemoryPressureMonitor` birleşik skoru; gerçek DRAM bant genişliği değildir.
    var memoryProxyPercent: Double
    var thermalState: ProcessInfo.ThermalState
    /// Termal duruma göre kabaca “ısı yükü” 0…100 (°C değil).
    var thermalHeatLoadApprox: Int
    var thermalDisplayLabel: String
    var cpuCores: [CPUCoreDisplay]
    var cpuFootnote: String
    var ramFootnote: String
    var memoryProxyFootnote: String
    var thermalFootnote: String

    /// Menü çubuğu: CPU, RAM, termal kodu, bellek vekili; ağ yok (≤ ~22 karakter hedefi).
    var compactMenuBarLabel: String {
        let cStr: String
        if let c = overallCpuPercent {
            cStr = String(format: "%.0f", min(100, max(0, c)))
        } else {
            cStr = "–"
        }
        let rStr: String
        if let r = ramUsedPercent {
            rStr = String(format: "%.0f", min(100, max(0, r)))
        } else {
            rStr = "–"
        }
        let mStr = String(format: "%.0f", min(100, max(0, memoryProxyPercent)))
        let tChar = Self.thermalMenuToken(thermalState)
        // Örnek: C23 R71 n M~40 (monospaced font uygulamada)
        return "C\(cStr) R\(rStr) \(tChar) M~\(mStr)"
    }

    /// n / f / s / k — açıklama açılır pencerede.
    private static func thermalMenuToken(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "n"
        case .fair: return "f"
        case .serious: return "s"
        case .critical: return "k"
        @unknown default: return "?"
        }
    }
}

enum SystemMetrics {
    private static func pageSize() -> vm_size_t {
        var p: vm_size_t = 0
        let kr = host_page_size(mach_host_self(), &p)
        if kr == KERN_SUCCESS, p > 0 { return p }
        return vm_size_t(vm_kernel_page_size)
    }

    private static func ramUsedPercent(vm: vm_statistics64, physical: UInt64, pageSize: vm_size_t) -> (pct: Double?, footnote: String) {
        guard physical > 0 else {
            return (nil, L10n.t("ram.noPhysicalMemory"))
        }
        let ps = UInt64(pageSize)
        let active = UInt64(vm.active_count)
        let wired = UInt64(vm.wire_count)
        let compressedPages = UInt64(vm.compressor_page_count)
        let usedPages = active &+ wired &+ compressedPages
        let usedBytes = usedPages &* ps
        let pct = min(100.0, max(0.0, Double(usedBytes) / Double(physical) * 100.0))
        return (pct, L10n.t("ram.usedLongFootnote"))
    }

    private static func thermalMapping(_ state: ProcessInfo.ThermalState) -> (displayLabel: String, heat0to100: Int, footnote: String) {
        switch state {
        case .nominal:
            return (
                L10n.t("thermal.low"),
                15,
                L10n.t("thermal.footnote.nominal")
            )
        case .fair:
            return (
                L10n.t("thermal.medium"),
                40,
                L10n.t("thermal.footnote.fair")
            )
        case .serious:
            return (
                L10n.t("thermal.high"),
                70,
                L10n.t("thermal.footnote.serious")
            )
        case .critical:
            return (
                L10n.t("thermal.high"),
                95,
                L10n.t("thermal.footnote.critical")
            )
        @unknown default:
            return (
                L10n.t("thermal.medium"),
                50,
                L10n.t("thermal.footnote.unknown")
            )
        }
    }

    /// CPU örneklemi + tek `HOST_VM_INFO64` okuması + `MemoryPressureMonitor` vekili; ağ hariç.
    static func poll() -> SystemMetricsSnapshot {
        let cpu = CPUStats.poll()
        let physical = ProcessInfo.processInfo.physicalMemory
        let psize = pageSize()
        let vmCur = MemoryPressureMonitor.readHostVMInfo64()
        let memPressure = MemoryPressureMonitor.poll(currentVM: vmCur)

        let ram: (pct: Double?, footnote: String)
        if let v = vmCur {
            ram = ramUsedPercent(vm: v, physical: physical, pageSize: psize)
        } else {
            ram = (nil, L10n.t("ram.hostStatsUnavailable"))
        }

        let thermalState = ProcessInfo.processInfo.thermalState
        let thermal = thermalMapping(thermalState)

        return SystemMetricsSnapshot(
            overallCpuPercent: cpu.overallCpuPercent,
            ramUsedPercent: ram.pct,
            memoryProxyPercent: memPressure.proxyPercent,
            thermalState: thermalState,
            thermalHeatLoadApprox: thermal.heat0to100,
            thermalDisplayLabel: thermal.displayLabel,
            cpuCores: cpu.cores,
            cpuFootnote: cpu.footnote,
            ramFootnote: ram.footnote,
            memoryProxyFootnote: memPressure.footnote,
            thermalFootnote: thermal.footnote
        )
    }
}

extension SystemMetricsSnapshot {
    static let placeholder = SystemMetricsSnapshot(
        overallCpuPercent: nil,
        ramUsedPercent: nil,
        memoryProxyPercent: 0,
        thermalState: .nominal,
        thermalHeatLoadApprox: 0,
        thermalDisplayLabel: "—",
        cpuCores: [],
        cpuFootnote: "",
        ramFootnote: "",
        memoryProxyFootnote: "",
        thermalFootnote: ""
    )

    /// Menü etiketindeki tek harfli termal kodun açıklaması.
    static let menuThermalLegend = L10n.t("menu.thermalLegend")
}

enum L10n {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
