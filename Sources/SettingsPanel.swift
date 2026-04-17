// WriteAssist — macOS menu bar writing assistant
// Copyright © 2025 Igor Alves. All rights reserved.

import SwiftUI

public struct SettingsPanel: View {
    private enum SettingsTab: Hashable {
        case general
        case writing
        case ai
    }

    public init() {}

    @State private var prefs = PreferencesManager.shared
    @State private var aiService = CloudAIService.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var isRuleTogglesExpanded = false
    @State private var apiKeyInput = ""
    @State private var isTestingConnection = false
    @State private var connectionTestResult: Bool?
    @State private var ollamaModels: [OllamaModel] = []
    @State private var isLoadingModels = false
    @State private var ollamaReachable: Bool?

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                generalTabContent
            }

            Tab("Writing", systemImage: "pencil.line", value: .writing) {
                writingTabContent
            }

            Tab("AI", systemImage: "sparkles", value: .ai) {
                aiTabContent
            }
        }
        .onAppear {
            if aiService.provider == .ollama {
                checkOllamaStatus()
            }
        }
    }

    private var generalTabContent: some View {
        tabScrollContent {
            settingsSection(title: "Current Setup", icon: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 8) {
                    summaryRow("Writing Preset", value: prefs.writingPreset.rawValue)
                    summaryRow("Formality", value: prefs.formalityLevel.rawValue)
                    summaryRow("Audience", value: prefs.audienceLevel.rawValue)
                    summaryRow("AI Provider", value: aiService.provider.rawValue)

                    if aiService.provider == .ollama {
                        summaryRow("Server", value: aiService.ollamaBaseURL)
                        summaryRow(
                            "Model",
                            value: aiService.ollamaModelName.isEmpty ? "No model selected" : aiService.ollamaModelName
                        )
                        summaryRow("Status", value: ollamaStatusSummary)
                    } else {
                        summaryRow("Model", value: currentCloudModelName)
                        summaryRow("Access", value: aiService.hasAPIKey() ? "API key configured" : "No API key")
                    }
                }
            }

            settingsSection(title: "Privacy & Usage", icon: "lock.shield") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Passive spell checks stay local.")
                    Text("Cloud AI runs only when you explicitly request suggestions or rewrites.")
                    Text("Ollama connections are restricted to localhost addresses for safety.")
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var writingTabContent: some View {
        tabScrollContent {
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
    }

    private var aiTabContent: some View {
        tabScrollContent {
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
        }
    }

    private var currentCloudModelName: String {
        let modelName = aiService.provider == .anthropic
            ? prefs.anthropicModelName
            : prefs.openAIModelName
        return modelName.isEmpty ? "Not set" : modelName
    }

    private var ollamaStatusSummary: String {
        guard let reachable = ollamaReachable else {
            return "Checking..."
        }
        return reachable ? "Connected" : "Not running"
    }

    private func tabScrollContent<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
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

    private func summaryRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
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

    private var ollamaSettingsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
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
    }

    private var cloudSettingsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }
    }

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
