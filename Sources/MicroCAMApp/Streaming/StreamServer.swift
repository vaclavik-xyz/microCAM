import Foundation
import MicroCAMCore
import Network

/// HTTP/1.1, one request per connection. Refuses non-local peers before
/// reading anything, gives slow clients 10 s to send their request, and
/// advertises itself over Bonjour for viewer mode.
final class StreamServer {
    static let serviceType = "_microcam._tcp"

    var onError: ((String?) -> Void)?   // main queue; nil = running fine

    private let router: StreamRouter
    private let hub: StreamHub
    private let queue: DispatchQueue
    private var listener: NWListener?

    init(router: StreamRouter, hub: StreamHub, queue: DispatchQueue) {
        self.router = router
        self.hub = hub
        self.queue = queue
    }

    /// `serviceName` nil skips Bonjour advertising; `loopbackOnly` binds to
    /// 127.0.0.1 (demo mode: no firewall prompt, never reachable from the LAN).
    func start(port: UInt16, serviceName: String?, loopbackOnly: Bool = false) {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return report("Neplatný port \(port).") }
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
            if let serviceName { listener.service = NWListener.Service(name: serviceName, type: Self.serviceType) }
            listener.newConnectionHandler = { [weak self] in self?.accept($0) }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready: self?.report(nil)
                case .failed(let error): self?.report("Přenos nelze spustit na portu \(port): \(error.localizedDescription)")
                default: break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            report("Přenos nelze spustit na portu \(port): \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        hub.closeAll()
    }

    private func report(_ text: String?) {
        DispatchQueue.main.async { self.onError?(text) }
    }

    private func accept(_ connection: NWConnection) {
        guard case .hostPort(let host, _) = connection.endpoint, StreamAccessPolicy.isAllowed(Self.string(host)) else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        let handled = LockedValue(false)
        queue.asyncAfter(deadline: .now() + 10) {
            if !handled.value { connection.cancel() }
        }
        receive(connection, buffer: Data(), handled: handled)
    }

    private func receive(_ connection: NWConnection, buffer: Data, handled: LockedValue<Bool>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequestParser.parse(buffer) {
            case .incomplete:
                if isComplete || error != nil { connection.cancel() } else { self.receive(connection, buffer: buffer, handled: handled) }
            case .invalid:
                handled.value = true
                self.send(.text(400, "bad request"), on: connection)
            case .complete(let request):
                handled.value = true
                // The backend lives on the main actor.
                DispatchQueue.main.async {
                    self.router.handle(request) { route in
                        self.queue.async {
                            switch route {
                            case .response(let response): self.send(response, on: connection)
                            case .stream: self.hub.add(connection)
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
