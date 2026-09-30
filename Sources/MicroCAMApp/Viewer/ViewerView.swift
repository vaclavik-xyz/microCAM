import SwiftUI
import WebKit

struct ViewerView: View {
    @ObservedObject var viewer: ViewerModel
    @State private var manual = ""
    @State private var manualInvalid = false

    var body: some View {
        ZStack {
            Color.black
            if let url = viewer.url {
                StreamWebView(url: url)
            } else {
                VStack(spacing: 14) {
                    Text(viewer.status).font(.title3)
                    ForEach(viewer.sources) { source in
                        Button("Connect to \(source.name)") { viewer.connect(source) }
                    }
                    HStack {
                        TextField("or an address, e.g. 192.168.1.20:8090", text: $manual)
                            .textFieldStyle(.roundedBorder).frame(width: 300)
                            .onSubmit { manualInvalid = !viewer.connect(manual: manual) }
                        Button("Connect") { manualInvalid = !viewer.connect(manual: manual) }
                    }
                    if manualInvalid { Text("Invalid address. Enter it as host:port, e.g. 192.168.1.20:8090.").font(.caption).foregroundStyle(.red) }
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .toolbar {
            if viewer.url != nil {
                ToolbarItem {
                    Menu(viewer.status) {
                        ForEach(viewer.sources) { source in Button(source.name) { viewer.connect(source) } }
                        Divider()
                        Button("Disconnect and choose another") { viewer.disconnect() }
                    }
                }
            }
        }
    }
}

/// The stream page in WebKit. The page reconnects the stream by itself; this
/// only retries when the page itself cannot be loaded.
struct StreamWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()   // keeps the PIN in localStorage between launches
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.url = url
        if view.url?.host != url.host || view.url?.port != url.port { view.load(URLRequest(url: url)) }
    }

    /// A failed first load leaves nothing to `reload()`, so retries load the URL again.
    final class Coordinator: NSObject, WKNavigationDelegate {
        var url: URL
        init(url: URL) { self.url = url }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { retry(webView) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { retry(webView) }
        private func retry(_ webView: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak webView, url] in
                webView?.load(URLRequest(url: url))
            }
        }
    }
}
