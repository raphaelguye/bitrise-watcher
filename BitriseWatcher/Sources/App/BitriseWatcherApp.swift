import SwiftUI

@main
struct BitriseWatcherApp: App {
  @StateObject private var buildsViewModel = BuildsViewModel(
    appSlug: "MOCK_APP_SLUG",
    workflowID: "MOCK_WORKFLOW_ID",
    buildsProvider: MockBitriseClient()
  )

  var body: some Scene {
    WindowGroup {
      BuildsView(viewModel: buildsViewModel)
        .frame(minWidth: 520, minHeight: 420)
    }
  }
}
