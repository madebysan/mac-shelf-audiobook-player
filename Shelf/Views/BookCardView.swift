import SwiftUI

/// Card size variants for grid views
enum BookCardSize {
    case regular  // 160x160 cover
    case large    // 240x240 cover

    var coverSize: CGFloat {
        switch self {
        case .regular: return 160
        case .large: return 240
        }
    }

    var cardWidth: CGFloat { coverSize }

    var titleFont: Font {
        switch self {
        case .regular: return .caption
        case .large: return .body
        }
    }

    var subtitleFont: Font {
        switch self {
        case .regular: return .caption2
        case .large: return .caption
        }
    }

    var playIconSize: CGFloat {
        switch self {
        case .regular: return 44
        case .large: return 56
        }
    }
}

/// A single book card in the library grid: cover art, title, author, duration, progress bar
struct BookCardView: View {
    let book: Book
    let size: BookCardSize
    let onTap: () -> Void

    @EnvironmentObject var libraryVM: LibraryViewModel
    @EnvironmentObject var playerVM: PlayerViewModel
    @State private var isHovering = false

    init(book: Book, size: BookCardSize = .regular, onTap: @escaping () -> Void) {
        self.book = book
        self.size = size
        self.onTap = onTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cover art (1:1 aspect ratio)
            Button(action: onTap) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: book.coverImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: size.coverSize, height: size.coverSize)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                    // Play overlay — always in tree, visibility via opacity
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.3))

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: size.playIconSize))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .opacity(isHovering ? 1 : 0)

                    // Progress badge
                    if book.progress > 0 && !book.isCompleted {
                        Text(book.progressPercentage)
                            .font(size == .large ? .caption : .caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                            .padding(6)
                    }

                    // Completed badge
                    if book.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(size == .large ? .title2 : .title3)
                            .foregroundColor(.green)
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }
                .frame(width: size.coverSize, height: size.coverSize)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }

            // Progress bar (thin line under cover)
            if book.progress > 0 && !book.isCompleted {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 3)
                            .cornerRadius(1.5)

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * book.progress, height: 3)
                            .cornerRadius(1.5)
                    }
                }
                .frame(height: 3)
            }

            // Title
            Text(book.displayTitle)
                .font(size.titleFont)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Author
            Text(book.displayAuthor)
                .font(size.subtitleFont)
                .foregroundColor(.secondary)
                .lineLimit(1)

            // Duration
            if book.duration > 0 {
                Text(book.formattedDuration)
                    .font(size.subtitleFont)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size.cardWidth)
        .contextMenu { bookContextMenu }
    }

    // MARK: - Context Menu (shared with BookListRow)

    @ViewBuilder
    var bookContextMenu: some View {
        Button {
            onTap()
        } label: {
            Label(book.isInProgress ? "Resume" : "Play", systemImage: "play.fill")
        }

        Divider()

        if !book.isCompleted {
            Button {
                libraryVM.markCompleted(book)
            } label: {
                Label("Mark as Completed", systemImage: "checkmark.circle")
            }
        } else {
            Button {
                libraryVM.markNotCompleted(book)
            } label: {
                Label("Mark as Not Completed", systemImage: "arrow.uturn.backward")
            }
        }

        if book.playbackPosition > 0 || book.isCompleted {
            Button {
                libraryVM.resetProgress(for: book)
            } label: {
                Label("Reset Progress", systemImage: "arrow.counterclockwise")
            }
        }

        Divider()

        Button {
            libraryVM.showInFinder(book)
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Button {
            libraryVM.copyTitle(book)
        } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }

        Divider()

        Menu("Book Info") {
            if let author = book.author, !author.isEmpty {
                Text("Author: \(author)")
            }
            if let genre = book.genre, !genre.isEmpty {
                Text("Genre: \(genre)")
            }
            if book.year > 0 {
                Text("Year: \(book.year)")
            }
            if book.duration > 0 {
                Text("Duration: \(book.formattedDuration)")
            }
            if book.hasChapters {
                Text("Has chapters")
            }
        }
    }
}
