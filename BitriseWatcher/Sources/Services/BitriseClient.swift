import Foundation

struct BitriseClientConfiguration: Sendable {
  let apiToken: String
  let baseURL: URL
  let buildsLimit: Int

  init(apiToken: String, baseURL: URL = URL(string: "https://api.bitrise.io/v0.1")!, buildsLimit: Int = 50) {
    self.apiToken = apiToken
    self.baseURL = baseURL
    self.buildsLimit = buildsLimit
  }
}

enum BitriseClientError: Error, LocalizedError, Sendable {
  case missingAPIToken
  case invalidURL
  case httpError(statusCode: Int, message: String?)
  case decodingError

  var errorDescription: String? {
    switch self {
    case .missingAPIToken:
      "Missing Bitrise API token. Set BITRISE_API_TOKEN in the scheme environment variables."
    case .invalidURL:
      "Invalid Bitrise API URL."
    case let .httpError(statusCode, message):
      if let message, !message.isEmpty {
        "Bitrise API error (\(statusCode)): \(message)"
      } else {
        "Bitrise API error (\(statusCode))."
      }
    case .decodingError:
      "Failed to decode Bitrise API response."
    }
  }
}

actor BitriseClient: BitriseBuildsProviding {
  private let configuration: BitriseClientConfiguration
  private let urlSession: URLSession

  init(configuration: BitriseClientConfiguration, urlSession: URLSession = .shared) {
    self.configuration = configuration
    self.urlSession = urlSession
  }

  func fetchBuilds(appSlug: String, workflowID: String) async throws -> [Build] {
    guard !configuration.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw BitriseClientError.missingAPIToken
    }

    var components = URLComponents(
      url: configuration.baseURL.appendingPathComponent("apps/\(appSlug)/builds"),
      resolvingAgainstBaseURL: false
    )

    var queryItems: [URLQueryItem] = [
      URLQueryItem(name: "limit", value: String(configuration.buildsLimit)),
    ]

    if !workflowID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      queryItems.append(URLQueryItem(name: "workflow", value: workflowID))
    }

    components?.queryItems = queryItems

    guard let url = components?.url else { throw BitriseClientError.invalidURL }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(configuration.apiToken, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw BitriseClientError.httpError(statusCode: -1, message: "No HTTP response.")
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let message = (try? JSONDecoder().decode(BitriseAPIMessageResponse.self, from: data))?.message
      throw BitriseClientError.httpError(statusCode: httpResponse.statusCode, message: message)
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
      let response = try decoder.decode(BitriseBuildsResponse.self, from: data)
      let builds = response.data.map { $0.toBuild() }.sorted { $0.buildNumber > $1.buildNumber }
      return try await attachArtifactMetadata(appSlug: appSlug, builds: builds)
    } catch {
      throw BitriseClientError.decodingError
    }
  }
}

private struct BitriseAPIMessageResponse: Decodable {
  let message: String?
}

private struct BitriseBuildsResponse: Decodable {
  let data: [BitriseBuildDTO]
}

private struct BitriseBuildDTO: Decodable {
  let slug: String?
  let buildNumber: Int?
  let branch: LossyString?
  let triggeredWorkflow: String?
  let commitMessage: String?
  let status: Int?
  let startedOnWorkerAt: Date?
  let triggeredAt: Date?

  enum CodingKeys: String, CodingKey {
    case slug
    case buildNumber = "build_number"
    case branch
    case triggeredWorkflow = "triggered_workflow"
    case commitMessage = "commit_message"
    case status
    case startedOnWorkerAt = "started_on_worker_at"
    case triggeredAt = "triggered_at"
  }

  func toBuild() -> Build {
    let id = slug ?? UUID().uuidString
    let number = buildNumber ?? 0
    let wf = triggeredWorkflow ?? ""
    let branchValue = branch?.value ?? ""

    return Build(
      id: id,
      buildNumber: number,
      workflowID: wf,
      branch: branchValue,
      title: commitMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
      status: BuildStatus(bitriseStatusCode: status),
      startedAt: startedOnWorkerAt ?? triggeredAt ?? .now,
      artifact: nil
    )
  }
}

private struct LossyString: Decodable, Sendable, Hashable {
  let value: String?

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let string = try? container.decode(String.self) {
      value = string
      return
    }

    if let object = try? container.decode(LossyStringObject.self) {
      value = object.string
      return
    }

    value = nil
  }
}

private struct LossyStringObject: Decodable, Sendable, Hashable {
  let string: String?
}

private extension BuildStatus {
  init(bitriseStatusCode: Int?) {
    switch bitriseStatusCode {
    case 1:
      self = .success
    case 2:
      self = .failed
    case 3:
      self = .aborted
    case 4:
      self = .running
    case 0:
      fallthrough
    default:
      self = .running
    }
  }
}

private extension BitriseClient {
  func attachArtifactMetadata(appSlug: String, builds: [Build]) async throws -> [Build] {
    let maxBuildsToEnrich = min(builds.count, 20)
    let head = Array(builds.prefix(maxBuildsToEnrich))
    let tail = Array(builds.dropFirst(maxBuildsToEnrich))

    var enriched = head

    try await withThrowingTaskGroup(of: (Int, BuildArtifact?).self) { group in
      for (index, build) in head.enumerated() {
        group.addTask { [urlSession, configuration] in
          let artifact = try await BitriseClient.fetchInstallableArtifact(
            urlSession: urlSession,
            baseURL: configuration.baseURL,
            apiToken: configuration.apiToken,
            appSlug: appSlug,
            buildSlug: build.id
          )
          return (index, artifact)
        }
      }

      for try await (index, artifact) in group {
        enriched[index] = Build(
          id: enriched[index].id,
          buildNumber: enriched[index].buildNumber,
          workflowID: enriched[index].workflowID,
          branch: enriched[index].branch,
          title: enriched[index].title,
          status: enriched[index].status,
          startedAt: enriched[index].startedAt,
          artifact: artifact
        )
      }
    }

    return enriched + tail
  }

  static func fetchInstallableArtifact(
    urlSession: URLSession,
    baseURL: URL,
    apiToken: String,
    appSlug: String,
    buildSlug: String
  ) async throws -> BuildArtifact? {
    let url = baseURL.appendingPathComponent("apps/\(appSlug)/builds/\(buildSlug)/artifacts")

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(apiToken, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { return nil }
    guard (200..<300).contains(httpResponse.statusCode) else { return nil }

    let decoder = JSONDecoder()
    guard let artifactsResponse = try? decoder.decode(BitriseArtifactsResponse.self, from: data) else { return nil }

    let preferredTypes: Set<String> = ["ios-ipa", "android-apk", "android-aab"]
    let artifact = artifactsResponse.data.first(where: { preferredTypes.contains($0.artifactType ?? "") }) ?? artifactsResponse.data.first

    guard let artifact, let title = artifact.title, let type = artifact.artifactType else { return nil }

    var extracted = extractVersionAndBuildNumber(from: artifact.artifactMeta)
    var version = extracted.0
    var buildNumber = extracted.1

    if version == nil || buildNumber == nil {
      let parsed = parseVersionAndBuildNumber(from: title)
      version = version ?? parsed.0
      buildNumber = buildNumber ?? parsed.1
    }

    if (buildNumber == nil || buildNumber?.isEmpty == true),
       let artifactSlug = artifact.slug
    {
      if let details = try await fetchArtifactDetails(
        urlSession: urlSession,
        baseURL: baseURL,
        apiToken: apiToken,
        appSlug: appSlug,
        buildSlug: buildSlug,
        artifactSlug: artifactSlug
      ) {
        extracted = extractVersionAndBuildNumber(from: details.artifactMeta)
        version = version ?? extracted.0
        buildNumber = buildNumber ?? extracted.1

#if DEBUG
        if (buildNumber == nil || buildNumber?.isEmpty == true), let meta = details.artifactMeta {
          print("[BitriseWatcher] Missing app build number. artifact_type=\(type) title=\"\(title)\" meta=\(meta.debugSummary)")
        }
#endif
      }
    }

    return BuildArtifact(
      title: title,
      type: type,
      appVersion: version,
      appBuildNumber: buildNumber
    )
  }

  static func fetchArtifactDetails(
    urlSession: URLSession,
    baseURL: URL,
    apiToken: String,
    appSlug: String,
    buildSlug: String,
    artifactSlug: String
  ) async throws -> BitriseArtifactDTO? {
    let url = baseURL.appendingPathComponent("apps/\(appSlug)/builds/\(buildSlug)/artifacts/\(artifactSlug)")

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(apiToken, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await urlSession.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else { return nil }
    guard (200..<300).contains(httpResponse.statusCode) else { return nil }

    let decoder = JSONDecoder()
    if let wrapped = try? decoder.decode(BitriseArtifactDetailsResponse.self, from: data) {
      return wrapped.data
    }
    return try? decoder.decode(BitriseArtifactDTO.self, from: data)
  }

  static func parseVersionAndBuildNumber(from text: String) -> (String?, String?) {
    let versionRegex = try? NSRegularExpression(pattern: #"(?:^|[^0-9])v?(\d+(?:\.\d+){1,3})"#)
    let buildRegex = try? NSRegularExpression(pattern: #"(?:\((\d{1,10})\)|\bbuild[ _-]?(\d{1,10})\b)"#, options: [.caseInsensitive])

    var version: String?
    if let match = versionRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
       let range = Range(match.range(at: 1), in: text)
    {
      version = String(text[range])
    }

    var buildNumber: String?
    if let match = buildRegex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
       (match.numberOfRanges >= 2)
    {
      if let range = Range(match.range(at: 1), in: text) {
        buildNumber = String(text[range])
      } else if match.numberOfRanges >= 3, let range = Range(match.range(at: 2), in: text) {
        buildNumber = String(text[range])
      }
    }

    return (version, buildNumber)
  }
}

private struct BitriseArtifactsResponse: Decodable {
  let data: [BitriseArtifactDTO]
}

private struct BitriseArtifactDTO: Decodable {
  let slug: String?
  let title: String?
  let artifactType: String?
  let artifactMeta: JSONValue?

  enum CodingKeys: String, CodingKey {
    case slug
    case title
    case artifactType = "artifact_type"
    case artifactMeta = "artifact_meta"
  }
}

private struct BitriseArtifactDetailsResponse: Decodable {
  let data: BitriseArtifactDTO
}

private enum JSONValue: Decodable, Sendable, Hashable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let obj = try? container.decode([String: JSONValue].self) {
      self = .object(obj)
    } else if let arr = try? container.decode([JSONValue].self) {
      self = .array(arr)
    } else if let str = try? container.decode(String.self) {
      self = .string(str)
    } else if let num = try? container.decode(Double.self) {
      self = .number(num)
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else {
      self = .null
    }
  }

  var stringValue: String? {
    switch self {
    case let .string(value):
      return value
    case let .number(value):
      if value.rounded(.towardZero) == value { return String(Int(value)) }
      return String(value)
    case let .bool(value):
      return value ? "true" : "false"
    case .object, .array, .null:
      return nil
    }
  }

  var debugSummary: String {
    switch self {
    case let .object(obj):
      let keys = obj.keys.sorted()
      return "object(keys: \(keys.joined(separator: ", ")))"
    case let .array(arr):
      return "array(count: \(arr.count))"
    case let .string(value):
      return "string(\(value.prefix(80)))"
    case let .number(value):
      return "number(\(value))"
    case let .bool(value):
      return "bool(\(value))"
    case .null:
      return "null"
    }
  }
}

private extension JSONValue {
  func firstStringValue(forKeys keys: [String]) -> String? {
    let normalizedKeys = Set(keys.map { $0.lowercased() })

    switch self {
    case let .object(obj):
      for (key, value) in obj {
        if normalizedKeys.contains(key.lowercased()) {
          if let str = value.stringValue {
            return str
          }
          if let nested = value.firstStringValue(forKeys: ["value"]) {
            return nested
          }
        }
      }
      for (_, value) in obj {
        if let str = value.firstStringValue(forKeys: keys) {
          return str
        }
      }
      return nil
    case let .array(arr):
      for value in arr {
        if let str = value.firstStringValue(forKeys: keys) {
          return str
        }
      }
      return nil
    case .string, .number, .bool, .null:
      return nil
    }
  }

  func firstScalarString(where predicate: (String, String) -> Bool) -> String? {
    switch self {
    case let .object(obj):
      for (key, value) in obj {
        if let scalar = value.stringValue, predicate(key, scalar) {
          return scalar
        }
        if value.stringValue == nil, let nested = value.firstStringValue(forKeys: ["value"]), predicate(key, nested) {
          return nested
        }
      }
      for (_, value) in obj {
        if let found = value.firstScalarString(where: predicate) {
          return found
        }
      }
      return nil
    case let .array(arr):
      for value in arr {
        if let found = value.firstScalarString(where: predicate) {
          return found
        }
      }
      return nil
    case .string, .number, .bool, .null:
      return nil
    }
  }
}

private extension BitriseClient {
  static func extractVersionAndBuildNumber(from artifactMeta: JSONValue?) -> (String?, String?) {
    guard let artifactMeta else { return (nil, nil) }

    let versionKeys = [
      "app_version",
      "version",
      "bundle_version_short",
      "bundle_short_version",
      "cfbundleshortversionstring",
      "version_name",
      "marketing_version",
    ]

    let buildNumberKeys = [
      "app_build_number",
      "build_number",
      "build",
      "bundle_version",
      "cfbundleversion",
      "version_code",
    ]

    let version = artifactMeta.firstStringValue(forKeys: versionKeys)
    let buildNumber = artifactMeta.firstStringValue(forKeys: buildNumberKeys)

    let fallbackVersion = version ?? artifactMeta.firstScalarString { key, value in
      let k = key.lowercased()
      return k.contains("version") && value.contains(".")
    }

    let fallbackBuildNumber = buildNumber ?? artifactMeta.firstScalarString { key, value in
      let k = key.lowercased()
      let digitsOnly = !value.isEmpty && value.allSatisfy(\.isNumber)
      return digitsOnly && (k.contains("build") || k.contains("bundle") || k.contains("version_code"))
    }

    return (fallbackVersion, fallbackBuildNumber)
  }
}
