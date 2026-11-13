import SwiftTerm
import SwiftUI

/// The VM's console as a terminal: SwiftTerm (MIT) draws what the guest prints
/// and turns typing into the bytes a terminal sends.
struct ConsoleView: UIViewRepresentable {
    let bridge: ConsoleBridge

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge)
    }

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.nativeBackgroundColor = .black
        view.nativeForegroundColor = UIColor(white: 0.92, alpha: 1)
        view.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        bridge.connect { [weak view] bytes in
            view?.feed(byteArray: bytes[...])
        }
        return view
    }

    func updateUIView(_ view: TerminalView, context: Context) {}

    static func dismantleUIView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.bridge.disconnect()
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let bridge: ConsoleBridge

        init(bridge: ConsoleBridge) {
            self.bridge = bridge
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            bridge.send(data)
        }

        // A serial console has no window size to report, no title and no
        // working directory; the rest needs nothing yet.
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {
            UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
        }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
