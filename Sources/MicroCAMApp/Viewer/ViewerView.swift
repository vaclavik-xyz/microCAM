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
                StreamWebView(url: url, viewer: viewer)
                if viewer.isDrawing {
                    // The same tools as on the camera Mac, over the bottom of the picture.
                    DrawingPalette(model: viewer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
        .animation(.easeOut(duration: 0.2), value: viewer.isDrawing)
        .navigationSubtitle(subtitle)
        .toolbar {
            if viewer.url != nil {
                ToolbarItemGroup(placement: .principal) {
                    if viewer.showsPhoto {
                        Button { viewer.backToLive() } label: { Label("Live view", systemImage: "chevron.backward") }
                            .labelStyle(.titleAndIcon)
                            .help("Back to the live picture")
                        Button { viewer.saveDrawingAsPhoto() } label: { Label("Save as photo", systemImage: "checkmark") }
                            .labelStyle(.titleAndIcon)
                            .disabled(!viewer.hasDrawing)
                            .help("Save the drawing as a new photo on the camera Mac")
                    } else if viewer.photoEnabled {
                        // Without a PIN on the camera computer nobody can take a photo: no button.
                        Button { viewer.takePhoto() } label: { Label("Take photo", systemImage: "camera") }
                            .help("Take a photo on the camera Mac")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $viewer.isDrawing) { Label("Draw", systemImage: "pencil.tip.crop.circle") }
                        .toggleStyle(.button)
                        .help("Draw on the picture")
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

extension ViewerView {
    /// Under the camera computer's name: live, the photo taken from here, or offline; and the job.
    private var subtitle: String {
        guard viewer.url != nil else { return "" }
        let state = viewer.offline ? String(localized: "Offline")
            : viewer.showsPhoto ? String(localized: "Photo") : String(localized: "Live")
        return viewer.job.isEmpty ? state : state + " · " + viewer.job
    }
}

/// The stream page in WebKit. The page reconnects the stream by itself; this
/// only retries when the page itself cannot be loaded. The page reports its
/// drawing state to `viewer`, whose native tools drive it.
struct StreamWebView: NSViewRepresentable {
    let url: URL
    let viewer: ViewerModel

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()   // keeps the PIN in localStorage between launches
        // Weak: WebKit keeps its message handlers alive, which would keep the viewer alive.
        configuration.userContentController.add(PageStateHandler(viewer: viewer), name: "microcam")
        let view = WKWebView(frame: .zero, configuration: configuration)
        viewer.webView = view
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.url = url
        if view.url?.host != url.host || view.url?.port != url.port { view.load(URLRequest(url: url)) }
    }

    private final class PageStateHandler: NSObject, WKScriptMessageHandler {
        weak var viewer: ViewerModel?
        init(viewer: ViewerModel) { self.viewer = viewer }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let json = message.body as? String else { return }
            MainActor.assumeIsolated { viewer?.receivePageState(json) }
        }
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
