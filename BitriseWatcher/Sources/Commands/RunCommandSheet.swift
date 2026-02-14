import SwiftUI

struct RunCommandSheet: View {
  let appSlug: String
  let build: Build

  @ObservedObject var presetsStore: CommandPresetsStore
  @StateObject private var runner = LocalCommandRunner()

  @Environment(\.dismiss) private var dismiss

  @State private var selectedPresetID: UUID?
  @State private var draftTemplate = ""
  @State private var isDirty = false

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(16)

      Divider()

      HStack(spacing: 0) {
        configPane
          .frame(minWidth: 380, idealWidth: 420, maxWidth: 520)

        Divider()

        outputPane
          .frame(minWidth: 420)
      }
    }
    .frame(minWidth: 860, minHeight: 520)
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
        .frame(minHeight: 120)

        Text("Variables: {{buildID}}, {{buildNumber}}, {{workflowID}}, {{branch}}, {{status}}, {{artifactTitle}}, {{artifactType}}, {{appVersion}}, {{appBuildNumber}}, {{appSlug}}")
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

      Section {
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
      }
    }
    .padding(12)
  }

  private var outputPane: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Output")
          .font(.headline)

        Spacer()

        Button("Clear") { runner.clearOutput() }
          .disabled(runner.output.isEmpty || runner.isRunning)
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)

      ScrollView {
        Text(runner.output.isEmpty ? "No output yet." : runner.output)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
          .foregroundStyle(runner.output.isEmpty ? .secondary : .primary)
      }
      .background(Color.secondary.opacity(0.06))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .padding(.horizontal, 16)
      .padding(.bottom, 16)
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

