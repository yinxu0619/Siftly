import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// About / sponsor panel.
struct AboutView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    private enum SponsorTab: String, CaseIterable, Identifiable {
        case wechat, alipay, paypal
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wechat: return L10n.wechat
            case .alipay: return L10n.alipay
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
                Button(L10n.done) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

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

            Text(L10n.appName).font(.title.bold())
            Text(L10n.version(version)).font(.caption).foregroundStyle(.secondary)
            Text(L10n.aboutTagline)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sponsor: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(L10n.sponsorTitle).font(.headline)
                Text(L10n.sponsorBlurb)
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
            qrCode(named: "sponsor-wechat", caption: L10n.wechatQRHint, accent: Color.green)
        case .alipay:
            qrCode(named: "sponsor-alipay", caption: L10n.alipayQRHint, accent: Color.blue)
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
                    .overlay(Text(L10n.qrNotFound).foregroundStyle(.secondary))
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
            Text(L10n.paypalOnline)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                app.openExternalURL(paypalURL)
            } label: {
                Label(L10n.openPayPal, systemImage: "arrow.up.right.square")
                    .frame(maxWidth: 240)
            }
            .buttonStyle(.borderedProminent)

            Button {
                app.copyToClipboard(paypalURL)
            } label: {
                Text(L10n.copyLink)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var appIcon: NSImage? {
        #if os(macOS)
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
