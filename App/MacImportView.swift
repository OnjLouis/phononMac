import SwiftUI
import UniformTypeIdentifiers

struct MacImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries = [MacVoiceStore.Entry]()
    @State private var selected: UUID?
    @State private var picking = false
    @State private var editing = false
    @State private var confirmingRemoval = false
    @State private var source: URL?
    @State private var name = ""
    @State private var locale = "en-US"
    @State private var error: String?
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            List(selection: $selected) {
                ForEach(entries, id: \.key) { entry in
                    Text("\(entry.name), \(languageName(entry.locale))").tag(entry.key)
                }
            }.accessibilityLabel("Imported voices")
            HStack {
                Button("Add Voice", systemImage: "plus") { picking = true }
                Button("Remove Voice", systemImage: "minus", role: .destructive) { confirmingRemoval = true }
                    .disabled(selected == nil)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding().frame(minWidth: 470, minHeight: 240)
        .onAppear(perform: load)
        .fileImporter(isPresented: $picking, allowedContentTypes: [UTType(filenameExtension: "safetensors") ?? .data]) { result in
            do {
                let file = try result.get()
                source = file
                name = String(file.deletingPathExtension().lastPathComponent.prefix(80))
                editing = true
            } catch { self.error = error.localizedDescription }
        }
        .sheet(isPresented: $editing) {
            Form {
                TextField("Voice name", text: $name)
                Picker("Spoken language", selection: $locale) {
                    ForEach(MacVoiceStore.locales, id: \.self) { Text(languageName($0)).tag($0) }
                }
                HStack {
                    Button("Cancel", role: .cancel) { editing = false }.keyboardShortcut(.cancelAction)
                    Button("Import") { add() }.keyboardShortcut(.defaultAction)
                }
            }.padding().frame(minWidth: 340)
        }
        .confirmationDialog("Remove this imported voice?", isPresented: $confirmingRemoval) {
            Button("Remove Voice", role: .destructive) { remove() }
        }
        .alert("Phonon voices", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func load() {
        entries = (try? VoiceCatalog.importStore().entries()) ?? []
        if !entries.contains(where: { $0.key == selected }) { selected = entries.first?.key }
    }

    private func add() {
        guard let source else { return }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        do {
            let entry = try VoiceCatalog.importStore().add(source, name: name, locale: locale, projection: AppModel.projection)
            editing = false
            load()
            selected = entry.key
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
