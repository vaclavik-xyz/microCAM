import Foundation

/// The stream page a viewer Mac loads from a camera computer.
public enum ViewerURL {
    /// `host` is an IPv4 address as Network.framework prints it, possibly
    /// with the interface after `%` ("192.168.1.140%en0"), which a URL host
    /// can't carry; it is dropped. Nil when nothing usable is left.
    public static func stream(host: String, port: UInt16, language: String) -> URL? {
        let address = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard !address.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = address
        components.port = Int(port)
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "embedded", value: "1"), URLQueryItem(name: "lang", value: language)]
        return components.url
    }
}
