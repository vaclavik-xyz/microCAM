import Foundation
import MicroCAMCore
import Network
import WebKit

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

    /// The stream page follows the app's language rather than the web view's.
    static let pageLanguage = Bundle.main.preferredLocalizations.first ?? "en"

    @Published private(set) var sources: [Source] = []
    @Published private(set) var url: URL?
    @Published private(set) var status = String(localized: "Looking for microCAM on the network…")

    private let settings: () -> AppSettings
    private let update: ((inout AppSettings) -> Void) -> Void
    private var browser: NWBrowser?
    private var resolving: NWConnection?

    // MARK: Native tools for the stream page (window.microcam in StreamPage)

    /// The page's drawing state, kept in sync both ways: a change here is sent
    /// to the page, and what the page reports is applied without sending it back.
    @Published var isDrawing = false { didSet { send("setDrawing(\(isDrawing))", if: isDrawing != oldValue) } }
    @Published var drawTool = AnnotationShape.Kind.arrow { didSet { send("setTool('\(drawTool.rawValue)')", if: drawTool != oldValue) } }
    @Published var drawColor = AppModel.drawColors[0] { didSet { send("setColor('\(drawColor)')", if: drawColor != oldValue) } }
    @Published var textSize = AnnotationTextSize.medium { didSet { send("setTextSize('\(textSize.rawValue)')", if: textSize != oldValue) } }
    @Published private(set) var hasDrawing = false
    var canUndoDrawing: Bool { hasDrawing }
    let drawingTools: [AnnotationShape.Kind] = [.arrow, .ellipse, .pen, .text]
    /// A PIN is set on the camera computer, so photos can be taken from here.
    @Published private(set) var photoEnabled = false
    /// A photo taken from here is shown instead of the live picture.
    @Published private(set) var showsPhoto = false
    @Published private(set) var offline = false
    @Published private(set) var job = ""
    weak var webView: WKWebView?
    private var applyingPageState = false

    func undoDrawing() { send("undo()") }
    func clearDrawing() { send("clear()") }
    func takePhoto() { send("photo()") }
    func backToLive() { send("back()") }
    func saveDrawingAsPhoto() { send("save()") }

    private func send(_ call: String, if changed: Bool = true) {
        guard changed, !applyingPageState else { return }
        webView?.evaluateJavaScript("window.microcam && microcam.\(call)")
    }

    /// The JSON the page posts to `microcam` whenever its state changes.
    func receivePageState(_ json: String) {
        guard let state = StreamPageState.decode(json) else { return }
        applyingPageState = true
        defer { applyingPageState = false }
        if isDrawing != state.drawing { isDrawing = state.drawing }
        if let tool = AnnotationShape.Kind(rawValue: state.tool), drawTool != tool { drawTool = tool }
        if drawColor != state.color { drawColor = state.color }
        if let size = AnnotationTextSize(rawValue: state.size), textSize != size { textSize = size }
        hasDrawing = state.shapes > 0
        photoEnabled = state.photoEnabled
        showsPhoto = state.frozen
        offline = state.offline
        job = state.job
    }

    init(settings: @escaping () -> AppSettings, update: @escaping ((inout AppSettings) -> Void) -> Void) {
        self.settings = settings
        self.update = update
    }

    func start() {
        if let manual = settings().viewerManualURL, connect(manual: manual) { /* remembered manual URL */ }
        let browser = NWBrowser(for: .bonjour(type: AppModel.streamServiceType, domain: nil), using: .tcp)
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
                    connection.cancel()
                    self.resolving = nil
                    // Only an IPv4 address: WebKit can't load a link-local IPv6 one.
                    if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint,
                       case .ipv4(let address) = host,
                       let url = ViewerURL.stream(host: "\(address)", port: port.rawValue, language: Self.pageLanguage) {
                        if self.url != url { self.resetPageState() }
                        self.url = url
                        self.status = source.name
                        self.update { $0.viewerSourceName = source.name; $0.viewerManualURL = nil }
                    } else {
                        // Never stay on "Connecting…" without saying anything.
                        self.retryLater(source)
                    }
                case .failed, .waiting:
                    connection.cancel()
                    self.resolving = nil
                    self.retryLater(source)
                default:
                    break
                }
            }
        }
        resolving = connection
        connection.start(queue: .main)
    }

    private func retryLater(_ source: Source) {
        status = String(localized: "\(source.name) isn't reachable. Trying again…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated { self?.autoConnect() }
        }
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
        components.queryItems = [URLQueryItem(name: "embedded", value: "1"), URLQueryItem(name: "lang", value: Self.pageLanguage)]
        guard let url = components.url else { return false }
        if self.url != url { resetPageState() }
        self.url = url
        status = components.host ?? ""
        update { $0.viewerManualURL = manual; $0.viewerSourceName = nil }
        return true
    }

    func disconnect() {
        url = nil
        resetPageState()
        update { $0.viewerSourceName = nil; $0.viewerManualURL = nil }
        autoConnect()
    }

    /// A new page starts with nothing drawn and no photo.
    private func resetPageState() {
        applyingPageState = true
        defer { applyingPageState = false }
        isDrawing = false
        hasDrawing = false
        showsPhoto = false
        photoEnabled = false
    }
}

extension ViewerModel: DrawingTarget {}
