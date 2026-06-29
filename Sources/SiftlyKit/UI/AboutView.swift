import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// "关于 / 赞助" panel: app info plus donation options (WeChat, Alipay, PayPal).
struct AboutView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    private enum SponsorTab: String, CaseIterable, Identifiable {
        case wechat, alipay, paypal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wechat: return "微信"
            case .alipay: return "支付宝"
            case .paypal: return "PayPal"
            }
        }
    }

    @State private var tab: SponsorTab = .wechat

    private let paypalURL = "https://www.paypal.com/paypalme/yinxu0619"
    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return v ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            Divider()
            sponsor
            Divider()
            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
            }

            Text("Siftly").font(.title.bold())
            Text("版本 \(version)").font(.caption).foregroundStyle(.secondary)
            Text("轻量存储卡素材管理工具 · RAW/JPG 配对联动删除 · 简单后期")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Sponsor

    private var sponsor: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("赞助支持 ❤️").font(.headline)
                Text("如果这个小工具帮到了你，欢迎请作者喝杯咖啡～")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: $tab) {
                ForEach(SponsorTab.allCases) { t in
                    Text(t.title).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            sponsorContent
                .frame(height: 280)
        }
    }

    @ViewBuilder
    private var sponsorContent: some View {
        switch tab {
        case .wechat:
            qrCode(named: "sponsor-wechat", caption: "微信扫一扫赞助", accent: Color.green)
        case .alipay:
            qrCode(named: "sponsor-alipay", caption: "支付宝扫一扫赞助", accent: Color.blue)
        case .paypal:
            paypal
        }
    }

    private func qrCode(named: String, caption: String, accent: Color) -> some View {
        VStack(spacing: 10) {
            if let image = bundledImage(named) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 240, maxHeight: 240)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 240, height: 240)
                    .overlay(Text("二维码未找到").foregroundStyle(.secondary))
            }
            Label(caption, systemImage: "qrcode")
                .font(.callout)
                .foregroundStyle(accent)
        }
    }

    private var paypal: some View {
        VStack(spacing: 14) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
            Text("通过 PayPal 在线赞助")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                app.openExternalURL(paypalURL)
            } label: {
                Label("打开 PayPal 赞助页", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)

            Button {
                app.copyToClipboard(paypalURL)
            } label: {
                Text("复制链接")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private var appIcon: NSImage? {
        #if canImport(AppKit)
        NSApplication.shared.applicationIconImage
        #else
        nil
        #endif
    }

    private func bundledImage(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
