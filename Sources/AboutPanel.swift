// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import SwiftUI

public struct AboutPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var logo: NSImage?

    private let appName: String
    private let version: String
    private let build: String
    private let copyright: String
    private let repoURL: URL?

    public init() {
        let info = Bundle.main.infoDictionary ?? [:]
        self.appName = info["CFBundleDisplayName"] as? String
            ?? info["CFBundleName"] as? String
            ?? "WriteAssist"
        self.version = info["CFBundleShortVersionString"] as? String ?? "—"
        self.build = info["CFBundleVersion"] as? String ?? "—"
        self.copyright = info["NSHumanReadableCopyright"] as? String
            ?? "© Igor Alves"
        self.repoURL = URL(string: "https://github.com/iguit0/write-assist")
    }

    private func loadLogo(for scheme: ColorScheme) -> NSImage? {
        let resource = scheme == .dark ? "write-assist-logo-dark" : "write-assist-logo-light"
        return Bundle.module.image(forResource: resource)
    }

    public var body: some View {
        VStack(spacing: 16) {
            logoView
                .frame(width: 128, height: 128)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.system(size: 22, weight: .semibold))
                Text("Version \(version) (\(build))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("Your writing companion for clearer, more confident English.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)

            if let repoURL {
                Link("View on GitHub", destination: repoURL)
                    .font(.system(size: 11))
            }

            Text(copyright)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 360)
        .onAppear { logo = loadLogo(for: colorScheme) }
        .onChange(of: colorScheme) { _, new in logo = loadLogo(for: new) }
    }

    @ViewBuilder
    private var logoView: some View {
        if let logo {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "pencil.and.sparkles")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}
