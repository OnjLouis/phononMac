import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries = [MacVoiceStore.Entry]()
    @State private var selected: UUID?
    @State private var picking = false
    @State private var editing = false
    @State private var confirmingRemoval = false
    @State private var source: Data?
    @State private var existing: MacVoiceStore.Entry?
    @State private var name = ""
    @State private var locale = ""
    @State private var error: String?
    @StateObject private var preview = ImportedVoicePreview()
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            List(selection: $selected) {
                ForEach(entries, id: \.key) { entry in
                    Text("\(entry.name), \(languageName(entry.locale))").tag(entry.key)
                }
            }.accessibilityLabel("Imported voices")
                .help("Select a voice to change its language or remove it.")
            HStack {
                Button("Add Voice", systemImage: "plus", action: pickVoice).disabled(picking)
                    .help("Choose a compatible Phonon voice file in safetensors format.")
                Button("Change Language") { changeLanguage() }.disabled(selected == nil)
                    .help("Moves the selected voice to another language without reimporting it.")
                Button("Remove Voice", systemImage: "minus", role: .destructive) { confirmingRemoval = true }
                    .disabled(selected == nil)
                    .help("Asks before removing the voice from Phonon and VoiceOver.")
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding().frame(minWidth: 560, minHeight: 240)
        .onAppear(perform: load)
        .sheet(isPresented: $editing, onDismiss: {
            preview.stop()
            source = nil
            existing = nil
        }) {
            Form {
                if existing == nil {
                    TextField("Voice name", text: $name)
                        .help("This name appears in Phonon and in the VoiceOver voice list.")
                }
                Picker("Spoken language", selection: $locale) {
                    Text("Choose a language").tag("")
                    ForEach(MacVoiceStore.locales, id: \.self) { Text(languageName($0)).tag($0) }
                }
                .help("Sets which language lists this voice appears in.")
                HStack {
                    Button("Preview Voice") { playPreview() }.disabled(preview.playing)
                        .help("Reads a sample before you save. It uses English if no language is set.")
                    Button("Stop Preview") { preview.stop() }.disabled(!preview.playing)
                }
                if !preview.message.isEmpty { Text(preview.message) }
                HStack {
                    Button("Cancel", role: .cancel) { editing = false }.keyboardShortcut(.cancelAction)
                    Button(existing == nil ? "Import" : "Save") { save() }
                        .keyboardShortcut(.defaultAction).disabled(locale.isEmpty)
                        .help(existing == nil ? "Adds this voice to Phonon and VoiceOver."
                                              : "Saves the new language for this voice.")
                }
            }.padding().frame(minWidth: 360).onDisappear { preview.stop() }
        }
        .confirmationDialog("Remove this imported voice?", isPresented: $confirmingRemoval) {
            Button("Remove Voice", role: .destructive) { remove() }
        }
        .alert("Phonon voices", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func pickVoice() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Phonon voice"
        panel.allowedContentTypes = [UTType(filenameExtension: "safetensors") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        picking = true
        panel.begin { response in
            let selected = response == .OK
            let url = panel.url
            Task { @MainActor in
                defer { picking = false }
                guard selected else { return }
                guard let url else {
                    error = MacVoiceStore.Failure.unavailable.localizedDescription
                    return
                }
                do {
                    source = try await Task.detached(priority: .userInitiated) {
                        try MacVoiceStore.snapshotSelectedFile(url)
                    }.value
                    name = String(url.deletingPathExtension().lastPathComponent.prefix(80))
                    existing = nil
                    locale = ""
                    editing = true
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func load() {
        entries = (try? VoiceCatalog.importStore().entries()) ?? []
        if !entries.contains(where: { $0.key == selected }) { selected = entries.first?.key }
    }

    private func changeLanguage() {
        guard let entry = entries.first(where: { $0.key == selected }) else { return }
        do {
            source = try VoiceCatalog.importStore().data(for: entry)
            existing = entry
            locale = entry.locale
            editing = true
        } catch { self.error = error.localizedDescription }
    }

    private func playPreview() {
        guard let source else { return }
        do {
            let data = try MacVoiceStore.project(source, projection: AppModel.projection)
            preview.play(data, locale: locale.isEmpty ? "en-US" : locale)
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        guard let source else { return }
        do {
            let store = try VoiceCatalog.importStore()
            let key: UUID
            if let existing {
                try store.changeLanguage(existing, to: locale)
                key = existing.key
            } else {
                key = try store.add(source, name: name, locale: locale, projection: AppModel.projection).key
            }
            editing = false
            load()
            selected = key
            onChange()
        } catch {
            editing = false
            self.error = error.localizedDescription
        }
    }

    private func remove() {
        guard let entry = entries.first(where: { $0.key == selected }) else { return }
        do { try VoiceCatalog.importStore().remove(entry) }
        catch { self.error = error.localizedDescription }
        load()
        onChange()
    }
}
