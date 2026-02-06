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
    let appSlug = sanitized(env[appSlugKey]) ?? "MOCK_APP_SLUG"
    let workflowID = sanitized(env[workflowIDKey]) ?? "MOCK_WORKFLOW_ID"

    let provider: BitriseBuildsProviding
    if useMocks {
      provider = MockBitriseClient()
    } else if let apiToken = sanitized(env[apiTokenKey]) {
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

  private static func sanitized(_ value: String?) -> String? {
    guard var value else { return nil }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    // Some setups inject quoted values (e.g. from xcconfig or scripts). Strip one layer.
    if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
      value.removeFirst()
      value.removeLast()
      value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return value.isEmpty ? nil : value
  }
}

private struct ConfigurationErrorProvider: BitriseBuildsProviding {
  let error: Error

  func fetchBuilds(appSlug: String, workflowID: String) async throws -> [Build] {
    throw error
  }
}
