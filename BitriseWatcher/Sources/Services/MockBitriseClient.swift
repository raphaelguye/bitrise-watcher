import Foundation

actor MockBitriseClient: BitriseBuildsProviding {
  private var refreshCount = 0

  func fetchBuilds(appSlug: String, workflowID: String) async throws -> [Build] {
    refreshCount += 1

    try await Task.sleep(for: .milliseconds(450))

    let now = Date()
    let baseNumber = 1200 + refreshCount * 3

    let statuses: [BuildStatus] = [
      .running,
      refreshCount.isMultiple(of: 2) ? .failed : .success,
      .success,
      .aborted,
      .success,
    ]

    return statuses.enumerated().map { offset, status in
      Build(
        id: "\(appSlug)-\(workflowID)-\(baseNumber - offset)",
        buildNumber: baseNumber - offset,
        workflowID: workflowID,
        branch: offset.isMultiple(of: 2) ? "main" : "feature/mock-\(refreshCount)",
        status: status,
        startedAt: now.addingTimeInterval(TimeInterval(-offset * 60 * 7))
      )
    }
  }
}

