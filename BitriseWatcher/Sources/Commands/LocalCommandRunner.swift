import Foundation

@MainActor
final class LocalCommandRunner: ObservableObject {
  @Published private(set) var isRunning = false
  @Published private(set) var output = ""
  @Published private(set) var exitCode: Int32?
  @Published private(set) var launchedCommand: String?

  private var process: Process?
  private var pipe: Pipe?

  func run(command: String, workingDirectory: String?, environment: [String: String]) {
    guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    guard !isRunning else { return }

    let normalizedCommand = normalizeCommandDashes(command)

    output = ""
    exitCode = nil
    launchedCommand = normalizedCommand

    let process = Process()
    let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    process.executableURL = URL(fileURLWithPath: shellPath)
    let preparedCommand = buildShellCommand(command: normalizedCommand, workingDirectory: workingDirectory)
    process.arguments = ["-lic", preparedCommand.command]
    if let workingDirectoryURL = preparedCommand.workingDirectoryURL {
      process.currentDirectoryURL = workingDirectoryURL
    }

    var env: [String: String] = [:]
    for (key, value) in ProcessInfo.processInfo.environment {
      env[key] = sanitizeEnvironmentValue(value)
    }
    for (k, v) in environment {
      env[k] = sanitizeEnvironmentValue(v)
    }
    process.environment = env

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    self.process = process
    self.pipe = pipe
    isRunning = true

    let handle = pipe.fileHandleForReading
    handle.readabilityHandler = { [weak self] fileHandle in
      let data = fileHandle.availableData
      guard !data.isEmpty else { return }
      Task { @MainActor in
        self?.appendOutput(data)
      }
    }

    process.terminationHandler = { [weak self] process in
      Task { @MainActor in
        handle.readabilityHandler = nil
        self?.appendOutput(Data()) // flush no-op
        self?.exitCode = process.terminationStatus
        self?.isRunning = false
        self?.process = nil
        self?.pipe = nil
      }
    }

    do {
      if normalizedCommand != command {
        output += "Note: converted smart dashes to '-' before execution.\n"
      }
      try process.run()
    } catch {
      handle.readabilityHandler = nil
      isRunning = false
      self.process = nil
      self.pipe = nil
      output += "Failed to start process: \(String(describing: error))\n"
    }
  }

  func cancel() {
    process?.terminate()
  }

  func clearOutput() {
    output = ""
    exitCode = nil
  }

  private func appendOutput(_ data: Data) {
    guard !data.isEmpty else { return }
    if let chunk = String(data: data, encoding: .utf8) {
      output += chunk
    } else {
      output += "<non-utf8 \(data.count) bytes>\n"
    }
  }

  private func buildShellCommand(command: String, workingDirectory: String?) -> (command: String, workingDirectoryURL: URL?) {
    guard let workingDirectory, !workingDirectory.isEmpty else { return (command, nil) }

    let expandedPath = NSString(string: workingDirectory).expandingTildeInPath
    let url = URL(fileURLWithPath: expandedPath, isDirectory: true)

    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
    guard exists, isDirectory.boolValue else {
      output += "Warning: working directory does not exist: \(expandedPath)\n"
      return (command, nil)
    }

    // Keep process cwd in sync and enforce cwd again after shell profile/init files are loaded.
    let quotedPath = shellSingleQuote(url.path)
    return ("cd -- \(quotedPath) && \(command)", url)
  }

  private func shellSingleQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
  }

  private func sanitizeEnvironmentValue(_ value: String) -> String {
    var sanitized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sanitized.isEmpty else { return value }

    // Some launch contexts (xcconfig/scheme vars) provide values wrapped in quotes.
    if (sanitized.hasPrefix("\"") && sanitized.hasSuffix("\"")) || (sanitized.hasPrefix("'") && sanitized.hasSuffix("'")) {
      sanitized.removeFirst()
      sanitized.removeLast()
      return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return value
  }

  private func normalizeCommandDashes(_ command: String) -> String {
    command
      .replacingOccurrences(of: "\u{2010}", with: "-") // hyphen
      .replacingOccurrences(of: "\u{2011}", with: "-") // non-breaking hyphen
      .replacingOccurrences(of: "\u{2012}", with: "-") // figure dash
      .replacingOccurrences(of: "\u{2013}", with: "-") // en dash
      .replacingOccurrences(of: "\u{2014}", with: "-") // em dash
      .replacingOccurrences(of: "\u{2015}", with: "-") // horizontal bar
      .replacingOccurrences(of: "\u{2212}", with: "-") // minus sign
  }
}
