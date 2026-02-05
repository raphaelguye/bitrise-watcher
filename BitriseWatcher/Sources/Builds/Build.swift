import Foundation

enum BuildStatus: String, Sendable, CaseIterable {
  case success
  case failed
  case running
  case aborted
}

struct Build: Identifiable, Sendable, Hashable {
  let id: String
  let buildNumber: Int
  let workflowID: String
  let branch: String
  let status: BuildStatus
  let startedAt: Date
}

