import Darwin
import Foundation

/// Samples kernel VM counters via `host_statistics64(_:HOST_VM_INFO64,...)`
/// into [`vm_statistics64`](https://developer.apple.com/documentation/kernel/vm_statistics64).
/// **Not** `mach_vm_statistics64_t` (per-task); host-level `vm_statistics64` is the
/// public 64-bit VM summary for the machine.
///
/// ## Important (PROXY)
/// Rates derived from page faults, pageins/outs, compression events, and a
/// free-vs-active heuristic are a **unified-memory / subsystem load proxy** only.
/// They do **not** measure true DRAM (or SoC) GB/s; Apple does not expose raw
/// memory bandwidth meters to unprivileged apps.
enum MemoryPressureMonitor {
    private static var lastSample: (date: Date, stats: vm_statistics64)?

    /// Blended 0…100 score for menu bar / summary (fault activity + occupancy heuristic).
    struct PollResult: Equatable {
        var proxyPercent: Double
        /// Compact menu bar token, e.g. `M~42%`.
        var shortLabel: String
        /// Turkish explanation for popover / help.
        var footnote: String
        /// 0…100 from `active+wire` vs `active+wire+free` (approximate “tightness”).
        var pressureHeuristicPercent: Double
        var pageinsPerSec: Double
        var pageoutsPerSec: Double
        var faultsPerSec: Double
        var cowFaultsPerSec: Double
        var compressionsPerSec: Double
        var decompressionsPerSec: Double
        var swapinsPerSec: Double
        var swapoutsPerSec: Double
        var compressorPageCount: UInt64
        var freePageCount: UInt64
        var activePageCount: UInt64
        var wirePageCount: UInt64
    }

    /// Tek `host_statistics64(HOST_VM_INFO64, …)` çağrısı; RAM % ve vekil için paylaşılabilir.
    static func readHostVMInfo64() -> vm_statistics64? {
        var stats = vm_statistics64()
        // Matches `HOST_VM_INFO64_COUNT` (sizeof(vm_statistics64) / sizeof(integer_t)).
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return stats
    }

    private static func deltaU64(_ a: UInt64, _ b: UInt64) -> UInt64 {
        a &- b
    }

    /// Maps a nonnegative rate to 0…100 using a soft saturation curve.
    private static func saturate(rate: Double, halfAt: Double) -> Double {
        guard rate.isFinite, rate >= 0, halfAt > 0 else { return 0 }
        // 1 / (1 + halfAt/rate) → ~50% at rate == halfAt
        let x = rate / halfAt
        return min(100, 100 * x / (1 + x))
    }

    /// `currentVM` verilirse ekstra Mach okuma yapılmaz (saniyede tek `HOST_VM_INFO64` ile uyum).
    static func poll(currentVM: vm_statistics64? = nil) -> PollResult {
        let placeholderFootnote = """
        Bu değerler `HOST_VM_INFO64` (vm_statistics64) sayaçlarından türetilir; gerçek DRAM/\
        birleşik bellek GB/s ölçümü değildir. Sayfa hatası, sayfa giriş/çıkışı ve sıkıştırma \
        etkinliği ile serbest sayfa oranı birleştirilerek kabaca bir yük göstergesi üretilir.
        """

        guard let cur = currentVM ?? readHostVMInfo64() else {
            return PollResult(
                proxyPercent: 0,
                shortLabel: "M~—",
                footnote: "VM istatistikleri okunamadı. " + placeholderFootnote,
                pressureHeuristicPercent: 0,
                pageinsPerSec: 0,
                pageoutsPerSec: 0,
                faultsPerSec: 0,
                cowFaultsPerSec: 0,
                compressionsPerSec: 0,
                decompressionsPerSec: 0,
                swapinsPerSec: 0,
                swapoutsPerSec: 0,
                compressorPageCount: 0,
                freePageCount: 0,
                activePageCount: 0,
                wirePageCount: 0
            )
        }

        let now = Date()
        defer { lastSample = (now, cur) }

        guard let prev = lastSample else {
            return PollResult(
                proxyPercent: 0,
                shortLabel: "M~…",
                footnote: "İlk örnek toplandı; bir sonraki saniyede oranlar güncellenir. " + placeholderFootnote,
                pressureHeuristicPercent: 0,
                pageinsPerSec: 0,
                pageoutsPerSec: 0,
                faultsPerSec: 0,
                cowFaultsPerSec: 0,
                compressionsPerSec: 0,
                decompressionsPerSec: 0,
                swapinsPerSec: 0,
                swapoutsPerSec: 0,
                compressorPageCount: UInt64(cur.compressor_page_count),
                freePageCount: UInt64(cur.free_count),
                activePageCount: UInt64(cur.active_count),
                wirePageCount: UInt64(cur.wire_count)
            )
        }

        let dt = max(now.timeIntervalSince(prev.date), 0.001)
        let p = prev.stats

        let dPageins = deltaU64(cur.pageins, p.pageins)
        let dPageouts = deltaU64(cur.pageouts, p.pageouts)
        let dFaults = deltaU64(cur.faults, p.faults)
        let dCow = deltaU64(cur.cow_faults, p.cow_faults)
        let dComp = deltaU64(cur.compressions, p.compressions)
        let dDecomp = deltaU64(cur.decompressions, p.decompressions)
        let dSwapin = deltaU64(cur.swapins, p.swapins)
        let dSwapout = deltaU64(cur.swapouts, p.swapouts)

        let pageinsPerSec = Double(dPageins) / dt
        let pageoutsPerSec = Double(dPageouts) / dt
        let faultsPerSec = Double(dFaults) / dt
        let cowFaultsPerSec = Double(dCow) / dt
        let compressionsPerSec = Double(dComp) / dt
        let decompressionsPerSec = Double(dDecomp) / dt
        let swapinsPerSec = Double(dSwapin) / dt
        let swapoutsPerSec = Double(dSwapout) / dt

        // Occupancy-style heuristic: higher when active+wire dominates vs free buffer.
        let freeN = UInt64(cur.free_count)
        let activeN = UInt64(cur.active_count)
        let wireN = UInt64(cur.wire_count)
        let denom = max(activeN &+ wireN &+ freeN, 1)
        let pressureHeuristicPercent = min(100, max(0, 100 * Double(activeN &+ wireN) / Double(denom)))

        // Activity from faults / COW + paging + compressor churn (PROXY components).
        let faultScore = saturate(rate: faultsPerSec, halfAt: 120_000)
            + 0.35 * saturate(rate: cowFaultsPerSec, halfAt: 40_000)
        let ioScore = saturate(rate: pageinsPerSec + pageoutsPerSec, halfAt: 2_000)
        let compScore = saturate(rate: compressionsPerSec + decompressionsPerSec, halfAt: 8_000)
        let swapScore = saturate(rate: swapinsPerSec + swapoutsPerSec, halfAt: 500)

        let activityBlend = min(
            100,
            0.55 * faultScore + 0.22 * ioScore + 0.18 * compScore + 0.05 * swapScore
        )
        let proxy = min(100, max(0, 0.58 * activityBlend + 0.42 * pressureHeuristicPercent))
        let short = String(format: "M~%.0f%%", proxy)

        let footnote = """
        Yaklaşık gösterge: `HOST_VM_INFO64` (`vm_statistics64`) sayaç deltaları (sayfa hatası, \
        sayfa giriş/çıkışı, sıkıştırma vb.) ile serbest sayfaya karşı etkin+kablolu sayfa oranı \
        birleştirilir. Bu, Apple Silicon / M serisi dahil **ölçülmüş bellek bant genişliği (GB/s) \
        değildir**; yalnızca bellek alt sistemi yükünün kabaca birleşik bir vekilidir.
        """

        return PollResult(
            proxyPercent: proxy,
            shortLabel: short,
            footnote: footnote,
            pressureHeuristicPercent: pressureHeuristicPercent,
            pageinsPerSec: pageinsPerSec,
            pageoutsPerSec: pageoutsPerSec,
            faultsPerSec: faultsPerSec,
            cowFaultsPerSec: cowFaultsPerSec,
            compressionsPerSec: compressionsPerSec,
            decompressionsPerSec: decompressionsPerSec,
            swapinsPerSec: swapinsPerSec,
            swapoutsPerSec: swapoutsPerSec,
            compressorPageCount: UInt64(cur.compressor_page_count),
            freePageCount: freeN,
            activePageCount: activeN,
            wirePageCount: wireN
        )
    }
}
