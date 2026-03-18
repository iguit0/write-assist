// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import AppKit
import SwiftUI

// MARK: - Menu Bar Popover Root View

enum PopoverTab: String, CaseIterable {
    case issues = "Issues"
    case tools = "Tools"
    case settings = "Settings"
}

struct MenuBarPopoverView: View {
    var viewModel: DocumentViewModel
    var inputMonitor: GlobalInputMonitor
    @State private var animateIn = false
    @State private var isPreviewExpanded = true
    @State private var isMetricsExpanded = false
    @State private var selectedTab: PopoverTab = .issues
    @State private var selectedTextForSuggestions: String?
    @State private var selectedTextRange: NSRange?

    var body: some View {
        VStack(spacing: 0) {
            popoverHeader
            Divider()

            if !inputMonitor.hasAccessibilityPermission {
                accessibilityPrompt
            } else {
                // Tab bar
                tabBar
                Divider()

                switch selectedTab {
                case .issues:
                    issuesList
                case .tools:
                    ToolsPanel()
                case .settings:
                    SettingsPanel()
                }
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

    // MARK: - Header

    private var popoverHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .foregroundStyle(.tint)
                .font(.system(size: 14, weight: .medium))

            Text("WriteAssist")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            // Word count
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

    // MARK: - Metrics Drawer

    private var metricsDrawer: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isMetricsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isMetricsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Metrics")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isMetricsExpanded {
                metricsContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    private var metricsContent: some View {
        VStack(spacing: 8) {
            // Row 1: Readability and times
            HStack(spacing: 12) {
                metricItem(
                    label: "Readability",
                    value: String(format: "%.0f", viewModel.readabilityScore),
                    icon: "book.fill",
                    color: viewModel.readabilityScore >= 60 ? .green : (viewModel.readabilityScore >= 30 ? .orange : .red)
                )
                metricItem(
                    label: "Read time",
                    value: formatTime(viewModel.readingTime),
                    icon: "clock",
                    color: .blue
                )
                metricItem(
                    label: "Speak time",
                    value: formatTime(viewModel.speakingTime),
                    icon: "mic",
                    color: .purple
                )
            }

            // Row 2: Structure stats
            HStack(spacing: 12) {
                metricItem(
                    label: "Sentences",
                    value: "\(viewModel.sentenceCount)",
                    icon: "text.alignleft",
                    color: .secondary
                )
                metricItem(
                    label: "Avg length",
                    value: String(format: "%.1f", viewModel.averageSentenceLength),
                    icon: "ruler",
                    color: .secondary
                )
                metricItem(
                    label: "Vocab",
                    value: String(format: "%.0f%%", viewModel.vocabularyDiversity * 100),
                    icon: "textformat.abc",
                    color: viewModel.vocabularyDiversity >= 0.7 ? .green : .orange
                )
            }

            // Row 3: Tone indicator
            HStack(spacing: 6) {
                Image(systemName: viewModel.detectedTone.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.tint)
                Text("Tone:")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(viewModel.detectedTone.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func metricItem(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(color)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatTime(_ minutes: Double) -> String {
        if minutes < 1 {
            return "<1m"
        } else if minutes < 60 {
            return String(format: "%.0fm", minutes)
        } else {
            let h = Int(minutes / 60)
            let m = Int(minutes.truncatingRemainder(dividingBy: 60))
            return "\(h)h\(m)m"
        }
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        VStack(spacing: 0) {
            // Collapsible header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPreviewExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isPreviewExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Text Preview")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !viewModel.issues.isEmpty {
                        let sc = viewModel.spellingCount
                        let gc = viewModel.grammarCount
                        HStack(spacing: 4) {
                            if sc > 0 {
                                Text("\(sc) spell")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                            if gc > 0 {
                                Text("\(gc) grammar")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPreviewExpanded {
                HighlightedTextView(
                    text: viewModel.text,
                    issues: viewModel.issues,
                    onSelectionChanged: { selectedText, selectedRange in
                        selectedTextForSuggestions = selectedText
                        selectedTextRange = selectedRange
                    }
                )
                    .frame(height: min(max(CGFloat(viewModel.text.count) / 4 + 48, 56), 110))
                    .overlay(alignment: .topLeading) {
                        if viewModel.text.isEmpty {
                            if #available(macOS 14.0, *) {
                                EmptyView()
                            } else {
                                Text("Type or paste your text here…")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }

    // MARK: - Category Filter

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(label: "All", category: nil, count: viewModel.totalActiveIssueCount)

                ForEach(IssueCategory.allCases, id: \.self) { category in
                    let count = viewModel.issues.filter { $0.type.category == category }.count
                    if count > 0 {
                        categoryChip(label: category.rawValue, category: category, count: count)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func categoryChip(label: String, category: IssueCategory?, count: Int) -> some View {
        let isSelected = viewModel.selectedCategory == category
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.selectedCategory = category
            }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isSelected ? (category?.color ?? .primary) : Color.secondary.opacity(0.15))
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isSelected ? (category?.color ?? .primary).opacity(0.15) : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? (category?.color ?? .primary).opacity(0.3) : Color.secondary.opacity(0.15),
                    lineWidth: 0.5
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Issues List

    private var issuesList: some View {
        VStack(spacing: 0) {
            // Issue count chips
            if viewModel.totalActiveIssueCount > 0 {
                HStack(spacing: 8) {
                    if viewModel.spellingCount > 0 {
                        issueChip(count: viewModel.spellingCount, label: "spelling", color: .red)
                    }
                    if viewModel.grammarCount > 0 {
                        issueChip(count: viewModel.grammarCount, label: "grammar", color: .orange)
                    }
                    if viewModel.clarityCount > 0 {
                        issueChip(count: viewModel.clarityCount, label: "clarity", color: .blue)
                    }
                    if viewModel.engagementCount > 0 {
                        issueChip(count: viewModel.engagementCount, label: "engagement", color: .purple)
                    }
                    if viewModel.styleCount > 0 {
                        issueChip(count: viewModel.styleCount, label: "style", color: .green)
                    }
                    Spacer()

                    // Clear buffer button
                    Button {
                        inputMonitor.clearBuffer()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear captured text")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            // Metrics drawer — shown when there's captured text
            if viewModel.wordCount > 0 {
                metricsDrawer
                Divider()
            }

            // Text preview panel — shown when there's captured text.
            // Only prepend a divider when the chips strip above wasn't shown
            // (which already has its own trailing divider).
            if !viewModel.text.isEmpty {
                let hasChips = viewModel.totalActiveIssueCount > 0
                if !hasChips && viewModel.wordCount == 0 {
                    Divider()
                }
                previewPanel
                
                // AI suggestions panel — shown when text is selected in preview
                if let selectedText = selectedTextForSuggestions, !selectedText.isEmpty {
                    Divider()
                    TextSelectionSuggestionsPanel(
                        selectedText: selectedText,
                        onCopy: { suggestion in
                            PasteboardTransaction.write(suggestion)
                            selectedTextForSuggestions = nil
                        },
                        onDismiss: {
                            selectedTextForSuggestions = nil
                        }
                    )
                }
                
                Divider()
            }

            // Category filter (only when there are issues)
            if viewModel.totalActiveIssueCount > 0 {
                categoryFilterChips
                Divider()
            }

            let active = viewModel.filteredIssues

            if active.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(active) { issue in
                            IssueSidebarCard(
                                issue: issue,
                                isNew: viewModel.unseenIssueIDs.contains(issue.id),
                                onApply: { correction in
                                    viewModel.applyCorrection(issue, correction: correction)
                                },
                                onIgnore: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.ignoreIssue(issue)
                                    }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: active.map(\.id))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 380)
            }

            Divider()
            popoverFooter
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 20)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)

            Text("Looking good!")
                .font(.system(size: 13, weight: .semibold))

            Text(viewModel.text.isEmpty
                 ? "Start typing anywhere — WriteAssist is watching."
                 : "No issues found in your recent text.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Accessibility Prompt

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

    // MARK: - Footer

    private var popoverFooter: some View {
        HStack {
            // Monitoring status indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(inputMonitor.hasAccessibilityPermission ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(inputMonitor.hasAccessibilityPermission ? "Monitoring" : "Not active")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Quit button
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

    // MARK: - Helpers

    private func issueChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count) \(label)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Score Badge



// MARK: - Issue Sidebar Card

struct IssueSidebarCard: View {
    let issue: WritingIssue
    let isNew: Bool
    let onApply: (String) -> Void
    let onIgnore: () -> Void

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var copiedSuggestion: String?
    @State private var pulsing = false

    private var accentColor: Color {
        issue.type.color
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 0) {
                    // Thick accent bar with gradient
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 4)
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 8,
                            bottomLeadingRadius: 8,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0
                        ))

                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(issue.word)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)

                                // "NEW" dot for unseen issues
                                if isNew {
                                    Circle()
                                        .fill(accentColor)
                                        .frame(width: 6, height: 6)
                                        .scaleEffect(pulsing ? 1.4 : 1.0)
                                        .opacity(pulsing ? 0.6 : 1.0)
                                        .animation(
                                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                            value: pulsing
                                        )
                                }

                                Spacer()

                                // Issue type chip
                                HStack(spacing: 3) {
                                    Image(systemName: issue.type.icon)
                                        .font(.system(size: 8))
                                    Text(issue.type.categoryLabel)
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.12))
                                .clipShape(Capsule())

                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }

                            Text(issue.message)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded: suggestions
            if isExpanded {
                Divider()
                    .padding(.leading, 24)

                VStack(alignment: .leading, spacing: 2) {
                    if issue.suggestions.isEmpty {
                        Text("No suggestions available")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(issue.suggestions.prefix(4), id: \.self) { suggestion in
                            Button {
                                onApply(suggestion)
                                copiedSuggestion = suggestion
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(1500))
                                    if copiedSuggestion == suggestion {
                                        copiedSuggestion = nil
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: copiedSuggestion == suggestion
                                          ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(copiedSuggestion == suggestion ? .green : accentColor)
                                    Text(copiedSuggestion == suggestion ? "Applied ✓" : suggestion)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(copiedSuggestion == suggestion ? .green : .primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    copiedSuggestion == suggestion
                                        ? Color.green.opacity(0.08)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .animation(.easeInOut(duration: 0.15), value: copiedSuggestion)
                        }
                    }

                    Divider()
                        .padding(.leading, 14)

                    Button(action: onIgnore) {
                        HStack(spacing: 5) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 10))
                            Text("Dismiss")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isHovered
                        ? accentColor.opacity(0.04)
                        : Color(nsColor: .textBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isNew ? accentColor.opacity(pulsing ? 0.5 : 0.2) : Color.clear,
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: .black.opacity(isHovered ? 0.1 : 0.05),
                    radius: isHovered ? 4 : 2,
                    y: 1
                )
        )
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .onAppear {
            if isNew {
                pulsing = true
            }
        }
    }
}

// MARK: - Settings Panel

struct SettingsPanel: View {
    @State private var prefs = PreferencesManager.shared
    @State private var aiService = CloudAIService.shared
    @State private var isRuleTogglesExpanded = false
    @State private var apiKeyInput = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Bool?
    // Ollama state
    @State private var ollamaModels: [OllamaModel] = []
    @State private var isLoadingModels = false
    @State private var ollamaReachable: Bool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // AI Provider
                settingsSection(title: "AI Provider", icon: "sparkles") {
                    Picker("Provider", selection: $aiService.provider) {
                        Text("Anthropic").tag(AIProvider.anthropic)
                        Text("OpenAI").tag(AIProvider.openai)
                        Text("Ollama").tag(AIProvider.ollama)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: aiService.provider) {
                        connectionTestResult = nil
                        if aiService.provider == .ollama {
                            checkOllamaStatus()
                        }
                    }

                    if aiService.provider == .ollama {
                        ollamaSettingsContent
                    } else {
                        cloudSettingsContent
                    }
                }

                // Writing preset
                settingsSection(title: "Writing Preset", icon: "doc.text") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                        spacing: 6
                    ) {
                        ForEach(WritingPreset.allCases, id: \.self) { preset in
                            pillButton(
                                preset.rawValue,
                                isSelected: prefs.writingPreset == preset
                            ) { prefs.writingPreset = preset }
                        }
                    }
                }

                // Formality
                settingsSection(title: "Formality", icon: "slider.horizontal.3") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                        spacing: 6
                    ) {
                        ForEach(FormalityLevel.allCases, id: \.self) { level in
                            pillButton(
                                level.rawValue,
                                isSelected: prefs.formalityLevel == level
                            ) { prefs.formalityLevel = level }
                        }
                    }
                }

                // Audience
                settingsSection(title: "Audience", icon: "person.2") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                        spacing: 6
                    ) {
                        ForEach(AudienceLevel.allCases, id: \.self) { level in
                            pillButton(
                                level.rawValue,
                                isSelected: prefs.audienceLevel == level
                            ) { prefs.audienceLevel = level }
                        }
                    }
                }

                // Rule toggles
                settingsSection(title: "Rules", icon: "checklist") {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isRuleTogglesExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text(isRuleTogglesExpanded ? "Hide rules" : "Show rules")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: isRuleTogglesExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isRuleTogglesExpanded {
                        VStack(spacing: 4) {
                            ForEach(RuleRegistry.allRules, id: \.ruleID) { rule in
                                ruleToggleRow(rule: rule)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 420)
    }

    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func ruleToggleRow(rule: any WritingRule) -> some View {
        HStack(spacing: 8) {
            Image(systemName: rule.issueType.icon)
                .font(.system(size: 10))
                .foregroundStyle(rule.issueType.color)
                .frame(width: 16)

            Text(rule.issueType.categoryLabel)
                .font(.system(size: 11))

            Spacer()

            Toggle("", isOn: Binding(
                get: { prefs.isRuleEnabled(rule.ruleID) },
                set: { _ in prefs.toggleRule(rule.ruleID) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    private func pillButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    isSelected
                        ? Color.accentColor
                        : Color.secondary.opacity(0.12)
                )
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ollama Settings

    private var ollamaSettingsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Server URL
            HStack(spacing: 6) {
                TextField("Server URL", text: $aiService.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { checkOllamaStatus() }

                Button {
                    checkOllamaStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Connection status
            HStack(spacing: 8) {
                if let reachable = ollamaReachable {
                    Circle()
                        .fill(reachable ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(reachable ? "Connected" : "Not running")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Checking...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Non-loopback URL security warning
            if !aiService.isOllamaURLSafe {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("Security: URL must be localhost or 127.0.0.1. Remote URLs are blocked to prevent your text from being sent to an unknown host.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.12))
                .clipShape(.rect(cornerRadius: 4))
            }

            // Model picker
            if ollamaReachable == true {
                HStack(spacing: 6) {
                    Picker("Model", selection: $aiService.ollamaModelName) {
                        if aiService.ollamaModelName.isEmpty {
                            Text("Select a model").tag("")
                        }
                        ForEach(ollamaModels) { model in
                            Text("\(model.name) (\(model.formattedSize))").tag(model.name)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 11))

                    if isLoadingModels {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Button {
                            loadOllamaModels()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Test button
                if !aiService.ollamaModelName.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            isTestingConnection = true
                            connectionTestResult = nil
                            Task {
                                let result = await aiService.testConnection()
                                isTestingConnection = false
                                connectionTestResult = result
                            }
                        } label: {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Text("Test Model")
                                    .font(.system(size: 10))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        if let result = connectionTestResult {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result ? .green : .red)
                                .font(.system(size: 12))
                        }

                        Spacer()
                    }
                }
            } else if ollamaReachable == false {
                Text("Start Ollama to select a model: `ollama serve`")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { checkOllamaStatus() }
    }

    private var cloudSettingsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Model name field
            HStack(spacing: 6) {
                Text("Model")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)
                let modelBinding = aiService.provider == .anthropic
                    ? Binding(
                        get: { PreferencesManager.shared.anthropicModelName },
                        set: { PreferencesManager.shared.anthropicModelName = $0 }
                    )
                    : Binding(
                        get: { PreferencesManager.shared.openAIModelName },
                        set: { PreferencesManager.shared.openAIModelName = $0 }
                    )
                TextField("Model name", text: modelBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            HStack(spacing: 6) {
                SecureField("API Key", text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))

                Button {
                    aiService.setAPIKey(apiKeyInput)
                    apiKeyInput = ""
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(apiKeyInput.isEmpty)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(aiService.hasAPIKey() ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(aiService.hasAPIKey() ? "API key configured" : "No API key")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                if aiService.hasAPIKey() {
                    Button {
                        isTestingConnection = true
                        connectionTestResult = nil
                        Task {
                            let result = await aiService.testConnection()
                            isTestingConnection = false
                            connectionTestResult = result
                        }
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text("Test")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    if let result = connectionTestResult {
                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result ? .green : .red)
                            .font(.system(size: 12))
                    }
                }
            }

            Text("Cloud AI runs only when you explicitly request suggestions or rewrites. Passive spell checks stay local.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Ollama Helpers

    private func checkOllamaStatus() {
        ollamaReachable = nil
        Task {
            let reachable = await aiService.isOllamaReachable()
            ollamaReachable = reachable
            if reachable {
                loadOllamaModels()
            }
        }
    }

    private func loadOllamaModels() {
        isLoadingModels = true
        Task {
            do {
                ollamaModels = try await aiService.listOllamaModels()
                // If current model name is empty or not in list, select the first one
                if !ollamaModels.contains(where: { $0.name == aiService.ollamaModelName }),
                   let first = ollamaModels.first {
                    aiService.ollamaModelName = first.name
                }
            } catch {
                ollamaModels = []
            }
            isLoadingModels = false
        }
    }
}

// MARK: - Tools Panel (Dictionary, Stats)

enum ToolsTab: String, CaseIterable {
    case dictionary = "Dictionary"
    case stats = "Stats"
}

struct ToolsPanel: View {
    @State private var selectedTab: ToolsTab = .dictionary

    var body: some View {
        VStack(spacing: 0) {
            // Sub-tab selector
            HStack(spacing: 4) {
                ForEach(ToolsTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
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
            .padding(.vertical, 6)

            Divider()

            switch selectedTab {
            case .dictionary:
                DictionaryView()
            case .stats:
                StatsView()
            }
        }
    }
}

// MARK: - Dictionary View

struct DictionaryView: View {
    @State private var dictionary = PersonalDictionary.shared
    @State private var newWord = ""

    var body: some View {
        VStack(spacing: 0) {
            // Add word field
            HStack(spacing: 6) {
                TextField("Add word...", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { addWord() }

                Button(action: addWord) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if dictionary.words.isEmpty {
                VStack(spacing: 8) {
                    Spacer(minLength: 20)
                    Image(systemName: "book.closed")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No custom words")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("Words you add will be recognized by the spell checker.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Spacer(minLength: 20)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(dictionary.words, id: \.self) { word in
                            HStack {
                                Text(word)
                                    .font(.system(size: 11))
                                Spacer()
                                Button {
                                    dictionary.removeWord(word)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        dictionary.addWord(trimmed)
        newWord = ""
    }
}

// MARK: - Stats View

struct StatsView: View {
    @State private var stats = WritingStatsStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Current session
                statsSection(title: "Current Session") {
                    HStack(spacing: 16) {
                        statItem(label: "Words", value: "\(stats.currentSessionWordCount)")
                        statItem(label: "Corrections", value: "\(stats.currentSessionCorrections)")
                    }
                }

                // This week
                statsSection(title: "This Week") {
                    HStack(spacing: 16) {
                        statItem(label: "Words", value: "\(stats.wordsThisWeek)")
                        statItem(label: "Sessions", value: "\(stats.sessionsThisWeek.count)")
                    }
                }

                // All time
                statsSection(title: "All Time") {
                    HStack(spacing: 16) {
                        statItem(label: "Words", value: "\(stats.totalWordsWritten)")
                        statItem(label: "Corrections", value: "\(stats.totalCorrections)")
                        statItem(label: "Sessions", value: "\(stats.sessions.count)")
                    }
                }

                // Top recurring issues
                if !stats.topRecurringIssues.isEmpty {
                    statsSection(title: "Top Issues") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(stats.topRecurringIssues, id: \.type) { item in
                                HStack {
                                    Text(item.type)
                                        .font(.system(size: 10))
                                    Spacer()
                                    Text("\(item.count)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 380)
    }

    private func statsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
        )
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Text Selection AI Suggestions Panel

struct TextSelectionSuggestionsPanel: View {
    let selectedText: String
    let onCopy: (String) -> Void
    let onDismiss: () -> Void

    @State private var aiService = CloudAIService.shared
    @State private var suggestions: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copiedSuggestion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Text("AI Suggestions")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            // Content
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Getting suggestions...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else if let error = errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Error")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            } else if suggestions.isEmpty {
                Text("No suggestions available")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Click a suggestion to copy it. Passive spell checks stay local.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                    ForEach(suggestions.prefix(3), id: \.self) { suggestion in
                        SuggestionButton(
                            suggestion: suggestion,
                            isApplied: copiedSuggestion == suggestion,
                            onTap: {
                                copiedSuggestion = suggestion
                                onCopy(suggestion)
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(800))
                                    onDismiss()
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            fetchSuggestions()
        }
    }

    private func fetchSuggestions() {
        guard aiService.isConfigured else {
            errorMessage = "AI is not configured. Add an API key in Settings."
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                // Create a synthetic issue for the selected text
                let issue = WritingIssue(
                    type: .style,
                    ruleID: "formality",
                    range: NSRange(location: 0, length: selectedText.count),
                    word: String(selectedText.prefix(20)),
                    message: "Improve this selection",
                    suggestions: []
                )

                let fetchedSuggestions = try await aiService.smartSuggestions(
                    for: issue,
                    context: selectedText
                )
                suggestions = fetchedSuggestions
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Suggestion Button

struct SuggestionButton: View {
    let suggestion: String
    let isApplied: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isApplied ? "checkmark.circle.fill" : "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(isApplied ? .green : .blue)

                Text(suggestion)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isApplied ? .green : .primary)
                    .lineLimit(2)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isApplied
                            ? Color.green.opacity(0.1)
                            : isHovered
                            ? Color.blue.opacity(0.08)
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isApplied)
    }
}
