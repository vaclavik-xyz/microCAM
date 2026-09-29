import Darwin

/// The stream is for the shop network only: loopback, private LAN,
/// link-local and Tailscale (CGNAT 100.64/10, ULA fd7a:115c:a1e0::/48 ⊂ fc00::/7).
/// Anything else is refused before any HTTP is read.
public enum StreamAccessPolicy {
    public static func isAllowed(_ host: String) -> Bool {
        let bare = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        if let v4 = ipv4(bare) { return allowedV4(v4) }
        if let v6 = ipv6(bare) { return allowedV6(v6) }
        return false
    }

    private static func ipv4(_ s: String) -> UInt32? {
        var addr = in_addr()
        guard inet_pton(AF_INET, s, &addr) == 1 else { return nil }
        return UInt32(bigEndian: addr.s_addr)
    }

    private static func ipv6(_ s: String) -> [UInt8]? {
        var addr = in6_addr()
        guard inet_pton(AF_INET6, s, &addr) == 1 else { return nil }
        return withUnsafeBytes(of: &addr) { Array($0) }
    }

    private static func inRange(_ ip: UInt32, _ base: UInt32, _ prefix: UInt32) -> Bool {
        let mask: UInt32 = prefix == 0 ? 0 : ~UInt32(0) << (32 - prefix)
        return ip & mask == base & mask
    }

    private static func allowedV4(_ ip: UInt32) -> Bool {
        let ranges: [(UInt32, UInt32)] = [
            (0x7F00_0000, 8),   // 127.0.0.0/8
            (0x0A00_0000, 8),   // 10.0.0.0/8
            (0xAC10_0000, 12),  // 172.16.0.0/12
            (0xC0A8_0000, 16),  // 192.168.0.0/16
            (0xA9FE_0000, 16),  // 169.254.0.0/16
            (0x6440_0000, 10),  // 100.64.0.0/10 (Tailscale)
        ]
        return ranges.contains { inRange(ip, $0.0, $0.1) }
    }

    private static func allowedV6(_ b: [UInt8]) -> Bool {
        if b == [UInt8](repeating: 0, count: 15) + [1] { return true }                 // ::1
        if b[0] == 0xFE && (b[1] & 0xC0) == 0x80 { return true }                       // fe80::/10
        if (b[0] & 0xFE) == 0xFC { return true }                                        // fc00::/7
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {        // ::ffff:a.b.c.d
            let v4 = UInt32(b[12]) << 24 | UInt32(b[13]) << 16 | UInt32(b[14]) << 8 | UInt32(b[15])
            return allowedV4(v4)
        }
        return false
    }
}
