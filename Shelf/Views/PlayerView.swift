import SwiftUI

/// Full player view shown as a sheet — cover art, controls, chapters
struct PlayerView: View {
    @EnvironmentObject var playerVM: PlayerViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding()
            }

            // Main content
            HStack(alignment: .top, spacing: 30) {
                // Left: Cover art + info
                VStack(spacing: 16) {
                    if let book = playerVM.currentBook {
                        Image(nsImage: book.coverImage)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: 240, height: 240)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

                        VStack(spacing: 4) {
                            Text(book.displayTitle)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text(book.displayAuthor)
                                .font(.body)
                                .foregroundColor(.secondary)

                            if let chapter = playerVM.currentChapterName {
                                Text(chapter)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
                .frame(maxWidth: 240)

                // Right: Controls + chapter list
                VStack(spacing: 20) {
                    // Scrubber
                    VStack(spacing: 4) {
                        Slider(
                            value: Binding(
                                get: { playerVM.audioService.currentTime },
                                set: { playerVM.audioService.seek(to: $0) }
                            ),
                            in: 0...max(playerVM.audioService.duration, 1)
                        )

                        HStack {
                            Text(Book.formatScrubberTime(playerVM.audioService.currentTime))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Spacer()
                            // Remaining time
                            Text("-" + Book.formatScrubberTime(max(playerVM.audioService.duration - playerVM.audioService.currentTime, 0)))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Transport controls
                    HStack(spacing: 28) {
                        // Speed button
                        Menu {
                            ForEach(AudioPlayerService.speeds, id: \.self) { speed in
                                Button {
                                    playerVM.audioService.setSpeed(speed)
                                } label: {
                                    HStack {
                                        Text(speed == Float(Int(speed)) ? "\(Int(speed))x" : String(format: "%.2gx", speed))
                                        if playerVM.audioService.playbackRate == speed {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Text(playerVM.speedLabel)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary)
                                .cornerRadius(6)
                        }

                        Spacer()

                        Button { playerVM.audioService.skipBackward() } label: {
                            Image(systemName: "gobackward.30")
                                .font(.title)
                        }
                        .buttonStyle(.plain)

                        Button { playerVM.audioService.togglePlayPause() } label: {
                            Image(systemName: playerVM.audioService.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 52))
                        }
                        .buttonStyle(.plain)

                        Button { playerVM.audioService.skipForward() } label: {
                            Image(systemName: "goforward.30")
                                .font(.title)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        // Bookmark button
                        Button {
                            playerVM.showAddBookmark = true
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Add Bookmark")

                        // Bookmark list toggle
                        Button {
                            playerVM.showBookmarkList.toggle()
                        } label: {
                            Image(systemName: "bookmark")
                                .font(.title3)
                                .foregroundColor(playerVM.showBookmarkList ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Bookmarks (\(playerVM.bookmarks.count))")

                        // Chapter toggle (only if chapters exist)
                        if !playerVM.chapters.isEmpty {
                            Button {
                                playerVM.showChapterList.toggle()
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.title3)
                                    .foregroundColor(playerVM.showChapterList ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Chapters")
                        } else {
                            // Spacer for alignment
                            Color.clear.frame(width: 20)
                        }
                    }

                    // Bookmark list (expandable)
                    if playerVM.showBookmarkList {
                        BookmarkListView()
                    }

                    // Chapter list (expandable)
                    if playerVM.showChapterList && !playerVM.chapters.isEmpty {
                        ChapterListView()
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $playerVM.showAddBookmark) {
            AddBookmarkSheet()
                .environmentObject(playerVM)
        }
    }
}
