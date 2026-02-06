import Foundation

enum BuildStatus: String, Sendable, CaseIterable {
  case success
  case failed
  case running
  case aborted
}

struct BuildArtifact: Sendable, Hashable {
  let title: String
  let type: String
  let appVersion: String?
  let appBuildNumber: String?

  var versionLabel: String? {
    guard let appVersion, !appVersion.isEmpty else { return nil }
    if let appBuildNumber, !appBuildNumber.isEmpty {
      return "v\(appVersion) (\(appBuildNumber))"
    }
    return "v\(appVersion)"
  }
}

struct Build: Identifiable, Sendable, Hashable {
  let id: String
  let buildNumber: Int
  let workflowID: String
  let branch: String
  let title: String?
  let status: BuildStatus
  let startedAt: Date
  let artifact: BuildArtifact?
}
