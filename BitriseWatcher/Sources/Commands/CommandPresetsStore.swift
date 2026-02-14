import Foundation
import SwiftUI

struct CommandPreset: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  var name: String
  var template: String

  init(id: UUID = UUID(), name: String, template: String) {
    self.id = id
    self.name = name
    self.template = template
  }
}

@MainActor
final class CommandPresetsStore: ObservableObject {
  @Published var presets: [CommandPreset] = []
  @Published var selectedPresetID: UUID?
  @Published var workingDirectory: String

  private let presetsKey = "bitriseWatcher.commandPresets.v1"
  private let selectedPresetKey = "bitriseWatcher.commandPresets.selectedID.v1"
  private let workingDirectoryKey = "bitriseWatcher.commandPresets.workingDirectory.v1"

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    self.workingDirectory = defaults.string(forKey: workingDirectoryKey) ?? home

    loadOrBootstrap()
  }

  var selectedPreset: CommandPreset? {
    guard let selectedPresetID else { return nil }
    return presets.first(where: { $0.id == selectedPresetID })
  }

  func selectPreset(id: UUID?) {
    selectedPresetID = id
    defaults.set(id?.uuidString, forKey: selectedPresetKey)
  }

  func upsertPreset(_ preset: CommandPreset) {
    if let index = presets.firstIndex(where: { $0.id == preset.id }) {
      presets[index] = preset
    } else {
      presets.append(preset)
    }
    savePresets()
  }

  func deletePreset(id: UUID) {
    presets.removeAll(where: { $0.id == id })
    if selectedPresetID == id {
      selectPreset(id: presets.first?.id)
    }
    savePresets()
  }

  func setWorkingDirectory(_ path: String) {
    workingDirectory = path
    defaults.set(path, forKey: workingDirectoryKey)
  }

  private func loadOrBootstrap() {
    if let data = defaults.data(forKey: presetsKey),
       let decoded = try? JSONDecoder().decode([CommandPreset].self, from: data),
       !decoded.isEmpty
    {
      presets = decoded
    } else {
      presets = Self.defaultPresets
      savePresets()
    }

    if let raw = defaults.string(forKey: selectedPresetKey),
       let id = UUID(uuidString: raw),
       presets.contains(where: { $0.id == id })
    {
      selectedPresetID = id
    } else {
      selectedPresetID = presets.first?.id
      defaults.set(selectedPresetID?.uuidString, forKey: selectedPresetKey)
    }
  }

  private func savePresets() {
    guard let data = try? JSONEncoder().encode(presets) else { return }
    defaults.set(data, forKey: presetsKey)
  }

  private static var defaultPresets: [CommandPreset] {
    [
      CommandPreset(
        name: "Resign & Deploy",
        template: #"echo "Resign & Deploy build={{buildSlug}} artifact={{artifactTitle}} version={{appVersion}} buildNumber={{appBuildNumber}}""#
      ),
      CommandPreset(
        name: "Custom",
        template: #"echo "Selected build={{buildNumber}} workflow={{workflowID}} branch={{branch}} (slug={{buildSlug}})""#
      ),
    ]
  }
}
