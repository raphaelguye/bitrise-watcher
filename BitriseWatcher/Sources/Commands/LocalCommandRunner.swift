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
    process.arguments = ["-lic", normalizedCommand]

    if let workingDirectory, !workingDirectory.isEmpty {
      let url = URL(fileURLWithPath: workingDirectory, isDirectory: true)
      if FileManager.default.fileExists(atPath: url.path) {
        process.currentDirectoryURL = url
      }
    }

    var env = ProcessInfo.processInfo.environment
    for (k, v) in environment {
      env[k] = v
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
