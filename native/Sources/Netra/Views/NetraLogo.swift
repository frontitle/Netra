import AppKit
import SwiftUI

/// 应用内品牌 Logo（与 AppIcon 同源资源）。
struct NetraLogo: View {
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let image = Self.nsImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                Image(systemName: "eye.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.cyan, .white.opacity(0.2))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: .cyan.opacity(0.25), radius: size * 0.12)
    }

    private static let nsImage: NSImage? = {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }()
}
