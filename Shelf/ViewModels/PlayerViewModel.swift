import Foundation
import SwiftUI
import Combine
import CoreData

/// Bridges the AudioPlayerService with the UI, manages chapter data
@MainActor
class PlayerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentBook: Book?
    @Published var chapters: [ChapterInfo] = []
    @Published var currentChapterIndex: Int = 0
    @Published var showChapterList: Bool = false
    @Published var bookmarks: [Bookmark] = []
    @Published var showBookmarkList: Bool = false
    @Published var showAddBookmark: Bool = false

    let audioService: AudioPlayerService
    private var cancellables = Set<AnyCancellable>()

    init(audioService: AudioPlayerService) {
        self.audioService = audioService

        // Forward audioService changes so views that observe PlayerViewModel
        // also redraw when isPlaying, currentTime, etc. change.
        // receive(on:) defers delivery to the next run loop tick, avoiding
        // "Publishing changes from within view updates" warnings.
        audioService.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Playback

    /// Opens a book for playback (loads chapters, starts playing)
    func openBook(_ book: Book) {
        currentBook = book

        // Load chapters if the book has them
        if book.hasChapters, let path = book.filePath {
            Task {
                let url = URL(fileURLWithPath: path)
                chapters = await MetadataExtractor.extractChapters(from: url)
            }
        } else {
            chapters = []
        }

        loadBookmarks(for: book)
        audioService.play(book: book)
    }

    /// Current chapter name based on playback position
    var currentChapterName: String? {
        guard !chapters.isEmpty else { return nil }
        let time = audioService.currentTime
        if let chapter = chapters.last(where: { $0.startTime <= time }) {
            return chapter.title
        }
        return chapters.first?.title
    }

    /// Updates the current chapter index based on playback position
    func updateCurrentChapter() {
        let time = audioService.currentTime
        if let index = chapters.lastIndex(where: { $0.startTime <= time }) {
            currentChapterIndex = index
        }
    }

    /// Jumps to a specific chapter
    func goToChapter(_ chapter: ChapterInfo) {
        audioService.seek(to: chapter.startTime)
    }

    /// Next chapter
    func nextChapter() {
        let next = currentChapterIndex + 1
        guard next < chapters.count else { return }
        goToChapter(chapters[next])
    }

    /// Previous chapter (goes to start of current chapter, or previous if near the start)
    func previousChapter() {
        let time = audioService.currentTime
        let current = chapters[safe: currentChapterIndex]

        // If more than 3 seconds into the chapter, go to its start
        if let current = current, time - current.startTime > 3 {
            goToChapter(current)
        } else {
            let prev = currentChapterIndex - 1
            guard prev >= 0 else { return }
            goToChapter(chapters[prev])
        }
    }

    /// Speed display label
    var speedLabel: String {
        let rate = audioService.playbackRate
        if rate == Float(Int(rate)) {
            return "\(Int(rate))x"
        }
        return String(format: "%.2gx", rate)
    }

    // MARK: - Bookmarks

    /// Loads bookmarks for the given book from Core Data, sorted by timestamp
    func loadBookmarks(for book: Book) {
        guard let bookmarkSet = book.bookmarks as? Set<Bookmark> else {
            bookmarks = []
            return
        }
        bookmarks = bookmarkSet.sorted { $0.timestamp < $1.timestamp }
    }

    /// Adds a new bookmark at the current playback position
    func addBookmark(name: String, note: String?) {
        guard let book = currentBook else { return }
        let context = book.managedObjectContext ?? PersistenceController.shared.container.viewContext

        let bookmark = Bookmark(context: context)
        bookmark.id = UUID()
        bookmark.timestamp = audioService.currentTime
        bookmark.name = name
        bookmark.note = note
        bookmark.createdDate = Date()
        bookmark.book = book

        PersistenceController.shared.save()
        loadBookmarks(for: book)
    }

    /// Deletes a bookmark from Core Data
    func deleteBookmark(_ bookmark: Bookmark) {
        guard let book = currentBook else { return }
        let context = bookmark.managedObjectContext ?? PersistenceController.shared.container.viewContext
        context.delete(bookmark)
        PersistenceController.shared.save()
        loadBookmarks(for: book)
    }

    /// Seeks playback to a bookmark's timestamp
    func jumpToBookmark(_ bookmark: Bookmark) {
        audioService.seek(to: bookmark.timestamp)
    }
}

// Safe array indexing
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
