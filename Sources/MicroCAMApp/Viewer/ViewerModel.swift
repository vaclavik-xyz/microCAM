import Foundation
import MicroCAMCore
import Network

/// Finds microCAM hosts via Bonjour, resolves one to an IPv4 URL and keeps
/// the chosen source for the next launch. Tailscale does not carry Bonjour,
/// so a manual URL is the fallback.
@MainActor
final class ViewerModel: ObservableObject {
    struct Source: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    @Published private(set) var sources: [Source] = []
    @Published private(set) var url: URL?
    @Published private(set) var status = String(localized: "Looking for microCAM on the network…")

    private let settings: () -> AppSettings
    private let update: ((inout AppSettings) -> Void) -> Void
    private var browser: NWBrowser?
    private var resolving: NWConnection?

    init(settings: @escaping () -> AppSettings, update: @escaping ((inout AppSettings) -> Void) -> Void) {
        self.settings = settings
        self.update = update
    }

    func start() {
        if let manual = settings().viewerManualURL, connect(manual: manual) { /* remembered manual URL */ }
        let browser = NWBrowser(for: .bonjour(type: StreamServer.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sources = results.compactMap { result in
                    if case .service(let name, _, _, _) = result.endpoint { return Source(name: name, endpoint: result.endpoint) }
                    return nil
                }.sorted { $0.name < $1.name }
                self.autoConnect()
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func autoConnect() {
        guard url == nil, resolving == nil else { return }
        if let name = settings().viewerSourceName, let source = sources.first(where: { $0.name == name }) {
            connect(source)
        } else if settings().viewerSourceName == nil, sources.count == 1 {
            connect(sources[0])
        } else if sources.isEmpty {
            status = String(localized: "Looking for microCAM on the network…")
        } else {
            status = String(localized: "Choose a camera computer")
        }
    }

    func connect(_ source: Source) {
        resolving?.cancel()
        status = String(localized: "Connecting to \(source.name)…")
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let connection = NWConnection(to: source.endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint,
                       case .ipv4(let address) = host {
                        self.url = URL(string: "http://\(address):\(port.rawValue)/?embedded=1")
                        self.status = source.name
                        self.update { $0.viewerSourceName = source.name; $0.viewerManualURL = nil }
                    }
                    connection.cancel()
                    self.resolving = nil
                case .failed, .waiting:
                    self.status = String(localized: "\(source.name) isn't reachable. Trying again…")
                    connection.cancel()
                    self.resolving = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        MainActor.assumeIsolated { self.autoConnect() }
                    }
                default:
                    break
                }
            }
        }
        resolving = connection
        connection.start(queue: .main)
    }

    /// `host:port`, `http://host:port` or a full URL. Returns false if unusable.
    @discardableResult
    func connect(manual: String) -> Bool {
        var text = manual.trimmingCharacters(in: .whitespaces)
        if !text.contains("://") { text = "http://" + text }
        guard var components = URLComponents(string: text), components.host != nil,
              ["http", "https"].contains(components.scheme ?? "") else { return false }
        if components.port == nil { components.port = 8090 }
        components.path = "/"
        components.queryItems = [URLQueryItem(name: "embedded", value: "1")]
        guard let url = components.url else { return false }
        self.url = url
        status = components.host ?? ""
        update { $0.viewerManualURL = manual; $0.viewerSourceName = nil }
        return true
    }

    func disconnect() {
        url = nil
        update { $0.viewerSourceName = nil; $0.viewerManualURL = nil }
        autoConnect()
    }
}
