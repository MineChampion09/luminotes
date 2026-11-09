import AppKit
import SwiftUI
import WebKit

struct MermaidBlockView: View {
    @ObservedObject var viewModel: EditorViewModel
    let block: Block

    @State private var isEditing = false
    @State private var draft = ""
    @State private var diagramHeight: CGFloat = 150
    @State private var didAutoEdit = false
    @Environment(\.colorScheme) private var colorScheme

    private var source: String {
        block.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewSource: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedSource: String {
        isEditing ? previewSource : source
    }

    private var theme: MermaidTheme {
        colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(Palette.border.opacity(0.8))
                .frame(height: 1)

            content
        }
        .glassPanel(cornerRadius: 8)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            editorPopover
        }
        .onAppear {
            guard source.isEmpty, !didAutoEdit else { return }
            didAutoEdit = true
            beginEditing()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "flowchart")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)

            Text("Mermaid diagram")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.primaryText)

            Spacer()

            Button {
                beginEditing()
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plainPointer)
            .help("Edit Mermaid source")
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    @ViewBuilder
    private var content: some View {
        if displayedSource.isEmpty {
            Button {
                beginEditing()
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "flowchart")
                        .font(.system(size: 23, weight: .light))
                        .foregroundStyle(Palette.tertiaryText)

                    Text("Add a Mermaid diagram")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plainPointer)
        } else {
            MermaidWebView(
                source: displayedSource,
                theme: theme,
                height: $diagramHeight
            )
            .frame(height: diagramHeight)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        beginEditing()
                    }
            }
            .help("Click to edit Mermaid source")
        }
    }

    private var editorPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "flowchart")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Mermaid source")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Palette.secondaryText)

            SourceTextEditor(text: $draft, fontSize: 12)
                .frame(width: 480, height: 260)
                .background(Palette.code)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.border, lineWidth: 1)
                )

            HStack {
                Text("Changes update live · press Done to save")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
                Spacer()
                Button("Cancel") {
                    isEditing = false
                }
                .buttonStyle(.plainPointer)
                .foregroundStyle(Palette.secondaryText)

                Button("Done") {
                    viewModel.updateText(
                        block.id,
                        text: RichText(previewSource)
                    )
                    isEditing = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 11.5, weight: .medium))
        }
        .padding(14)
        .frame(width: 508)
        .onExitCommand {
            isEditing = false
        }
    }

    private func beginEditing() {
        draft = source
        isEditing = true
    }
}

private enum MermaidTheme: String {
    case light
    case dark
}

private struct MermaidWebView: NSViewRepresentable {
    let source: String
    let theme: MermaidTheme
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "pele")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear

        context.coordinator.webView = webView
        context.coordinator.configure(webView)

        if let html = MermaidPage.html {
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            webView.loadHTMLString(MermaidPage.missingLibraryHTML, baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configure(webView)
        context.coordinator.renderIfNeeded()
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "pele")
        webView.stopLoading()
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MermaidWebView
        weak var webView: WKWebView?

        private var isLoaded = false
        private var lastSource: String?
        private var lastTheme: MermaidTheme?

        init(_ parent: MermaidWebView) {
            self.parent = parent
        }

        func configure(_ webView: WKWebView) {
            webView.enclosingScrollView?.hasVerticalScroller = false
            webView.enclosingScrollView?.hasHorizontalScroller = false
            webView.enclosingScrollView?.verticalScrollElasticity = .none
            webView.enclosingScrollView?.horizontalScrollElasticity = .none
            webView.enclosingScrollView?.drawsBackground = false
        }

        func renderIfNeeded(force: Bool = false) {
            guard isLoaded, let webView else { return }
            guard force || parent.source != lastSource || parent.theme != lastTheme else {
                return
            }

            lastSource = parent.source
            lastTheme = parent.theme

            let source = Self.jsonString(parent.source)
            let theme = Self.jsonString(parent.theme.rawValue)
            webView.evaluateJavaScript(
                "window.luminotes.render(\(source), \(theme));",
                completionHandler: nil
            )
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            configure(webView)
            renderIfNeeded(force: true)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                if url.scheme == "http" || url.scheme == "https" {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "pele",
                  let body = message.body as? [String: Any],
                  body["type"] as? String == "height",
                  let value = (body["height"] as? NSNumber)?.doubleValue else {
                return
            }

            let newHeight = max(48, min(8000, CGFloat(value)))
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.parent.height - newHeight) > 0.5 else { return }
                self.parent.height = newHeight
            }
        }

        private static func jsonString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let string = String(data: data, encoding: .utf8) else {
                return "\"\""
            }
            return string
        }
    }
}

private enum MermaidPage {
    static let html: String? = {
        guard let url = Bundle.main.url(forResource: "pele.global", withExtension: "js"),
              let script = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        // Keep the embedded script from closing the surrounding HTML tag.
        let safeScript = script.replacingOccurrences(of: "</script", with: "<\\/script")

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            :root { color-scheme: light dark; }
            html, body {
                margin: 0;
                padding: 0;
                width: 100%;
                height: 100%;
                background: transparent;
                overflow: hidden;
            }
            #diagram {
                width: 100%;
                min-height: 24px;
                box-sizing: border-box;
                display: flex;
                align-items: flex-start;
                justify-content: center;
                --pele-font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
                --pele-font-mono: ui-monospace, "SF Mono", Menlo, monospace;
                --pele-radius: 6px;
            }
            #diagram > svg {
                display: block;
                flex: 0 0 auto;
                max-width: 100%;
                margin: 0 auto;
            }
            #diagram .pele-error {
                font: 12px -apple-system, BlinkMacSystemFont, sans-serif;
                line-height: 1.45;
                white-space: pre-wrap;
                text-align: left;
                padding: 8px 10px;
                flex: 1 1 auto;
            }
        </style>
        </head>
        <body>
        <div id="diagram"></div>
        <script>\(safeScript)</script>
        <script>
        (function () {
            var container = document.getElementById('diagram');
            var mounted = null;
            var lastSource = null;
            var frameScheduled = false;

            var light = {
                '--pele-bg': 'transparent',
                '--pele-fg': '#37352f',
                '--pele-muted': '#787774',
                '--pele-line': '#4a4843',
                '--pele-surface': 'rgba(55, 53, 47, 0.045)',
                '--pele-surface-alt': 'rgba(55, 53, 47, 0.08)',
                '--pele-border': 'rgba(55, 53, 47, 0.16)',
                '--pele-accent': '#2f6fed',
                '--pele-error': '#c0392b'
            };

            var dark = {
                '--pele-bg': 'transparent',
                '--pele-fg': '#dadada',
                '--pele-muted': '#9a9a97',
                '--pele-line': '#c7c7c3',
                '--pele-surface': 'rgba(255, 255, 255, 0.06)',
                '--pele-surface-alt': 'rgba(255, 255, 255, 0.10)',
                '--pele-border': 'rgba(255, 255, 255, 0.16)',
                '--pele-accent': '#6c9cff',
                '--pele-error': '#ff8078'
            };

            function postHeight() {
                if (frameScheduled) return;
                frameScheduled = true;
                requestAnimationFrame(function () {
                    frameScheduled = false;
                    var rect = container.getBoundingClientRect();
                    var height = Math.ceil(rect.height + 4);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pele) {
                        window.webkit.messageHandlers.pele.postMessage({
                            type: 'height',
                            height: height
                        });
                    }
                });
            }

            function applyTheme(theme) {
                var variables = theme === 'dark' ? dark : light;
                for (var key in variables) {
                    container.style.setProperty(key, variables[key]);
                }
                document.documentElement.style.colorScheme = theme;
            }

            window.luminotes = {
                render: function (source, theme) {
                    applyTheme(theme);

                    if (mounted) {
                        if (source !== lastSource) {
                            lastSource = source;
                            mounted.update(source);
                        }
                        postHeight();
                        return;
                    }

                    lastSource = source;
                    mounted = pele.mount(container, source, {
                        zoom: false,
                        links: false,
                        images: false,
                        padding: 0
                    });
                    postHeight();
                }
            };

            var observer = new ResizeObserver(postHeight);
            observer.observe(document.body);
            observer.observe(container);
            window.addEventListener('load', postHeight);
        })();
        </script>
        </body>
        </html>
        """
    }()

    static let missingLibraryHTML = """
    <!doctype html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
        html, body {
            margin: 0;
            height: 100%;
            background: transparent;
            overflow: hidden;
        }
        body {
            display: flex;
            align-items: center;
            justify-content: center;
            font: 12px -apple-system, BlinkMacSystemFont, sans-serif;
            color: #787774;
        }
    </style>
    </head>
    <body>Could not load the bundled diagram renderer.</body>
    </html>
    """
}
