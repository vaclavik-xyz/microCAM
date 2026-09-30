import AppKit
import MicroCAMCore

/// The MCP server for AI agents (Settings → Integrations): token, listener,
/// and what the person at the Mac sees of the agent. Off by default, camera
/// mode only, and it never runs without a token.
@MainActor
final class MCPController: ObservableObject {
    /// How long after the last frame an agent counts as watching.
    static let watchWindow: TimeInterval = 10
    private static let keychainAccount = "mcp-token"

    @Published private(set) var error: String?
    /// An agent pulled a frame in the last `watchWindow` seconds (window subtitle).
    @Published private(set) var agentWatching = false

    private unowned let model: AppModel
    private var server: HTTPServer?
    private lazy var backend = MCPBackendAdapter(model: model)
    private let authGuard = MCPAuthGuard()
    /// Keychain value, read once; `.some(nil)` means read and not set.
    private var cachedToken: String?? = nil
    private var demoMode = false
    private var watchReset: DispatchWorkItem?

    init(model: AppModel) { self.model = model }

    // MARK: Token

    var token: String? {
        if case .some(let value) = cachedToken { return value }
        let value = KeychainToken.read(account: Self.keychainAccount).flatMap { MCPToken.isValid($0) ? $0 : nil }
        cachedToken = .some(value)
        return value
    }

    /// Replaces the token; agents using the old one are refused from now on.
    func regenerateToken() {
        store(MCPToken.generate())
    }

    /// Demo mode: the token lives in memory only, never in the Keychain.
    func useDemoToken(_ value: String?) {
        demoMode = true
        cachedToken = .some(value.flatMap { MCPToken.isValid($0) ? $0 : nil } ?? MCPToken.generate())
    }

    @discardableResult
    private func store(_ value: String) -> Bool {
        if demoMode {
            cachedToken = .some(value)
            return true
        }
        let saved = KeychainToken.write(value, account: Self.keychainAccount)
            && KeychainToken.read(account: Self.keychainAccount) == value
        cachedToken = .some(saved ? value : nil)
        return saved
    }

    // MARK: Server

    /// Starts, restarts or stops the server to match settings.
    func apply() {
        let settings = model.settings
        guard model.launchMode == .camera, settings.mcpEnabled else {
            server?.stop()
            server = nil
            error = nil
            return
        }
        // Turning the server on creates the token; without one it stays off.
        if token == nil, !store(MCPToken.generate()) {
            server?.stop()
            error = String(localized: "Can't save the token in the Keychain, so the MCP server stays off.")
            return
        }
        if server == nil {
            let router = MCPRouter(backend: backend, authGuard: authGuard, token: { [weak self] in
                MainActor.assumeIsolated { self?.token }
            }, serverVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            let server = HTTPServer(queue: DispatchQueue(label: "microcam.mcp.server"), cannotStart: { port, reason in
                String(localized: "The MCP server can't start on port \(port): \(reason). Try another port.")
            }) { request, peer, reply in
                router.handle(request, peer: peer) { reply(.response($0)) }
            }
            server.onError = { [weak self] in self?.error = $0 }
            self.server = server
        }
        guard StreamPort.isValid(settings.mcpPort) else {
            server?.stop()
            error = String(localized: "The port must be a number from 1024 to 65535.")
            return
        }
        // Demo mode stays on loopback so it is never reachable from the network.
        server?.start(port: UInt16(settings.mcpPort), loopbackOnly: model.demo != nil)
    }

    /// Addresses shown in Settings; the demo shows a documentation address.
    func addresses() -> [String] {
        model.demo == nil ? NetworkAddresses.streamIPv4() : ["192.0.2.10"]
    }

    // MARK: Agent activity

    /// Called for every frame an agent takes: shows "Agent is watching" and
    /// keeps the camera on (like a stream viewer) for `watchWindow` seconds.
    func noteAgentWatching() {
        agentWatching = true
        model.lifecycle.update { $0.agentWatching = true }
        watchReset?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.agentWatching = false
                self?.model.lifecycle.update { $0.agentWatching = false }
            }
        }
        watchReset = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.watchWindow, execute: reset)
    }
}
