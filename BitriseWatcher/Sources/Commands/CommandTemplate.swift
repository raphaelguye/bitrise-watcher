import Foundation

enum CommandTemplate {
  static func render(_ template: String, variables: [String: String]) -> String {
    var result = template
    for (key, value) in variables {
      result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
    }
    return result
  }
}

extension Build {
  func commandVariables(appSlug: String) -> [String: String] {
    var vars: [String: String] = [
      "appSlug": appSlug,
      "buildID": id,
      "buildNumber": String(buildNumber),
      "workflowID": workflowID,
      "branch": branch,
      "status": status.rawValue,
    ]

    if let artifact {
      vars["artifactTitle"] = artifact.title
      vars["artifactType"] = artifact.type
      if let version = artifact.appVersion { vars["appVersion"] = version }
      if let build = artifact.appBuildNumber { vars["appBuildNumber"] = build }
    }

    return vars
  }
}

enum CommandEnvironment {
  static func variables(appSlug: String, build: Build) -> [String: String] {
    var env: [String: String] = [
      "BITRISE_WATCHER_APP_SLUG": appSlug,
      "BITRISE_WATCHER_BUILD_ID": build.id,
      "BITRISE_WATCHER_BUILD_NUMBER": String(build.buildNumber),
      "BITRISE_WATCHER_WORKFLOW_ID": build.workflowID,
      "BITRISE_WATCHER_BRANCH": build.branch,
      "BITRISE_WATCHER_STATUS": build.status.rawValue,
    ]

    if let artifact = build.artifact {
      env["BITRISE_WATCHER_ARTIFACT_TITLE"] = artifact.title
      env["BITRISE_WATCHER_ARTIFACT_TYPE"] = artifact.type
      if let version = artifact.appVersion { env["BITRISE_WATCHER_APP_VERSION"] = version }
      if let build = artifact.appBuildNumber { env["BITRISE_WATCHER_APP_BUILD_NUMBER"] = build }
    }

    return env
  }
}

