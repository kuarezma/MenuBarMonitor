import Foundation

struct InterfaceTraffic: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
}

enum BandwidthMonitor {
    static func snapshot() -> [InterfaceTraffic] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(first) }

        var byName: [String: (in: UInt64, out: UInt64)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            guard let namePtr = ifa.pointee.ifa_name else { continue }
            let name = String(cString: namePtr)
            guard let data = ifa.pointee.ifa_addr?.pointee else { continue }
            guard data.sa_family == UInt8(AF_LINK) else { continue }
            guard let stats = ifa.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }

            let inB = UInt64(stats.pointee.ifi_ibytes)
            let outB = UInt64(stats.pointee.ifi_obytes)
            var cur = byName[name, default: (0, 0)]
            cur.in += inB
            cur.out += outB
            byName[name] = cur
        }

        return byName.keys.sorted().map { key in
            let v = byName[key]!
            return InterfaceTraffic(name: key, bytesIn: v.in, bytesOut: v.out)
        }
    }

    static func preferredInterface(from list: [InterfaceTraffic], override: String?) -> InterfaceTraffic? {
        if let o = override, let hit = list.first(where: { $0.name == o }) {
            return hit
        }
        if let en0 = list.first(where: { $0.name == "en0" }) { return en0 }
        let candidates = list.filter { iface in
            iface.name.hasPrefix("en") && iface.name != "en0"
        }
        return candidates.first ?? list.first { $0.name != "lo0" }
    }

    static func formatRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 0, bytesPerSecond.isFinite else { return "—" }
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
        if bytesPerSecond >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    /// Ultra-short rate for menu bar suffix (not a speed unit; omits “/s” on purpose).
    static func formatCompactRate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 0, bytesPerSecond.isFinite else { return "—" }
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1fM", bytesPerSecond / 1_000_000)
        }
        if bytesPerSecond >= 1_000 {
            return String(format: "%.0fk", bytesPerSecond / 1_000)
        }
        if bytesPerSecond >= 1 {
            return String(format: "%.0f", bytesPerSecond)
        }
        return "0"
    }
}
