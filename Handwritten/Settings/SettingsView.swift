import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var selectedTab: SettingTab = .general
    /// Row frames in window coordinates (top-left origin), recorded for UI tests.
    var rowFrames: [String: CGRect] = [:]
}

private struct RecordFrame: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content.background(GeometryReader { geo in
            Color.clear
                .onAppear { SettingsNavigation.shared.rowFrames[id] = geo.frame(in: .global) }
                .onChange(of: geo.frame(in: .global)) { _, f in SettingsNavigation.shared.rowFrames[id] = f }
        })
    }
}

extension View {
    func recordFrame(_ id: String) -> some View { modifier(RecordFrame(id: id)) }
}

struct SettingsView: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var nav = SettingsNavigation.shared
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var visibleTabs: [SettingTab] {
        SettingTab.allCases.filter { $0.minLevel <= store.uiLevel }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                topBar
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !query.isEmpty { searchResults } else { tabContent(nav.selectedTab) }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    /// Plain buttons instead of List selection, so every click switches tabs reliably.
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(visibleTabs) { tab in
                    SidebarButton(tab: tab, selected: nav.selectedTab == tab && query.isEmpty,
                                  changed: changedCount(tab)) {
                        nav.selectedTab = tab
                        query = ""
                        searching = false
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 34)
            .padding(.bottom, 10)
        }
        .frame(width: 200)
        .background(Color.primary.opacity(0.03))
    }

    private func changedCount(_ tab: SettingTab) -> Int {
        SettingsRegistry.all.filter { $0.tab == tab && store.isChanged($0.key) }.count
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $store.uiLevel) {
                ForEach(SettingLevel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .help("Simple shows the essentials, Advanced shows more, Custom shows every setting.")
            Text("\(SettingsRegistry.all.filter { $0.level <= store.uiLevel }.count) settings")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if searching {
                TextField("Search all settings", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .focused($searchFocused)
                    .onExitCommand { searching = false; query = "" }
            }
            Button {
                searching.toggle()
                if searching { searchFocused = true } else { query = "" }
            } label: { Image(systemName: searching ? "xmark.circle" : "magnifyingglass") }
            .keyboardShortcut("f", modifiers: .command)
            .help("Search settings (⌘F)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Search

    @ViewBuilder private var searchResults: some View {
        let results = SettingsRegistry.search(query, level: .custom)
        Text(results.isEmpty ? "No settings match “\(query)”" : "\(results.count) matching settings")
            .font(.headline).padding(.bottom, 8)
        ForEach(results) { def in
            SettingRowView(def: def, showTab: true)
            if def.level > store.uiLevel {
                Text("Shown in \(def.level.title) mode").font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
        }
    }

    // MARK: Tabs

    @ViewBuilder private func tabContent(_ tab: SettingTab) -> some View {
        Text(tab.title).font(.title2.bold()).padding(.bottom, 4)
        switch tab {
        case .presets: PresetsTab()
        case .wordLists: WordListsTab()
        default:
            if tab == .speed { HumannessCard().padding(.bottom, 8) }
            if tab == .typos { TyposSimpleHint() }
            sections(tab)
            if tab == .general { GeneralExtras() }
        }
    }

    @ViewBuilder private func sections(_ tab: SettingTab) -> some View {
        let defs = SettingsRegistry.defs(tab: tab, level: store.uiLevel)
            .filter { !(tab == .speed && $0.key == K.humanness) }
        let sectionNames = defs.reduce(into: [String]()) { acc, d in if !acc.contains(d.section) { acc.append(d.section) } }
        ForEach(sectionNames, id: \.self) { name in
            VStack(alignment: .leading, spacing: 2) {
                Text(name.uppercased()).font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 14)
                VStack(spacing: 0) {
                    ForEach(defs.filter { $0.section == name }) { def in
                        SettingRowView(def: def)
                        if def.id != defs.last(where: { $0.section == name })?.id { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            }
        }
        if defs.isEmpty {
            Text("Switch to Advanced or Custom to see more settings here.").foregroundStyle(.secondary).padding(.top, 10)
        }
    }
}

// MARK: - Preset row

/// A preset row you can click anywhere (or on its circle) to select.
private struct PresetRowShell<Content: View>: View {
    let id: String
    let selected: Bool
    let onSelect: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? ThemeStore.shared.accent : .secondary)
            }
            .buttonStyle(.plain)
            content()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? ThemeStore.shared.accent.opacity(0.14) : Color.primary.opacity(hover ? 0.08 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(selected ? ThemeStore.shared.accent.opacity(0.6) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hover = $0 }
        .recordFrame("preset.\(id)")
    }
}

// MARK: - Sidebar

private struct SidebarButton: View {
    let tab: SettingTab
    let selected: Bool
    let changed: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon).frame(width: 18)
                Text(tab.title).lineLimit(1).fixedSize()
                Spacer()
                if changed > 0 {
                    Text("\(changed)").font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.25) : Color.secondary.opacity(0.18)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(selected ? ThemeStore.shared.accent : Color.primary.opacity(hover ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .recordFrame("tab.\(tab.rawValue)")
    }
}

// MARK: - Tab extras

private struct HumannessCard: View {
    @ObservedObject private var store = SettingsStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let d = SettingsRegistry.def(K.humanness) { SettingRowView(def: d) }
            HStack {
                Text("\(store.manualOverrides.count) setting\(store.manualOverrides.count == 1 ? "" : "s") set by hand (not moved by the slider).")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Let the slider control everything") { store.clearManualOverrides() }
                    .controlSize(.small)
                    .disabled(store.manualOverrides.isEmpty)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(ThemeStore.shared.accent.opacity(0.08)))
    }
}

private struct TyposSimpleHint: View {
    @ObservedObject private var store = SettingsStore.shared
    var body: some View {
        if store.uiLevel == .simple {
            Text("Switch to Advanced to set a separate chance for each kind of typo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct GeneralExtras: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PERMISSIONS").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 14)
            HStack {
                Button("Check Permissions…") { AppDelegate.shared?.showOnboarding() }
                Button("Reset All Settings…") {
                    let a = NSAlert()
                    a.messageText = "Reset every setting to its default?"
                    a.informativeText = "Your presets and clipboard history are kept."
                    a.addButton(withTitle: "Reset")
                    a.addButton(withTitle: "Cancel")
                    if a.runModal() == .alertFirstButtonReturn { SettingsStore.shared.resetAll() }
                }
            }
        }
    }
}

private struct PresetsTab: View {
    @ObservedObject private var store = SettingsStore.shared
    @ObservedObject private var presets = PresetStore.shared
    @State private var newName = ""
    @State private var renaming: String?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("A preset saves your Speed, Rhythm, Typos and Corrections settings. Hotkeys, appearance and clipboard settings are not changed by presets.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("New preset name", text: $newName).textFieldStyle(.roundedBorder).frame(width: 240)
                Button("Save Current Settings as Preset") {
                    let n = newName.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    presets.saveCurrent(as: n)
                    newName = ""
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || presets.isReserved(newName))
            }
            if presets.isReserved(newName) {
                Text("That name is taken by a built-in preset or Custom. Pick another name.")
                    .font(.caption).foregroundStyle(.orange)
            }

            Text("NO PRESET").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 6)
            customRow

            Text("BUILT-IN").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 6)
            ForEach(BuiltInPresets.all) { p in row(p) }
            Text("YOUR PRESETS").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 6)
            if presets.userPresets.isEmpty {
                Text("None yet.").foregroundStyle(.secondary)
            }
            ForEach(presets.userPresets) { p in row(p) }

            Text("IMPORT / EXPORT").font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 10)
            HStack {
                Button("Export Settings & Presets…") { export() }
                Button("Import…") { importFile() }
            }
        }
    }

    private var onCustom: Bool { presets.preset(named: store.activePresetName) == nil }

    private var customRow: some View {
        PresetRowShell(id: Preset.customName, selected: onCustom, onSelect: { store.useCustom() }) {
            VStack(alignment: .leading) {
                Text("Custom (my settings)")
                Text("Use your own settings without any preset. Changing any Speed, Rhythm, Typos or Corrections setting switches to this automatically.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    @ViewBuilder private func row(_ p: Preset) -> some View {
        PresetRowShell(id: p.name, selected: store.activePresetName == p.name, onSelect: { store.apply(preset: p) }) {
            if renaming == p.name {
                TextField("", text: $renameText, onCommit: {
                    presets.rename(p.name, to: renameText)
                    renaming = nil
                }).textFieldStyle(.roundedBorder).frame(width: 200)
            } else {
                VStack(alignment: .leading) {
                    Text(p.name)
                    if !p.detail.isEmpty { Text(p.detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            if !p.builtIn {
                Button("Update") { presets.saveCurrent(as: p.name, detail: p.detail) }
                    .help("Overwrite this preset with your current settings")
                Button("Rename") { renaming = p.name; renameText = p.name }
                Button(role: .destructive) { presets.delete(p.name) } label: { Image(systemName: "trash") }
            }
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Handwritten Settings.json"
        guard panel.runModal() == .OK, let url = panel.url,
              let data = store.exportBundle(includePresets: true) else { return }
        try? data.write(to: url)
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        do { try store.importBundle(data) } catch {
            let a = NSAlert(error: error)
            a.runModal()
        }
    }
}

private struct WordListsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("These lists drive speed bursts and built-in typos. Edit them to match how you write.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(WordData.File.allCases) { f in
                HStack {
                    VStack(alignment: .leading) {
                        Text(f.title)
                        Text(f.help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Edit…") { AppDelegate.shared?.showDataEditor(f) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([WordData.userURL(f)]) }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            }
        }
    }
}
