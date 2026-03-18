// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import SwiftUI

enum PopoverTab: String, CaseIterable {
    case issues = "Issues"
    case tools = "Tools"
    case settings = "Settings"
}

struct MenuBarPopoverView: View {
    var viewModel: DocumentViewModel
    var inputMonitor: GlobalInputMonitor

    @State private var selectedTab: PopoverTab = .issues

    var body: some View {
        VStack(spacing: 0) {
            popoverHeader
            Divider()

            if !inputMonitor.hasAccessibilityPermission {
                accessibilityPrompt
            } else {
                tabBar
                Divider()

                switch selectedTab {
                case .issues:
                    IssuesListView(viewModel: viewModel, inputMonitor: inputMonitor)
                case .tools:
                    ToolsPanel()
                case .settings:
                    SettingsPanel()
                }

                Divider()
                popoverFooter
            }
        }
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(PopoverTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            selectedTab == tab
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var popoverHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .foregroundStyle(.tint)
                .font(.system(size: 14, weight: .medium))

            Text("WriteAssist")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            if viewModel.wordCount > 0 {
                HStack(spacing: 3) {
                    Text("\(viewModel.wordCount)")
                        .font(.system(size: 11, weight: .medium))
                    Text("words")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var accessibilityPrompt: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 16)

            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Accessibility Access Required")
                .font(.system(size: 13, weight: .semibold))

            Text("WriteAssist needs Accessibility permission to monitor your typing across all apps.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button("Enable Access") {
                inputMonitor.requestPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var popoverFooter: some View {
        HStack {
            HStack(spacing: 5) {
                Circle()
                    .fill(inputMonitor.hasAccessibilityPermission ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(inputMonitor.hasAccessibilityPermission ? "Monitoring" : "Not active")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Quit WriteAssist") {
                NSApp.terminate(nil)
            }
            .font(.system(size: 10))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
