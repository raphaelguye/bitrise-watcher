import SwiftUI

@main
@MainActor
struct BitriseWatcherApp: App {
  @StateObject private var buildsViewModel: BuildsViewModel

  init() {
    _buildsViewModel = StateObject(wrappedValue: AppEnvironment.makeBuildsViewModel())
  }

  var body: some Scene {
    WindowGroup {
      BuildsView(viewModel: buildsViewModel)
        .frame(minWidth: 520, minHeight: 420)
    }
  }
}
