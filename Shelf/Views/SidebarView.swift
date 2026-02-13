import SwiftUI

/// Sidebar navigation with collapsible groups — inspired by Things app
struct SidebarView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel

    // Persist expansion state across launches
    @AppStorage("sidebar_smartCollectionsExpanded") private var smartCollectionsExpanded = false
    @AppStorage("sidebar_authorsExpanded") private var authorsExpanded = false
    @AppStorage("sidebar_genresExpanded") private var genresExpanded = false
    @AppStorage("sidebar_yearsExpanded") private var yearsExpanded = false

    // Book counts for library categories
    private var inProgressCount: Int {
        libraryVM.books.filter { $0.isInProgress }.count
    }
    private var completedCount: Int {
        libraryVM.books.filter { $0.isCompleted }.count
    }

    /// Smart collections that have at least one matching book
    private var activeSmartCollections: [(collection: LibraryViewModel.SmartCollection, count: Int)] {
        LibraryViewModel.SmartCollection.allCases.compactMap { collection in
            let count = libraryVM.books.filter { collection.matches($0) }.count
            return count > 0 ? (collection, count) : nil
        }
    }

    var body: some View {
        List(selection: $libraryVM.selectedCategory) {
            // Library — always visible
            Section {
                sidebarRow("All Books", icon: "books.vertical", count: libraryVM.books.count)
                    .tag(LibraryViewModel.SidebarCategory.allBooks)

                sidebarRow("In Progress", icon: "book", count: inProgressCount)
                    .tag(LibraryViewModel.SidebarCategory.inProgress)

                sidebarRow("Completed", icon: "checkmark.circle", count: completedCount)
                    .tag(LibraryViewModel.SidebarCategory.completed)
            } header: {
                Text("Library")
            }

            // Smart Collections — only shown if any have matching books
            if !activeSmartCollections.isEmpty {
                DisclosureGroup(isExpanded: $smartCollectionsExpanded) {
                    ForEach(activeSmartCollections, id: \.collection) { item in
                        sidebarRow(item.collection.rawValue, icon: item.collection.icon, count: item.count)
                            .tag(LibraryViewModel.SidebarCategory.smartCollection(item.collection))
                    }
                } label: {
                    sectionHeader("Smart Collections", count: activeSmartCollections.count)
                }
            }

            // Authors
            if !libraryVM.authors.isEmpty {
                DisclosureGroup(isExpanded: $authorsExpanded) {
                    ForEach(libraryVM.authors, id: \.self) { author in
                        sidebarRow(author, icon: "person", count: countBooks(for: .author(author)))
                            .tag(LibraryViewModel.SidebarCategory.author(author))
                    }
                } label: {
                    sectionHeader("Authors", count: libraryVM.authors.count)
                }

            }

            // Genres
            if !libraryVM.genres.isEmpty {
                DisclosureGroup(isExpanded: $genresExpanded) {
                    ForEach(libraryVM.genres, id: \.self) { genre in
                        sidebarRow(genre, icon: "tag", count: countBooks(for: .genre(genre)))
                            .tag(LibraryViewModel.SidebarCategory.genre(genre))
                    }
                } label: {
                    sectionHeader("Genres", count: libraryVM.genres.count)
                }
            }

            // Years
            if !libraryVM.years.isEmpty {
                DisclosureGroup(isExpanded: $yearsExpanded) {
                    ForEach(libraryVM.years, id: \.self) { year in
                        sidebarRow(String(year), icon: "calendar", count: countBooks(for: .year(year)))
                            .tag(LibraryViewModel.SidebarCategory.year(year))
                    }
                } label: {
                    sectionHeader("Years", count: libraryVM.years.count)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await libraryVM.scanLibrary() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(libraryVM.isScanning)
                .help("Refresh Library")
            }
        }
    }

    // MARK: - Components

    /// A single sidebar row with icon, label, and trailing count
    private func sidebarRow(_ title: String, icon: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .lineLimit(1)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 2)
            }
        }
    }

    /// Disclosure group header styled like a section title
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Spacer()

            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.trailing, 2)
        }
        .contentShape(Rectangle())
    }

    /// Counts books matching a sidebar category
    private func countBooks(for category: LibraryViewModel.SidebarCategory) -> Int {
        switch category {
        case .author(let name):
            return libraryVM.books.filter { $0.author == name }.count
        case .genre(let name):
            return libraryVM.books.filter { $0.genre == name }.count
        case .year(let yr):
            return libraryVM.books.filter { $0.year == yr }.count
        case .smartCollection(let collection):
            return libraryVM.books.filter { collection.matches($0) }.count
        default:
            return 0
        }
    }
}
