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
    let trimmedVersion = appVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedBuild = appBuildNumber?.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let trimmedVersion, !trimmedVersion.isEmpty else { return nil }
    if let trimmedBuild, !trimmedBuild.isEmpty {
      return "v\(trimmedVersion) (\(trimmedBuild))"
    }
    return "v\(trimmedVersion)"
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
