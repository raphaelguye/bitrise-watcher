import SwiftUI

struct BuildsView: View {
  @ObservedObject var viewModel: BuildsViewModel

  var body: some View {
    NavigationStack {
      List(viewModel.builds) { build in
        BuildRow(build: build)
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
    .alert("Refresh failed", isPresented: $viewModel.isShowingError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage ?? "Unknown error")
    }
  }
}

private struct BuildRow: View {
  let build: Build

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
