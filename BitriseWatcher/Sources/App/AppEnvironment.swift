import Foundation

enum AppEnvironment {
  static let useMocksKey = "BITRISE_WATCHER_USE_MOCKS"
  static let apiTokenKey = "BITRISE_API_TOKEN"
  static let appSlugKey = "BITRISE_APP_SLUG"
  static let workflowIDKey = "BITRISE_WORKFLOW_ID"

  @MainActor
  static func makeBuildsViewModel() -> BuildsViewModel {
    let env = ProcessInfo.processInfo.environment

    let useMocks = env[useMocksKey].map(isTruthy(_:)) ?? false
    let appSlug = env[appSlugKey] ?? "MOCK_APP_SLUG"
    let workflowID = env[workflowIDKey] ?? "MOCK_WORKFLOW_ID"

    let provider: BitriseBuildsProviding
    if useMocks {
      provider = MockBitriseClient()
    } else if let apiToken = env[apiTokenKey], !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      provider = BitriseClient(configuration: BitriseClientConfiguration(apiToken: apiToken))
    } else {
      provider = ConfigurationErrorProvider(error: BitriseClientError.missingAPIToken)
    }

    return BuildsViewModel(appSlug: appSlug, workflowID: workflowID, buildsProvider: provider)
  }

  private static func isTruthy(_ value: String) -> Bool {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "y", "on":
      true
    default:
      false
    }
  }
}

private struct ConfigurationErrorProvider: BitriseBuildsProviding {
  let error: Error

  func fetchBuilds(appSlug: String, workflowID: String) async throws -> [Build] {
    throw error
  }
}
