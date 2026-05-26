import AppKit
import SwiftUI

struct CopyIconButton: View {
    let value: String
    var help: String?

    var body: some View {
        Button {
            guard !value.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .disabled(value.isEmpty)
        .help(help ?? value)
    }
}
