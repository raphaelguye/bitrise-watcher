import Foundation

enum BuildsFilter: String, Sendable, CaseIterable, Identifiable {
  case successOnly
  case all

  var id: String { rawValue }

  var title: String {
    switch self {
    case .successOnly: "Success"
    case .all: "All"
    }
  }
}

@MainActor
final class BuildsViewModel: ObservableObject {
  @Published private(set) var allBuilds: [Build] = []
  @Published private(set) var isLoading = false
  @Published var isShowingError = false
  @Published private(set) var errorMessage: String?
  @Published var filter: BuildsFilter = .successOnly

  private let appSlug: String
  private let workflowID: String
  private let buildsProvider: BitriseBuildsProviding

  init(appSlug: String, workflowID: String, buildsProvider: BitriseBuildsProviding) {
    self.appSlug = appSlug
    self.workflowID = workflowID
    self.buildsProvider = buildsProvider
  }

  var builds: [Build] {
    switch filter {
    case .successOnly:
      allBuilds.filter { $0.status == .success }
    case .all:
      allBuilds
    }
  }

  func refresh() async {
    guard !isLoading else { return }

    isLoading = true
    defer { isLoading = false }

    do {
      allBuilds = try await buildsProvider.fetchBuilds(appSlug: appSlug, workflowID: workflowID)
    } catch {
      errorMessage = String(describing: error)
      isShowingError = true
    }
  }
}
