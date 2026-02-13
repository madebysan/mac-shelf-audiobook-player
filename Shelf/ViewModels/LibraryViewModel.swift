import Foundation
import CoreData
import SwiftUI
import UniformTypeIdentifiers

/// Controls library state: scanning, filtering, sorting, and grouping
@MainActor
class LibraryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var books: [Book] = []
    @Published var searchText: String = ""
    @Published var sortOrder: SortOrder = .title
    @Published var selectedCategory: SidebarCategory = .allBooks
    @Published var isScanning: Bool = false
    @Published var scanResult: ScanResult?
    @Published var libraryFolderPath: String?

    // MARK: - Grouping Data

    @Published var authors: [String] = []
    @Published var genres: [String] = []
    @Published var years: [Int32] = []

    // MARK: - View Mode

    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case bigGrid = "Big Grid"
        case list = "List"

        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .bigGrid: return "square.grid.3x1.below.line.grid.1x2"
            case .list: return "list.bullet"
            }
        }
    }

    @Published var viewMode: ViewMode = .grid

    // MARK: - Sort Options

    enum SortOrder: String, CaseIterable {
        case title = "Title"
        case author = "Author"
        case year = "Year"
        case duration = "Duration"
        case recentlyPlayed = "Recently Played"
        case progress = "Progress"
    }

    // MARK: - Sidebar Categories

    enum SidebarCategory: Hashable {
        case allBooks
        case inProgress
        case completed
        case smartCollection(SmartCollection)
        case author(String)
        case genre(String)
        case year(Int32)
    }

    // MARK: - Smart Collections

    enum SmartCollection: String, CaseIterable, Hashable {
        case recentlyAdded = "Recently Added"
        case shortBooks = "Short Books"
        case longBooks = "Long Books"
        case notStarted = "Not Started"
        case nearlyFinished = "Nearly Finished"

        var icon: String {
            switch self {
            case .recentlyAdded: return "clock"
            case .shortBooks: return "hourglass.bottomhalf.filled"
            case .longBooks: return "hourglass.tophalf.filled"
            case .notStarted: return "circle"
            case .nearlyFinished: return "flag.checkered"
            }
        }

        /// Returns true if the book matches this smart collection's criteria
        func matches(_ book: Book) -> Bool {
            switch self {
            case .recentlyAdded:
                guard let modDate = book.fileModDate else { return false }
                return modDate > Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            case .shortBooks:
                return book.duration > 0 && book.duration < 4 * 3600
            case .longBooks:
                return book.duration > 10 * 3600
            case .notStarted:
                return book.playbackPosition == 0 && !book.isCompleted
            case .nearlyFinished:
                return book.progress > 0.85 && !book.isCompleted && book.duration > 0
            }
        }
    }

    // MARK: - Init

    private let persistence: PersistenceController

    /// Keeps the security-scoped resource active so AVPlayer can read files
    private var activeFolderURL: URL?

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
        self.libraryFolderPath = UserDefaults.standard.string(forKey: "libraryFolderPath")
        loadBooks()
        // Start security-scoped access on launch so files are readable for playback
        startFolderAccess()
    }

    // MARK: - Security-Scoped Folder Access

    /// Starts security-scoped access to the bookmarked folder.
    /// Keeps it alive so AVPlayer can read audio files at any time.
    func startFolderAccess() {
        // Stop any previous access
        stopFolderAccess()

        guard let bookmarkData = UserDefaults.standard.data(forKey: "libraryFolderBookmark") else { return }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                let newBookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(newBookmark, forKey: "libraryFolderBookmark")
            }

            if url.startAccessingSecurityScopedResource() {
                activeFolderURL = url
            }
        } catch {
            print("Failed to start folder access: \(error)")
        }
    }

    /// Stops security-scoped access (called on folder change or app quit)
    func stopFolderAccess() {
        activeFolderURL?.stopAccessingSecurityScopedResource()
        activeFolderURL = nil
    }

    // MARK: - Library Scanning

    /// Prompts the user to pick a folder (called on first launch or when changing the folder)
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "Select Your Audiobooks Folder"
        panel.message = "Choose the folder containing your audiobook files (m4b, m4a, mp3)."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Save a security-scoped bookmark so we can access this folder across launches
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: "libraryFolderBookmark")
        } catch {
            print("Failed to save bookmark: \(error)")
        }

        libraryFolderPath = url.path
        UserDefaults.standard.set(url.path, forKey: "libraryFolderPath")

        // Restart security-scoped access with the new bookmark
        startFolderAccess()

        // Scan immediately
        Task { await scanLibrary() }
    }

    /// Scans the library folder and updates Core Data
    func scanLibrary() async {
        // Ensure folder access is active
        if activeFolderURL == nil {
            startFolderAccess()
        }

        guard let folderURL = activeFolderURL ?? fallbackFolderURL() else { return }

        isScanning = true
        let context = persistence.container.viewContext

        let result = await LibraryScanner.scan(folder: folderURL, context: context)
        self.scanResult = result

        // Don't stop security-scoped access — AVPlayer needs it to read files

        loadBooks()
        isScanning = false

        print("Library scan: \(result.summary)")
    }

    /// Fallback: returns a plain file URL (works outside sandbox)
    private func fallbackFolderURL() -> URL? {
        guard let path = libraryFolderPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    // MARK: - Data Loading

    /// Loads books from Core Data and updates grouping data
    func loadBooks() {
        let request: NSFetchRequest<Book> = Book.fetchRequest()
        do {
            let allBooks = try persistence.container.viewContext.fetch(request)

            // Extract unique authors and genres for sidebar
            let authorSet = Set(allBooks.compactMap { $0.author }.filter { !$0.isEmpty })
            authors = authorSet.sorted()

            let genreSet = Set(allBooks.compactMap { $0.genre }.filter { !$0.isEmpty })
            genres = genreSet.sorted()

            let yearSet = Set(allBooks.map { $0.year }.filter { $0 > 0 })
            years = yearSet.sorted(by: >)  // newest first

            books = allBooks
        } catch {
            print("Failed to fetch books: \(error)")
        }
    }

    // MARK: - Filtered & Sorted Books

    /// Returns books filtered by search, category, and sorted
    var filteredBooks: [Book] {
        var result = books

        // Filter by category
        switch selectedCategory {
        case .allBooks:
            break
        case .inProgress:
            result = result.filter { $0.isInProgress }
        case .completed:
            result = result.filter { $0.isCompleted }
        case .smartCollection(let collection):
            result = result.filter { collection.matches($0) }
        case .author(let name):
            result = result.filter { $0.author == name }
        case .genre(let name):
            result = result.filter { $0.genre == name }
        case .year(let yr):
            result = result.filter { $0.year == yr }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { book in
                (book.title?.lowercased().contains(query) ?? false) ||
                (book.author?.lowercased().contains(query) ?? false) ||
                (book.genre?.lowercased().contains(query) ?? false)
            }
        }

        // Sort
        switch sortOrder {
        case .title:
            result.sort { ($0.displayTitle) < ($1.displayTitle) }
        case .author:
            result.sort { $0.displayAuthor < $1.displayAuthor }
        case .year:
            result.sort { $0.year > $1.year }
        case .duration:
            result.sort { $0.duration < $1.duration }
        case .recentlyPlayed:
            result.sort { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        case .progress:
            result.sort { $0.progress > $1.progress }
        }

        return result
    }

    // MARK: - Book Actions

    /// Resets a book's playback progress to zero
    func resetProgress(for book: Book) {
        book.playbackPosition = 0
        book.lastPlayedDate = nil
        book.isCompleted = false
        persistence.save()
        notifyChange()
    }

    /// Marks a book as completed and resets its progress
    func markCompleted(_ book: Book) {
        book.isCompleted = true
        book.playbackPosition = 0
        persistence.save()
        notifyChange()
    }

    /// Unmarks a book as completed (moves it back to the library)
    func markNotCompleted(_ book: Book) {
        book.isCompleted = false
        persistence.save()
        notifyChange()
    }

    /// Defers objectWillChange to the next run loop tick to avoid
    /// "Publishing changes from within view updates" warnings
    private func notifyChange() {
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
    }

    /// Reveals the book's file in Finder
    func showInFinder(_ book: Book) {
        guard let path = book.filePath else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Copies the book's title to the clipboard
    func copyTitle(_ book: Book) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(book.displayTitle, forType: .string)
    }

    // MARK: - Import / Export

    /// Exports all book progress and bookmarks to a JSON file via NSSavePanel
    func exportProgress() {
        guard let data = ProgressExporter.exportProgress(books: books) else { return }

        let panel = NSSavePanel()
        panel.title = "Export Audiobook Progress"
        panel.nameFieldStringValue = "audiobook-progress.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url)
        } catch {
            print("Export failed: \(error)")
        }
    }

    /// Imports progress from a JSON file via NSOpenPanel, then shows a summary alert
    func importProgress() {
        let panel = NSOpenPanel()
        panel.title = "Import Audiobook Progress"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let context = persistence.container.viewContext
            guard let result = ProgressExporter.importProgress(from: data, context: context) else {
                showImportAlert(message: "Could not read the progress file. It may be in an unsupported format.")
                return
            }

            loadBooks()

            var summary = "Updated \(result.booksUpdated) book(s)."
            if result.bookmarksCreated > 0 {
                summary += "\nImported \(result.bookmarksCreated) bookmark(s)."
            }
            if result.booksNotFound > 0 {
                summary += "\nSkipped \(result.booksNotFound) book(s) not in library."
            }
            showImportAlert(message: summary)
        } catch {
            showImportAlert(message: "Failed to read file: \(error.localizedDescription)")
        }
    }

    /// Shows an alert with import results
    private func showImportAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Import Complete"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
