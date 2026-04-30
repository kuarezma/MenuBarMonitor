import Darwin

struct CPUSample: Equatable {
    let ticksPerCPU: [[UInt32]]
}

struct CPUCoreDisplay: Identifiable {
    var id: Int { index }
    let index: Int
    let usagePercent: Double
    let label: String
}

enum CPUStats {
    private static var lastSample: CPUSample?

    static func sysctlUInt64(_ name: String) -> UInt64? {
        var size = MemoryLayout<UInt64>.size
        var value: UInt64 = 0
        let result = name.withCString { sysctlbyname($0, &value, &size, nil, 0) }
        return result == 0 ? value : nil
    }

    static func sysctlInt32(_ name: String) -> Int32? {
        var size = MemoryLayout<Int32>.size
        var value: Int32 = 0
        let result = name.withCString { sysctlbyname($0, &value, &size, nil, 0) }
        return result == 0 ? value : nil
    }

    /// Intel-style CPU frequency in Hz; often 0 on Apple Silicon.
    static func intelCPUFrequencyHz() -> UInt64? {
        if let hz = sysctlUInt64("hw.cpufrequency"), hz > 0 { return hz }
        if let hz = sysctlUInt64("hw.cpufrequency_max"), hz > 0 { return hz }
        return nil
    }

    static func isAppleSilicon() -> Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// perflevel0 = performance (P), perflevel1 = efficiency (E) logical CPU counts.
    static func performanceLevelLogicalCounts() -> (performance: Int, efficiency: Int) {
        let n = sysctlInt32("hw.nperflevels") ?? 0
        if n >= 2 {
            let p = Int(sysctlInt32("hw.perflevel0.logicalcpu") ?? 0)
            let e = Int(sysctlInt32("hw.perflevel1.logicalcpu") ?? 0)
            return (performance: p, efficiency: e)
        }
        return (performance: 0, efficiency: 0)
    }

    private static func takeSample() -> CPUSample? {
        let host = mach_host_self()
        var processorCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &cpuInfo,
            &numCpuInfo
        )
        guard kr == KERN_SUCCESS, let raw = cpuInfo else { return nil }
        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            let addr = vm_address_t(UInt(bitPattern: UnsafeRawPointer(raw)))
            vm_deallocate(mach_task_self_, addr, size)
        }

        let count = Int(processorCount)
        let states = Int(CPU_STATE_MAX)
        guard states > 0, count * states <= Int(numCpuInfo) else { return nil }

        var perCPU: [[UInt32]] = []
        perCPU.reserveCapacity(count)

        for i in 0..<count {
            var ticks: [UInt32] = []
            ticks.reserveCapacity(states)
            for s in 0..<states {
                let idx = i * states + s
                ticks.append(UInt32(raw[idx]))
            }
            perCPU.append(ticks)
        }
        return CPUSample(ticksPerCPU: perCPU)
    }

    /// Overall CPU usage 0...100 as mean of logical processors; nil until two samples exist.
    static func overallCpuPercent(from cores: [CPUCoreDisplay]) -> Double? {
        guard !cores.isEmpty else { return nil }
        let sum = cores.reduce(0.0) { $0 + $1.usagePercent }
        return sum / Double(cores.count)
    }

    /// Returns per-logical-CPU usage 0...100, optional Intel frequency string, and mean CPU % when available.
    static func poll() -> (cores: [CPUCoreDisplay], intelFrequencyText: String?, footnote: String, overallCpuPercent: Double?) {
        guard let current = takeSample() else {
            return ([], nil, "CPU ölçümü alınamadı.", nil)
        }
        defer { lastSample = current }

        let intelHz = intelCPUFrequencyHz()
        let intelText: String?
        if let hz = intelHz {
            let ghz = Double(hz) / 1_000_000_000.0
            intelText = String(format: "~%.2f GHz (sysctl)", ghz)
        } else {
            intelText = nil
        }

        guard let prev = lastSample else {
            return ([], intelText, isAppleSilicon()
                ? "Apple Silicon: OS, çekirdek başına gerçek MHz sunmuyor; aşağıda yük yüzdeleri."
                : "Örnek toplandı; bir sonraki güncellemede yük gösterilecek.", nil)
        }

        let count = min(prev.ticksPerCPU.count, current.ticksPerCPU.count)
        var displays: [CPUCoreDisplay] = []
        displays.reserveCapacity(count)

        let (performanceLogical, efficiencyLogical) = performanceLevelLogicalCounts()
        let twoClusters = performanceLogical > 0 && efficiencyLogical > 0
        let stateCount = Int(CPU_STATE_MAX)

        for i in 0..<count {
            let oldT = prev.ticksPerCPU[i]
            let newT = current.ticksPerCPU[i]
            guard oldT.count == newT.count, oldT.count >= stateCount else { continue }

            var idle: UInt64 = 0
            var busy: UInt64 = 0
            for s in 0..<oldT.count {
                let d = UInt64(newT[s]) &- UInt64(oldT[s])
                if s == Int(CPU_STATE_IDLE) {
                    idle &+= d
                } else {
                    busy &+= d
                }
            }
            let total = idle &+ busy
            let pct = total > 0 ? Double(busy) / Double(total) * 100.0 : 0

            let label: String
            if twoClusters {
                // Yaygın Apple Silicon sırası: düşük indeksler E, yüksek indeksler P.
                if i < efficiencyLogical {
                    label = "E\(i)"
                } else {
                    label = "P\(i - efficiencyLogical)"
                }
            } else {
                label = "CPU\(i)"
            }

            displays.append(CPUCoreDisplay(index: i, usagePercent: min(100, max(0, pct)), label: label))
        }

        let footnote: String
        if isAppleSilicon() {
            footnote = "Apple Silicon: gerçek çekirdek MHz kullanıcı alanında güvenilir değil; yük % gösterilir."
        } else if intelHz == nil {
            footnote = "Bu makinede sysctl ile frekans okunamadı; yük % gösterilir."
        } else {
            footnote = "Intel: frekans sysctl ile kabaca; dinamik turbo farklı olabilir."
        }

        let overall = overallCpuPercent(from: displays)
        return (displays, intelText, footnote, overall)
    }
}
