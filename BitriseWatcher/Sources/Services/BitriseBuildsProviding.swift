import Foundation

protocol BitriseBuildsProviding: Sendable {
  func fetchBuilds(appSlug: String, workflowID: String) async throws -> [Build]
}

