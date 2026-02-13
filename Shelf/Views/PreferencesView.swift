import SwiftUI

/// Preferences/Settings window
struct PreferencesView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel

    var body: some View {
        Form {
            Section("Library") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Audiobooks Folder")
                            .font(.headline)
                        if let path = libraryVM.libraryFolderPath {
                            Text(path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No folder selected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Change...") {
                        libraryVM.pickFolder()
                    }
                }

                Button("Refresh Library Now") {
                    Task { await libraryVM.scanLibrary() }
                }
                .disabled(libraryVM.isScanning || libraryVM.libraryFolderPath == nil)

                if libraryVM.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                if let result = libraryVM.scanResult {
                    Text(result.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Backup") {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Export Progress")
                            .font(.headline)
                        Text("Save your playback positions and bookmarks to a JSON file.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Export...") {
                        libraryVM.exportProgress()
                    }
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Import Progress")
                            .font(.headline)
                        Text("Restore playback positions and bookmarks from a backup file.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Import...") {
                        libraryVM.importProgress()
                    }
                }
            }

            Section("About") {
                Text("Shelf v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("A native audiobook player for macOS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 380)
    }
}
