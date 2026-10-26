// SPDX-License-Identifier: GPL-3.0-or-later
import DriftLoomPlayback
import SwiftUI
import UniformTypeIdentifiers

private struct LibraryBackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct LibraryTransferView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var playlists: PlaylistStore
    @EnvironmentObject private var groups: SubscriptionGroups
    @State private var backup = LibraryBackupFile()
    @State private var exporting = false
    @State private var importing = false
    @State private var pending: LibraryImportPlan?
    @State private var message: String?
    var body: some View {
        List {
            Section("Library backup") {
                Text("Back up saved videos, subscriptions, watch history, local playlists, bookmarked playlists, and subscription groups. Downloaded media, playback queues, and app settings are excluded.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Export library backup") {
                    do { backup = LibraryBackupFile(data: try LibraryTransfer.export(library: library, playlists: playlists, groups: groups)); exporting = true }
                    catch { message = error.localizedDescription }
                }.disabled(!library.isWritable || !playlists.isWritable || !groups.isWritable)
            }
            Section("Import and merge") {
                Text("Choose a DriftLoom library backup or a NewPipe subscriptions JSON export or ZIP database backup. Review the import before merging. Existing items and privacy settings are kept; a recovery copy is saved on this device.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Choose import file") { importing = true }.disabled(!library.isWritable || !playlists.isWritable || !groups.isWritable)
                Text("NewPipe ZIP migration supports YouTube subscriptions, history, local playlists, and subscription groups. Android preferences and downloaded media are excluded; unsupported entries are reported in the preview.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let pending {
                Section("Import preview") {
                    Text(pending.summary)
                    ForEach(pending.warnings, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    Button("Merge imported library") {
                        do {
                            try LibraryTransfer.apply(pending, library: library, playlists: playlists, groups: groups)
                            self.pending = nil; message = "Import complete. Existing items were kept and a recovery copy was saved."
                        } catch { message = "Import failed: " + error.localizedDescription }
                    }
                    Button("Cancel import", role: .cancel) { self.pending = nil }
                }
            }
        }
        .navigationTitle("Backup and import").navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "DriftLoom-library") { result in
            if case let .failure(error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .zip], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 50_000_000 else { throw BrowseError.unavailable("This import exceeds the 50 MB ZIP limit (20 MB for JSON).") }
                pending = try LibraryTransfer.preview(Data(contentsOf: url))
            } catch { message = "Couldn't read the import: " + error.localizedDescription }
        }
        .alert("Library transfer", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
}
