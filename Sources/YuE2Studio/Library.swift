import Foundation

/// A named collection of songs with its own categories and an optional radio station.
struct MusicLibrary: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var description = ""
    var refinedDescription = ""
    var categories: [String] = [LibraryIndex.uncategorized]
    var radioFastDrafts = false
    var radioAutoplay = false

    var stationBrief: String {
        refinedDescription.isEmpty ? description : refinedDescription
    }
}

struct SongPlacement: Codable, Hashable {
    var library: UUID
    var category: String
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var songIDs: [String] = []
}

/// Everything the composer needs to reproduce or edit a song. Saved as `studio.json`
/// inside the song folder.
struct StudioMeta: Codable {
    var title: String
    var idea: String
    var style: String
    var lyrics: String
    var mode: String
    var seed: Int64
    var odeSteps: Int
    var source: String        // "manual" | "radio"
    var createdAt: Date

    static func load(from dir: URL) -> StudioMeta? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("studio.json")) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(StudioMeta.self, from: data)
    }

    func save(to dir: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(self) {
            try? data.write(to: dir.appendingPathComponent("studio.json"))
        }
    }
}

/// Persisted next to the songs as `library.json`.
struct LibraryIndex: Codable {
    static let uncategorized = "Uncategorized"

    var libraries: [MusicLibrary] = [MusicLibrary(name: "My Library")]
    var placements: [String: SongPlacement] = [:]   // song id -> library + category
    var playlists: [Playlist] = []

    init() {}

    // Tolerant decoding: fills defaults for missing keys and migrates the v1 single-library layout.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        libraries = try c.decodeIfPresent([MusicLibrary].self, forKey: .libraries) ?? []
        placements = try c.decodeIfPresent([String: SongPlacement].self, forKey: .placements) ?? [:]
        playlists = try c.decodeIfPresent([Playlist].self, forKey: .playlists) ?? []

        if libraries.isEmpty {
            var lib = MusicLibrary(name: "My Library")
            if let cats = try c.decodeIfPresent([String].self, forKey: .categories) {
                for cat in cats where !lib.categories.contains(cat) { lib.categories.append(cat) }
            }
            if let old = try c.decodeIfPresent([String: String].self, forKey: .songCategories) {
                for (song, cat) in old { placements[song] = SongPlacement(library: lib.id, category: cat) }
            }
            libraries = [lib]
        }
        for i in libraries.indices where !libraries[i].categories.contains(Self.uncategorized) {
            libraries[i].categories.insert(Self.uncategorized, at: 0)
        }
    }

    private enum Keys: String, CodingKey { case libraries, placements, playlists, categories, songCategories }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(libraries, forKey: .libraries)
        try c.encode(placements, forKey: .placements)
        try c.encode(playlists, forKey: .playlists)
    }

    static func load(from url: URL) -> LibraryIndex {
        guard let data = try? Data(contentsOf: url),
              let idx = try? JSONDecoder().decode(LibraryIndex.self, from: data) else { return LibraryIndex() }
        return idx
    }

    func save(to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: url) }
    }

    func library(_ id: UUID) -> MusicLibrary? { libraries.first { $0.id == id } }

    /// Resolved placement: falls back to the first library / Uncategorized when stale.
    func placement(for songID: String) -> SongPlacement {
        let fallback = SongPlacement(library: libraries[0].id, category: Self.uncategorized)
        guard let p = placements[songID], let lib = library(p.library) else { return fallback }
        return lib.categories.contains(p.category) ? p : SongPlacement(library: lib.id, category: Self.uncategorized)
    }
}

enum SidebarSelection: Hashable {
    case library(UUID)
    case song(String)
    case playlist(UUID)
}
