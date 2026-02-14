import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct BuildsView: View {
  @ObservedObject var viewModel: BuildsViewModel
  @StateObject private var presetsStore = CommandPresetsStore()

  @State private var selection: String?
  @State private var isShowingRunSheet = false

  var body: some View {
    NavigationStack {
      List(selection: $selection) {
        ForEach(viewModel.builds) { build in
          BuildRow(
            build: build,
            onRun: { run(build: build) },
            onCopyCommand: { copyDefaultCommand(for: build) }
          )
          .tag(build.id)
          .simultaneousGesture(
            TapGesture(count: 2).onEnded {
              run(build: build)
            }
          )
        }
      }
      .overlay {
        if viewModel.isLoading {
          ProgressView("Refreshing…")
            .controlSize(.regular)
        }
      }
      .navigationTitle("Builds")
      .toolbar {
        ToolbarItem(placement: .principal) {
          Picker("Filter", selection: $viewModel.filter) {
            ForEach(BuildsFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 220)
        }

        ToolbarItem(placement: .primaryAction) {
          Button {
            runSelectedBuild()
          } label: {
            Label("Run…", systemImage: "terminal")
          }
          .keyboardShortcut("r", modifiers: [.command, .shift])
          .disabled(selectedBuild == nil)
        }

        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await viewModel.refresh() }
          } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
          }
          .keyboardShortcut("r")
          .disabled(viewModel.isLoading)
        }
      }
    }
    .task {
      await viewModel.refresh()
    }
    .onChange(of: viewModel.filter) { _, _ in
      selection = nil
    }
    .onChange(of: viewModel.allBuilds) { _, newValue in
      if let selection, !newValue.contains(where: { $0.id == selection }) {
        self.selection = nil
      }
    }
    .sheet(isPresented: $isShowingRunSheet) {
      if let build = selectedBuild {
        RunCommandSheet(appSlug: viewModel.appSlugValue, build: build, presetsStore: presetsStore)
      }
    }
    .alert("Refresh failed", isPresented: $viewModel.isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage ?? "Unknown error")
    }
  }

  private var selectedBuild: Build? {
    viewModel.build(withID: selection)
  }

  private func runSelectedBuild() {
    guard selectedBuild != nil else { return }
    isShowingRunSheet = true
  }

  private func run(build: Build) {
    selection = build.id
    isShowingRunSheet = true
  }

  private func copyDefaultCommand(for build: Build) {
    let template = presetsStore.selectedPreset?.template ?? ""
    let rendered = CommandTemplate.render(template, variables: build.commandVariables(appSlug: viewModel.appSlugValue))
#if canImport(AppKit)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(rendered, forType: .string)
#endif
  }
}

private struct BuildRow: View {
  let build: Build
  let onRun: () -> Void
  let onCopyCommand: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      StatusPill(status: build.status)

      VStack(alignment: .leading, spacing: 4) {
        if let title = build.title, !title.isEmpty {
          Text(title)
            .font(.headline)
            .lineLimit(1)
        } else {
          Text("#\(build.buildNumber)")
            .font(.headline)
        }

        Text("#\(build.buildNumber) • Workflow: \(build.workflowID) • Branch: \(build.branch)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if let label = build.artifact?.versionLabel {
        VersionPill(label: label, artifactType: build.artifact?.type)
      }

      Text(build.startedAt, style: .relative)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .contextMenu {
      Button("Run…") { onRun() }
      Button("Copy Command") { onCopyCommand() }
      Button("Copy Build slug") {
#if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(build.id, forType: .string)
#endif
      }
    }
  }
}

private struct VersionPill: View {
  let label: String
  let artifactType: String?

  var body: some View {
    Label {
      Text(label)
    } icon: {
      Image(systemName: iconName)
    }
    .labelStyle(.titleAndIcon)
    .font(.caption.weight(.semibold))
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.secondary.opacity(0.15))
    .clipShape(Capsule())
    .accessibilityLabel("App version: \(label)")
  }

  private var iconName: String {
    switch artifactType {
    case "ios-ipa":
      "applelogo"
    case "android-apk", "android-aab":
      "shippingbox"
    default:
      "app"
    }
  }
}

private struct StatusPill: View {
  let status: BuildStatus

  var body: some View {
    Text(status.rawValue.uppercased())
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(backgroundColor)
      .clipShape(Capsule())
      .accessibilityLabel("Status: \(status.rawValue)")
  }

  private var backgroundColor: Color {
    switch status {
    case .success: .green
    case .failed: .red
    case .running: .blue
    case .aborted: .gray
    }
  }
}

#Preview {
  BuildsView(
    viewModel: BuildsViewModel(
      appSlug: "MOCK_APP_SLUG",
      workflowID: "primary",
      buildsProvider: MockBitriseClient()
    )
  )
}
