import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct RunCommandSheet: View {
  let appSlug: String
  let build: Build

  @ObservedObject var presetsStore: CommandPresetsStore
  @StateObject private var runner = LocalCommandRunner()

  @Environment(\.dismiss) private var dismiss

  @State private var selectedPresetID: UUID?
  @State private var draftTemplate = ""
  @State private var isDirty = false
  @State private var showRawOutput = false
  @State private var wrapOutputLines = true

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(16)

      Divider()

      VStack(spacing: 0) {
        configPane
          .frame(maxWidth: .infinity, minHeight: 280, idealHeight: 330)

        Divider()

        outputPane
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(minWidth: 980, minHeight: 680)
    .onAppear {
      selectedPresetID = presetsStore.selectedPresetID
      if let preset = presetsStore.selectedPreset {
        draftTemplate = preset.template
      }
    }
    .onChange(of: selectedPresetID) { _, newValue in
      presetsStore.selectPreset(id: newValue)
      if let preset = presetsStore.selectedPreset {
        draftTemplate = preset.template
        isDirty = false
      }
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Run Command")
          .font(.title2.weight(.semibold))

        Text("#\(build.buildNumber) • \(build.workflowID) • \(build.branch)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if runner.isRunning {
        ProgressView()
          .controlSize(.small)
      } else if let exitCode = runner.exitCode {
        Text(exitCode == 0 ? "Succeeded" : "Failed (exit \(exitCode))")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(exitCode == 0 ? .green : .red)
      }
    }
  }

  private var configPane: some View {
    VStack(spacing: 0) {
      Form {
        Section("Preset") {
          Picker("Preset", selection: $selectedPresetID) {
            ForEach(presetsStore.presets) { preset in
              Text(preset.name).tag(Optional(preset.id))
            }
          }
          .labelsHidden()

          TextField("Working directory", text: Binding(
            get: { presetsStore.workingDirectory },
            set: { presetsStore.setWorkingDirectory($0) }
          ))
          .textFieldStyle(.roundedBorder)
        }

        Section("Command Template") {
          TextEditor(text: Binding(
            get: { draftTemplate },
            set: { newValue in
              draftTemplate = newValue
              isDirty = true
            }
          ))
          .font(.system(.body, design: .monospaced))
          .frame(height: 82)

          Text("Variables: {{buildSlug}}, {{buildNumber}}, {{workflowID}}, {{branch}}, {{status}}, {{artifactTitle}}, {{artifactType}}, {{appVersion}}, {{appBuildNumber}}, {{appSlug}}")
            .font(.caption)
            .foregroundStyle(.secondary)

          VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(renderedCommand)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .foregroundStyle(.secondary)
          }
        }
      }

      Divider()

      HStack {
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)

        Spacer()

        if runner.isRunning {
          Button("Stop") { runner.cancel() }
            .keyboardShortcut(.escape, modifiers: [])
        } else {
          Button("Save Preset") { savePreset() }
            .disabled(!canSavePreset)

          Button("Run") { runNow() }
            .keyboardShortcut(.defaultAction)
            .disabled(renderedCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
    .padding(.top, 12)
  }

  private var outputPane: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Output", systemImage: "terminal")
          .font(.headline)

        if runner.isRunning {
          Text("Live")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.green.opacity(0.16), in: Capsule())
            .foregroundStyle(.green)
        }

        Spacer()

        Picker("", selection: $showRawOutput) {
          Text("Clean").tag(false)
          Text("Raw").tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 140)

        HStack(spacing: 6) {
          Text("Wrap")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle("", isOn: $wrapOutputLines)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }

        Button("Copy") { copyOutput() }
          .disabled(displayedOutput.isEmpty)

        Button("Clear") { runner.clearOutput() }
          .disabled(displayedOutput.isEmpty || runner.isRunning)
      }
      .padding(.horizontal, 16)
      .padding(.top, 10)

      outputConsole
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }
  }

  private var outputConsole: some View {
    ScrollViewReader { proxy in
      ScrollView(outputScrollAxes) {
        VStack(alignment: .leading, spacing: 0) {
          Text(displayedOutput.isEmpty ? "No output yet." : displayedOutput)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: wrapOutputLines ? .infinity : nil, alignment: .leading)
            .fixedSize(horizontal: !wrapOutputLines, vertical: true)
            .padding(16)
            .foregroundStyle(displayedOutput.isEmpty ? .secondary : .primary)
            .id("output-text")

          Color.clear
            .frame(height: 1)
            .id("output-end")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(terminalBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .onChange(of: displayedOutput) { _, _ in
        guard runner.isRunning else { return }
        proxy.scrollTo("output-end", anchor: .bottom)
      }
      .onAppear {
        proxy.scrollTo("output-end", anchor: .bottom)
      }
    }
  }

  private var displayedOutput: String {
    showRawOutput ? runner.rawOutput : runner.output
  }

  private var outputScrollAxes: Axis.Set {
    wrapOutputLines ? .vertical : [.vertical, .horizontal]
  }

  private var terminalBackground: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10)
        .fill(Color.black.opacity(0.76))
      LinearGradient(
        colors: [Color.white.opacity(0.03), Color.clear],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .clipShape(RoundedRectangle(cornerRadius: 10))
    }
  }

  private var renderedCommand: String {
    CommandTemplate.render(draftTemplate, variables: build.commandVariables(appSlug: appSlug))
  }

  private var canSavePreset: Bool {
    guard isDirty else { return false }
    guard let preset = presetsStore.selectedPreset else { return false }
    return !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func savePreset() {
    guard var preset = presetsStore.selectedPreset else { return }
    preset.template = draftTemplate
    presetsStore.upsertPreset(preset)
    isDirty = false
  }

  private func runNow() {
    if isDirty {
      savePreset()
    }
    runner.run(
      command: renderedCommand,
      workingDirectory: presetsStore.workingDirectory,
      environment: CommandEnvironment.variables(appSlug: appSlug, build: build)
    )
  }

  private func copyOutput() {
    guard !displayedOutput.isEmpty else { return }
    #if canImport(AppKit)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(displayedOutput, forType: .string)
    #endif
  }
}

#Preview {
  RunCommandSheet(
    appSlug: "MOCK_APP_SLUG",
    build: Build(
      id: "MOCK_BUILD_ID",
      buildNumber: 123,
      workflowID: "primary",
      branch: "main",
      title: "PR: Add run command UX",
      status: .success,
      startedAt: .now,
      artifact: BuildArtifact(
        title: "MyApp-v1.2.3 (456).ipa",
        type: "ios-ipa",
        appVersion: "1.2.3",
        appBuildNumber: "456"
      )
    ),
    presetsStore: CommandPresetsStore()
  )
}
