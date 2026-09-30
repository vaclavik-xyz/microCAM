import Foundation
import MicroCAMCore
import Network

/// HTTP/1.1, one request per connection, shared by the live stream and the
/// MCP server. Refuses peers outside the shop network (`StreamAccessPolicy`)
/// before reading anything, gives slow clients 10 s to send their request,
/// and can advertise itself over Bonjour.
final class HTTPServer {
    /// Called on the main queue with the request and the client's IP address;
    /// `reply` may be called on any queue.
    typealias Handler = (_ request: HTTPRequest, _ peer: String, _ reply: @escaping (StreamRoute) -> Void) -> Void

    var onError: ((String?) -> Void)?   // main queue; nil = running fine

    private let queue: DispatchQueue
    private let handler: Handler
    /// Takes over a connection answered with `.stream`.
    private let onStream: ((NWConnection) -> Void)?
    private let onStop: (() -> Void)?
    private let cannotStart: (_ port: Int, _ reason: String) -> String
    private var listener: NWListener?

    init(queue: DispatchQueue, cannotStart: @escaping (_ port: Int, _ reason: String) -> String,
         onStream: ((NWConnection) -> Void)? = nil, onStop: (() -> Void)? = nil, handler: @escaping Handler) {
        self.queue = queue
        self.cannotStart = cannotStart
        self.onStream = onStream
        self.onStop = onStop
        self.handler = handler
    }

    /// `serviceName` nil skips Bonjour advertising; `loopbackOnly` binds to
    /// 127.0.0.1 (demo mode: no firewall prompt, never reachable from the LAN).
    func start(port: UInt16, serviceName: String? = nil, serviceType: String? = nil, loopbackOnly: Bool = false) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return report(String(localized: "The port must be a number from 1024 to 65535.")) }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener: NWListener
            if loopbackOnly {
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
                listener = try NWListener(using: parameters)
            } else {
                listener = try NWListener(using: parameters, on: nwPort)
            }
            if let serviceName, let serviceType { listener.service = NWListener.Service(name: serviceName, type: serviceType) }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready: self.report(nil)
                case .failed(let error): self.report(self.cannotStart(Int(port), error.localizedDescription))
                default: break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            report(cannotStart(Int(port), error.localizedDescription))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onStop?()
    }

    private func report(_ text: String?) {
        DispatchQueue.main.async { self.onError?(text) }
    }

    private func accept(_ connection: NWConnection) {
        guard case .hostPort(let host, _) = connection.endpoint, StreamAccessPolicy.isAllowed(Self.string(host)) else {
            connection.cancel()
            return
        }
        let peer = Self.string(host)
        connection.start(queue: queue)
        let handled = LockedValue(false)
        queue.asyncAfter(deadline: .now() + 10) {
            if !handled.value { connection.cancel() }
        }
        receive(connection, peer: peer, buffer: Data(), handled: handled)
    }

    private func receive(_ connection: NWConnection, peer: String, buffer: Data, handled: LockedValue<Bool>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequestParser.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(connection, peer: peer, buffer: buffer, handled: handled)
                }
            case .invalid:
                handled.value = true
                self.send(.text(400, "bad request"), on: connection)
            case .complete(let request):
                handled.value = true
                // The handlers live on the main actor.
                DispatchQueue.main.async {
                    self.handler(request, peer) { route in
                        self.queue.async {
                            switch route {
                            case .response(let response): self.send(response, on: connection)
                            case .stream:
                                if let onStream = self.onStream { onStream(connection) } else { connection.cancel() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func string(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address): "\(address)"
        case .ipv6(let address): "\(address)"
        case .name(let name, _): name
        @unknown default: ""
        }
    }
}
