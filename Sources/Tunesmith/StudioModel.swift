import Foundation
import AVFoundation
import AppKit

enum SongMode: String, CaseIterable, Identifiable {
    case full, melody, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .full: return "Full score"
        case .melody: return "Melody only"
        case .off: return "Direct"
        }
    }
    var help: String {
        switch self {
        case .full: return "Writes melody + chords first, then renders. Best default."
        case .melody: return "Writes a melody, leaves the accompaniment free."
        case .off: return "Skips the score and renders straight from style + lyrics."
        }
    }
}

struct Song: Identifiable, Hashable {
    let id: String          // directory name
    let title: String
    let style: String
    let created: Date
    let directory: URL
    let source: String
    var audioURL: URL { directory.appendingPathComponent("audio.flac") }
    var scoreURL: URL { directory.appendingPathComponent("score.abc") }
}

/// Everything one render needs; built from the composer or by the radio.
struct GenerationSpec {
    var title: String
    var idea: String
    var style: String
    var lyrics: String
    var mode: SongMode
    var seed: Int64
    var odeSteps: Int
    var source: String
    var library: UUID
    var category: String

    var meta: StudioMeta {
        StudioMeta(title: title, idea: idea, style: style, lyrics: lyrics, mode: mode.rawValue,
                   seed: seed, odeSteps: odeSteps, source: source, createdAt: Date())
    }
}

@MainActor
@Observable
final class StudioModel {
    // MARK: Settings
    var projectDir: URL {
        didSet { UserDefaults.standard.set(projectDir.path, forKey: "projectDir"); checkSetup() }
    }
    var outputRoot: URL {
        didSet { UserDefaults.standard.set(outputRoot.path, forKey: "outputRoot"); reloadIndex(); refreshLibrary() }
    }
    var claudePathOverride: String {
        didSet { UserDefaults.standard.set(claudePathOverride, forKey: "claudePath") }
    }
    var claudeModel: String {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }
    var remailAPIKey: String {
        didSet { Keychain.set(remailAPIKey, service: Self.keychainService, account: "remail-api-key") }
    }
    var remailFrom: String {
        didSet { UserDefaults.standard.set(remailFrom, forKey: "remailFrom") }
    }
    var remailReplyTo: String {
        didSet { UserDefaults.standard.set(remailReplyTo, forKey: "remailReplyTo") }
    }
    /// Unchanged across the rename to Tunesmith so existing keychain items still resolve.
    static let keychainService = "com.scott.yue2studio"
    static let defaultRemailFrom = "Scott <scott@johnnycode.ai>"

    // MARK: Idea → song (Claude CLI)
    var idea = ""
    var isRefining = false
    var isWriting = false
    private var claudeProcess: Process?

    var claudeURL: URL? { ClaudeCLI.locate(override: claudePathOverride) }
    var isBusy: Bool { isGenerating || isRefining || isWriting }

    // MARK: Form
    var title = ""
    var style = ""
    var lyrics = ""
    var seedText = ""
    var mode: SongMode = .full
    var fastDraft = false
    var allowBattery = false
    var targetLibraryID: UUID? = nil

    // MARK: Generation state
    var isGenerating = false
    var stageText = ""
    var progress: Double? = nil
    var log = ""
    var errorMessage: String? = nil
    var setupProblem: String? = nil

    // MARK: Library
    var songs: [Song] = []
    var index = LibraryIndex()
    var selection: SidebarSelection? = nil {
        didSet {
            if let e = editingSongID, selection != .song(e) { editingSongID = nil }
        }
    }
    /// Song whose generation details are open in the composer (nil = player view).
    var editingSongID: String? = nil
    var askNewCategory = false
    var askNewPlaylist = false
    var askNewLibrary = false
    /// Song whose share-by-email sheet is open.
    var sharingSong: Song? = nil

    // MARK: Radio
    var radioLibraryID: UUID? = nil
    var radioStatus = ""
    var radioCount = 0
    var radioError: String? = nil
    /// Set when the station is switched off with a render still in flight — that song
    /// is allowed to finish and file itself before the loop exits.
    var radioWindingDown: UUID? = nil
    /// Title of the song currently rendering, for "up next" UI.
    var renderingTitle: String? = nil
    var isRefiningStation = false
    private var radioTask: Task<Void, Never>? = nil
    /// Freshly rendered song waiting to go on the air after the current track.
    private var radioPendingSongID: String? = nil
    /// Recently aired ids, so the random filler doesn't repeat itself immediately.
    private var radioRecentIDs: [String] = []

    // MARK: Playback
    var isPlaying = false
    var isPaused = false
    var nowPlayingID: String? = nil
    var playbackDuration: TimeInterval = 0
    var playbackPosition: TimeInterval = 0
    private var queue: [Song] = []
    private var queueIndex = 0

    private var process: Process?
    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var pendingOutputDir: URL?
    private var pendingSpec: GenerationSpec?
    private var replacingSong: Song?
    private var generationCompletion: ((Result<String, Error>) -> Void)?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let savedProject = UserDefaults.standard.string(forKey: "projectDir")
        projectDir = URL(fileURLWithPath: savedProject ?? home.appendingPathComponent("repos/mlx-Yue").path)
        let savedOut = UserDefaults.standard.string(forKey: "outputRoot")
        outputRoot = URL(fileURLWithPath: savedOut ?? Self.defaultOutputRoot(home: home).path)
        claudePathOverride = UserDefaults.standard.string(forKey: "claudePath") ?? ""
        claudeModel = UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-opus-5"
        remailAPIKey = Keychain.get(service: Self.keychainService, account: "remail-api-key") ?? ""
        remailFrom = UserDefaults.standard.string(forKey: "remailFrom") ?? Self.defaultRemailFrom
        remailReplyTo = UserDefaults.standard.string(forKey: "remailReplyTo") ?? ""
        checkSetup()
        reloadIndex()
        refreshLibrary()
    }

    // MARK: Derived

    var libraries: [MusicLibrary] { index.libraries }
    func library(_ id: UUID) -> MusicLibrary? { index.library(id) }

    var selectedSongID: String? {
        if case .song(let id) = selection { return id }
        return nil
    }
    var selectedSong: Song? { songs.first { $0.id == selectedSongID } }
    var selectedPlaylist: Playlist? {
        if case .playlist(let id) = selection { return index.playlists.first { $0.id == id } }
        return nil
    }
    var selectedLibrary: MusicLibrary? {
        if case .library(let id) = selection { return library(id) }
        return nil
    }
    func song(_ id: String) -> Song? { songs.first { $0.id == id } }
    func songs(in libraryID: UUID) -> [Song] { songs.filter { index.placement(for: $0.id).library == libraryID } }
    func songs(in libraryID: UUID, category: String) -> [Song] {
        songs.filter { let p = index.placement(for: $0.id); return p.library == libraryID && p.category == category }
    }
    func songs(in playlist: Playlist) -> [Song] { playlist.songIDs.compactMap(song) }

    /// Library the composer will file the next song in.
    var resolvedTargetLibrary: MusicLibrary {
        if let id = targetLibraryID, let l = library(id) { return l }
        return libraries[0]
    }

    var pythonURL: URL { projectDir.appendingPathComponent(".venv/bin/python") }
    var modelDir: URL { projectDir.appendingPathComponent("models/converted") }
    var vaeDir: URL { projectDir.appendingPathComponent("models/vae") }
    private var indexURL: URL { outputRoot.appendingPathComponent("library.json") }

    var canGenerate: Bool {
        !isBusy && setupProblem == nil && !style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canUseIdea: Bool {
        !isBusy && claudeURL != nil && !idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func checkSetup() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: pythonURL.path) {
            setupProblem = "Python runtime not found at \(pythonURL.path). Point Settings → Project folder at your mlx-Yue checkout."
        } else if !fm.fileExists(atPath: modelDir.appendingPathComponent("ar-8bit.safetensors").path) {
            setupProblem = "Model weights not found in \(modelDir.path)."
        } else if !fm.fileExists(atPath: vaeDir.appendingPathComponent("model.safetensors").path) {
            setupProblem = "VAE weights not found in \(vaeDir.path)."
        } else {
            setupProblem = nil
        }
    }

    // MARK: Library index

    private func reloadIndex() { index = LibraryIndex.load(from: indexURL) }
    private func saveIndex() { index.save(to: indexURL) }

    func refreshLibrary() {
        let fm = FileManager.default
        try? fm.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        guard let dirs = try? fm.contentsOfDirectory(at: outputRoot, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]) else {
            songs = []; return
        }
        var found: [Song] = []
        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  fm.fileExists(atPath: dir.appendingPathComponent("audio.flac").path) else { continue }
            var title = dir.lastPathComponent
            var style = ""
            var source = "manual"
            if let meta = StudioMeta.load(from: dir) {
                title = meta.title
                style = meta.style
                source = meta.source
            } else if let data = try? Data(contentsOf: dir.appendingPathComponent("request.json")),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                title = (json["id"] as? String) ?? title
                style = (json["style"] as? String) ?? ""
            }
            let created = (try? dir.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            found.append(Song(id: dir.lastPathComponent, title: title, style: style, created: created, directory: dir, source: source))
        }
        songs = found.sorted { $0.created > $1.created }
    }

    // Libraries

    @discardableResult
    func addLibrary(_ name: String) -> MusicLibrary? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        let lib = MusicLibrary(name: n)
        index.libraries.append(lib); saveIndex()
        return lib
    }

    func updateLibrary(_ lib: MusicLibrary) {
        guard let i = index.libraries.firstIndex(where: { $0.id == lib.id }) else { return }
        index.libraries[i] = lib; saveIndex()
        if isRadioOn(lib.id), lib.radioAutoplay, !isPlaying { radioPlayNext() }
    }

    func deleteLibrary(_ id: UUID) {
        guard index.libraries.count > 1, let i = index.libraries.firstIndex(where: { $0.id == id }) else { return }
        if radioLibraryID == id { setRadio(false, for: id) }
        index.libraries.remove(at: i)
        let fallback = index.libraries[0].id
        for (song, p) in index.placements where p.library == id {
            index.placements[song] = SongPlacement(library: fallback, category: LibraryIndex.uncategorized)
        }
        if case .library(let sel) = selection, sel == id { selection = nil }
        if targetLibraryID == id { targetLibraryID = nil }
        saveIndex()
    }

    // Categories (per library)

    @discardableResult
    func addCategory(_ name: String, to libraryID: UUID) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let i = index.libraries.firstIndex(where: { $0.id == libraryID }) else { return nil }
        if let existing = index.libraries[i].categories.first(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) {
            return existing
        }
        index.libraries[i].categories.append(n); saveIndex()
        return n
    }

    func renameCategory(_ old: String, to new: String, in libraryID: UUID) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard old != LibraryIndex.uncategorized, !n.isEmpty,
              let i = index.libraries.firstIndex(where: { $0.id == libraryID }),
              !index.libraries[i].categories.contains(n),
              let ci = index.libraries[i].categories.firstIndex(of: old) else { return }
        index.libraries[i].categories[ci] = n
        for (song, p) in index.placements where p.library == libraryID && p.category == old {
            index.placements[song] = SongPlacement(library: libraryID, category: n)
        }
        saveIndex()
    }

    func deleteCategory(_ name: String, in libraryID: UUID) {
        guard name != LibraryIndex.uncategorized, let i = index.libraries.firstIndex(where: { $0.id == libraryID }) else { return }
        index.libraries[i].categories.removeAll { $0 == name }
        for (song, p) in index.placements where p.library == libraryID && p.category == name {
            index.placements[song] = SongPlacement(library: libraryID, category: LibraryIndex.uncategorized)
        }
        saveIndex()
    }

    func place(_ song: Song, in libraryID: UUID, category: String) {
        guard let lib = library(libraryID) else { return }
        let cat = lib.categories.contains(category) ? category : LibraryIndex.uncategorized
        index.placements[song.id] = SongPlacement(library: libraryID, category: cat)
        saveIndex()
    }

    // Playlists

    func addPlaylist(_ name: String) -> Playlist? {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        let p = Playlist(name: n)
        index.playlists.append(p); saveIndex()
        return p
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let i = index.playlists.firstIndex(where: { $0.id == id }) else { return }
        index.playlists[i].name = n; saveIndex()
    }

    func deletePlaylist(_ id: UUID) {
        index.playlists.removeAll { $0.id == id }
        if case .playlist(let sel) = selection, sel == id { selection = nil }
        saveIndex()
    }

    func add(_ song: Song, to playlistID: UUID) {
        guard let i = index.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        if !index.playlists[i].songIDs.contains(song.id) { index.playlists[i].songIDs.append(song.id) }
        saveIndex()
    }

    func removeFromPlaylist(_ playlistID: UUID, at offsets: IndexSet) {
        guard let i = index.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        index.playlists[i].songIDs.remove(atOffsets: offsets); saveIndex()
    }

    func movePlaylistSongs(_ playlistID: UUID, from: IndexSet, to: Int) {
        guard let i = index.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        index.playlists[i].songIDs.move(fromOffsets: from, toOffset: to); saveIndex()
    }

    // MARK: Idea → song

    private func makeCLI() -> ClaudeCLI? {
        guard let url = claudeURL else { return nil }
        return ClaudeCLI(executable: url, model: claudeModel)
    }

    func refineIdea() {
        guard canUseIdea, let cli = makeCLI() else { return }
        isRefining = true
        errorMessage = nil
        stageText = "Refining prompt with Claude…"
        progress = nil
        let text = idea
        Task {
            do {
                let result = try await cli.run(system: SongWriter.refineSystem, prompt: text) { [weak self] p in
                    Task { @MainActor in self?.claudeProcess = p }
                }
                if let brief = result as? String { idea = brief.trimmingCharacters(in: .whitespacesAndNewlines) }
                stageText = "Prompt refined"
            } catch {
                stageText = "Failed"
                errorMessage = error.localizedDescription
            }
            isRefining = false
            claudeProcess = nil
        }
    }

    func writeSong(thenGenerate: Bool) {
        guard canUseIdea, let cli = makeCLI() else { return }
        isWriting = true
        errorMessage = nil
        stageText = "Writing lyrics and style with Claude…"
        progress = nil
        let text = idea
        Task {
            do {
                let result = try await cli.run(system: SongWriter.writeSystem, prompt: text,
                                               schema: SongWriter.writeSchema(withCategory: false)) { [weak self] p in
                    Task { @MainActor in self?.claudeProcess = p }
                }
                guard let spec = SongWriter.Spec(result) else {
                    throw ClaudeCLI.Failure(message: "Claude returned an unexpected shape.")
                }
                title = spec.title
                style = spec.style
                lyrics = spec.lyrics
                seedText = ""
                mode = .full
                isWriting = false
                claudeProcess = nil
                if thenGenerate { generate() } else { stageText = "Song written — review, then Generate." }
            } catch {
                isWriting = false
                claudeProcess = nil
                stageText = "Failed"
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Station (library description) refinement

    func refineStation(_ libraryID: UUID) {
        guard let lib = library(libraryID), let cli = makeCLI(),
              !lib.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isRefiningStation = true
        errorMessage = nil
        Task {
            do {
                let result = try await cli.run(system: SongWriter.refineStationSystem, prompt: lib.description)
                if var updated = library(libraryID), let brief = result as? String {
                    updated.refinedDescription = brief.trimmingCharacters(in: .whitespacesAndNewlines)
                    updateLibrary(updated)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isRefiningStation = false
        }
    }

    // MARK: Radio

    var radioLibrary: MusicLibrary? { radioLibraryID.flatMap(library) }
    func isRadioOn(_ libraryID: UUID) -> Bool { radioLibraryID == libraryID }

    func setRadio(_ on: Bool, for libraryID: UUID) {
        if on {
            guard claudeURL != nil, setupProblem == nil, let lib = library(libraryID),
                  !lib.stationBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Give the library a description first (and make sure the claude CLI and models are set up)."
                return
            }
            radioLibraryID = libraryID
            radioError = nil
            radioCount = 0
            radioStatus = "Starting…"
            radioPendingSongID = nil
            radioRecentIDs = []
            if radioTask == nil { radioTask = Task { await radioLoop() } }
            // Don't wait for the first render — put a library song on the air now.
            if !isPlaying { radioPlayNext() }
        } else if radioLibraryID == libraryID {
            radioLibraryID = nil
            radioPendingSongID = nil
            radioRecentIDs = []
            // The song already on the renderer keeps going and still gets filed.
            radioWindingDown = isBusy ? libraryID : nil
            radioStatus = isBusy ? "Radio off — finishing \u{201C}\(renderingTitle ?? "the current song")\u{201D}…" : ""
        }
    }

    // MARK: Radio playback
    //
    // With Auto-play on the station never goes silent: while the next song renders it
    // airs random songs from the same library, and the fresh song goes on as soon as
    // whatever is playing ends.

    /// The rendered song queued to air next, if one is waiting.
    var radioUpNext: Song? { radioPendingSongID.flatMap(song) }

    private var radioAutoplayOn: Bool {
        guard let id = radioLibraryID, let lib = library(id) else { return false }
        return lib.radioAutoplay
    }

    /// A render finished: that song is next on the air (immediately if nothing is playing).
    private func radioDidRender(_ songID: String) {
        radioPendingSongID = songID
        if !isPlaying { radioPlayNext() }
    }

    /// Airs the pending new song if there is one, otherwise a random song from the library.
    private func radioPlayNext() {
        guard radioAutoplayOn, let libID = radioLibraryID else { return }
        let pool = songs(in: libID)
        var next: Song? = nil
        if let pending = radioPendingSongID, let s = song(pending) {
            radioPendingSongID = nil
            next = s
        } else if !pool.isEmpty {
            let unheard = pool.filter { !radioRecentIDs.contains($0.id) }
            next = (unheard.isEmpty ? pool : unheard).randomElement()
        }
        guard let s = next else { stop(); return }
        radioRecentIDs.append(s.id)
        let memory = max(1, min(5, pool.count - 1))
        if radioRecentIDs.count > memory { radioRecentIDs.removeFirst(radioRecentIDs.count - memory) }
        play(s, queue: [s])
    }

    private func radioLoop() async {
        while let libID = radioLibraryID {
            if isBusy {
                radioStatus = "Waiting for the current job to finish…"
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            do {
                try await radioStep(libID)
            } catch {
                if radioLibraryID == nil { break }
                radioError = error.localizedDescription
                radioStatus = "Error — retrying in 15 s"
                try? await Task.sleep(for: .seconds(15))
            }
        }
        radioStatus = ""
        radioWindingDown = nil
        radioTask = nil
    }

    /// One radio iteration: Claude writes + categorizes, YuE2 renders, the song is filed.
    @discardableResult
    func radioStep(_ libraryID: UUID) async throws -> String {
        guard let lib = library(libraryID), let cli = makeCLI() else {
            throw ClaudeCLI.Failure(message: "Radio library or claude CLI unavailable.")
        }
        radioStatus = "Writing the next song…"
        isWriting = true
        stageText = "Radio · writing the next song for \(lib.name)…"
        progress = nil
        defer { isWriting = false }

        let recent = songs(in: libraryID).prefix(8).map { (title: $0.title, style: $0.style) }
        let prompt = SongWriter.radioPrompt(brief: lib.stationBrief, categories: lib.categories, recent: Array(recent))
        let result: Any
        do {
            result = try await cli.run(system: SongWriter.radioWriteSystem, prompt: prompt,
                                       schema: SongWriter.writeSchema(withCategory: true)) { [weak self] p in
                Task { @MainActor in self?.claudeProcess = p }
            }
        }
        claudeProcess = nil
        isWriting = false
        guard let written = SongWriter.Spec(result) else {
            throw ClaudeCLI.Failure(message: "Claude returned an unexpected shape.")
        }

        // Resolve the category: reuse an existing one (case-insensitive) or create it.
        var category = LibraryIndex.uncategorized
        if let proposed = written.category, proposed.caseInsensitiveCompare(LibraryIndex.uncategorized) != .orderedSame {
            category = addCategory(proposed, to: libraryID) ?? LibraryIndex.uncategorized
        }

        let currentLib = library(libraryID) ?? lib
        let spec = GenerationSpec(
            title: written.title, idea: "Radio: \(currentLib.name)", style: written.style, lyrics: written.lyrics,
            mode: .full, seed: Int64.random(in: 1...9_999_999), odeSteps: currentLib.radioFastDrafts ? 8 : 32,
            source: "radio", library: libraryID, category: category)

        radioStatus = "Rendering “\(written.title)” → \(category)"
        let slug = Self.slugify(written.title)
        let outDir = outputRoot.appendingPathComponent("\(slug)-\(Self.stampFormatter.string(from: Date()))")
        let songID = try await generateAsync(spec: spec, outDir: outDir, replacing: nil)
        radioCount += 1
        radioStatus = radioLibraryID == nil ? "" : "Generated \(radioCount) — writing the next song…"

        if library(libraryID)?.radioAutoplay == true, let s = song(songID) {
            if radioLibraryID == libraryID { radioDidRender(songID) }
            else if !isPlaying { play(s, queue: [s]) }   // one-off render with the station off
        }
        return songID
    }

    /// "Generate one now" from the library page.
    func generateOneForRadio(_ libraryID: UUID) {
        guard !isBusy else { return }
        radioError = nil
        Task {
            do { try await radioStep(libraryID) }
            catch { radioError = error.localizedDescription; errorMessage = error.localizedDescription }
            if radioLibraryID == nil { radioStatus = "" }
        }
    }

    // MARK: Generation

    private func specFromForm(source: String, library: UUID, category: String) -> GenerationSpec {
        GenerationSpec(
            title: title.isEmpty ? "Song" : title, idea: idea,
            style: style.trimmingCharacters(in: .whitespacesAndNewlines), lyrics: lyrics, mode: mode,
            seed: Int64(seedText.trimmingCharacters(in: .whitespaces)) ?? Int64.random(in: 1...9_999_999),
            odeSteps: fastDraft ? 8 : 32, source: source, library: library, category: category)
    }

    /// Renders a new song from the composer into the target library.
    func generate() {
        guard canGenerate else { return }
        let lib = resolvedTargetLibrary
        let spec = specFromForm(source: "manual", library: lib.id, category: LibraryIndex.uncategorized)
        let slug = Self.slugify(spec.title)
        let stamp = Self.stampFormatter.string(from: Date())
        startGeneration(spec: spec, outDir: outputRoot.appendingPathComponent("\(slug)-\(stamp)"), replacing: nil, completion: nil)
    }

    /// Re-renders from the composer and swaps the result in for `song`, keeping its
    /// library id, placement and playlist membership.
    func regenerate(replacing song: Song) {
        guard canGenerate else { return }
        let p = index.placement(for: song.id)
        let spec = specFromForm(source: "manual", library: p.library, category: p.category)
        let stamp = Self.stampFormatter.string(from: Date())
        let tmp = outputRoot.appendingPathComponent(".regen-\(song.id)-\(stamp)")
        startGeneration(spec: spec, outDir: tmp, replacing: song, completion: nil)
    }

    private func generateAsync(spec: GenerationSpec, outDir: URL, replacing: Song?) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            startGeneration(spec: spec, outDir: outDir, replacing: replacing) { cont.resume(with: $0) }
        }
    }

    private func startGeneration(spec: GenerationSpec, outDir: URL, replacing: Song?,
                                 completion: ((Result<String, Error>) -> Void)?) {
        errorMessage = nil
        log = ""
        stageText = replacing == nil ? "Starting…" : "Regenerating \(replacing!.title)…"
        progress = nil
        isGenerating = true
        renderingTitle = spec.title
        pendingOutputDir = outDir
        pendingSpec = spec
        replacingSong = replacing
        generationCompletion = completion

        let request: [String: Any] = [
            "id": Self.slugify(spec.title),
            "style": spec.style,
            "lyrics": spec.lyrics,
            "cot": spec.mode.rawValue,
            "seed": spec.seed,
            "generation_config": ["ode_steps": spec.odeSteps],
        ]
        let requestURL = outputRoot.appendingPathComponent(".requests/\(outDir.lastPathComponent).json")
        do {
            try FileManager.default.createDirectory(at: requestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: request, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: requestURL)
        } catch {
            finish(success: false, message: "Could not write request: \(error.localizedDescription)")
            return
        }

        var args = [
            "-m", "lyra.cli", "generate", requestURL.path,
            "--model", modelDir.path,
            "--vae", vaeDir.path,
            "--precision", "8bit",
            "--offline",
            "--vae-core-frames", "128",
            "--output", outDir.path,
        ]
        if !allowBattery { args.append("--require-ac") }

        let proc = Process()
        proc.executableURL = pythonURL
        proc.arguments = args
        proc.currentDirectoryURL = projectDir
        var env = ProcessInfo.processInfo.environment
        env["MLX_ENABLE_TF32"] = "0"
        env["HF_HUB_OFFLINE"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        var buffer = ""
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            buffer += chunk
            var lines: [String] = []
            while let range = buffer.rangeOfCharacter(from: CharacterSet(charactersIn: "\n\r")) {
                lines.append(String(buffer[..<range.lowerBound]))
                buffer = String(buffer[range.upperBound...])
            }
            if lines.isEmpty { return }
            DispatchQueue.main.async { lines.forEach { self.handle(line: $0) } }
        }
        proc.terminationHandler = { p in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                if !buffer.isEmpty { self.handle(line: buffer) }
                let ok = p.terminationStatus == 0
                let audioExists = FileManager.default.fileExists(atPath: outDir.appendingPathComponent("audio.flac").path)
                self.finish(success: ok && audioExists, message: ok ? nil : self.lastErrorLine())
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            finish(success: false, message: "Could not start Python: \(error.localizedDescription)")
        }
    }

    /// Cancels the render (and the station with it — otherwise it would immediately
    /// start writing another song). Use `setRadio(false:)` to stop the station alone.
    func cancel() {
        if let id = radioLibraryID { setRadio(false, for: id) }
        radioWindingDown = nil
        radioStatus = ""
        process?.terminate()
        claudeProcess?.terminate()
        stageText = "Cancelling…"
    }

    private func handle(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        log += trimmed + "\n"
        guard trimmed.hasPrefix("[YuE2]") else { return }
        let text = trimmed.dropFirst("[YuE2]".count).trimmingCharacters(in: .whitespaces)
        stageText = (pendingSpec?.source == "radio" ? "Radio · " : "") + text

        var pct: Double? = nil
        if let m = Self.percentRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(m.range(at: 1), in: text), let v = Double(text[r]) {
            pct = v / 100
        }
        if text.contains("Planning score") { progress = 0.05 }
        else if text.contains("Generating song") { progress = 0.15 }
        else if text.contains("Synthesizing audio") { progress = 0.2 + 0.75 * (pct ?? 0) }
        else if text.contains("Decoding audio") { progress = 0.95 + 0.05 * (pct ?? 0) }
        else if text.hasPrefix("Completed:") { progress = 1 }
    }

    private func lastErrorLine() -> String {
        let lines = log.split(separator: "\n").map(String.init)
        if let err = lines.last(where: { $0.contains("Error") || $0.contains("error:") }) { return err }
        return lines.suffix(3).joined(separator: "\n")
    }

    private func finish(success: Bool, message: String?) {
        isGenerating = false
        renderingTitle = nil
        process = nil
        progress = success ? 1 : nil
        let completion = generationCompletion
        let spec = pendingSpec
        let isRadio = spec?.source == "radio"
        defer { pendingOutputDir = nil; pendingSpec = nil; replacingSong = nil; generationCompletion = nil }

        guard success, let newDir = pendingOutputDir, let spec else {
            stageText = "Failed"
            let msg = message ?? "Generation failed."
            if isRadio { radioError = msg } else { errorMessage = msg }
            if let dir = pendingOutputDir { try? FileManager.default.removeItem(at: dir) }
            completion?(.failure(ClaudeCLI.Failure(message: msg)))
            return
        }

        spec.meta.save(to: newDir)

        var finalID = newDir.lastPathComponent
        if let old = replacingSong {
            if nowPlayingID == old.id { stop() }
            let fm = FileManager.default
            try? fm.trashItem(at: old.directory, resultingItemURL: nil)
            for suffix in [".resources.json", ".resources.jsonl"] {
                try? fm.trashItem(at: outputRoot.appendingPathComponent(old.id + suffix), resultingItemURL: nil)
            }
            do {
                try fm.moveItem(at: newDir, to: old.directory)
                for suffix in [".resources.json", ".resources.jsonl"] {
                    let side = outputRoot.appendingPathComponent(newDir.lastPathComponent + suffix)
                    if fm.fileExists(atPath: side.path) {
                        try? fm.moveItem(at: side, to: outputRoot.appendingPathComponent(old.id + suffix))
                    }
                }
                finalID = old.id
            } catch {
                errorMessage = "Rendered, but could not replace the old song: \(error.localizedDescription)"
            }
        }
        index.placements[finalID] = SongPlacement(library: spec.library, category: spec.category)
        saveIndex()
        stageText = isRadio ? "Radio · done" : "Done"
        refreshLibrary()
        if !isRadio { selection = .song(finalID) }
        NSSound(named: "Glass")?.play()
        completion?(.success(finalID))
    }

    // MARK: Playback

    func isPlaying(_ song: Song) -> Bool { isPlaying && nowPlayingID == song.id }

    func togglePlay(_ song: Song) {
        if isPlaying(song) { stop(); return }
        play(song, queue: [song])
    }

    func playAll(_ list: [Song], from start: Int = 0) {
        guard start < list.count else { return }
        play(list[start], queue: list, index: start)
    }

    private func play(_ song: Song, queue: [Song], index: Int = 0) {
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: song.audioURL)
            p.prepareToPlay()
            p.play()
            player = p
            self.queue = queue
            queueIndex = index
            nowPlayingID = song.id
            playbackDuration = p.duration
            playbackPosition = 0
            isPlaying = true
            isPaused = false
            // Follow playback in the sidebar, except on a playlist page, an on-air radio page, or while editing.
            if editingSongID == nil {
                switch selection {
                case .playlist: break
                case .library(let id) where isRadioOn(id): break
                default: selection = .song(song.id)
                }
            }
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.tick() }
            }
        } catch {
            errorMessage = "Could not play: \(error.localizedDescription)"
        }
    }

    /// Moves on when a track ends or is skipped; an on-air station picks its own next track.
    private func advanceQueue() {
        let next = queueIndex + 1
        if next < queue.count { play(queue[next], queue: queue, index: next) }
        else if radioAutoplayOn { radioPlayNext() }
        else { stop() }
    }

    func togglePause() {
        guard let p = player else { return }
        if isPaused { p.play(); isPaused = false } else { p.pause(); isPaused = true }
    }

    private func tick() {
        guard let p = player else { return }
        playbackPosition = p.currentTime
        guard !isPaused else { return }
        if !p.isPlaying { advanceQueue() }
    }

    func playNext() { advanceQueue() }

    func playPrevious() {
        let prev = queueIndex - 1
        if prev >= 0 { play(queue[prev], queue: queue, index: prev) }
    }

    func stop() {
        player?.stop()
        player = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        isPlaying = false
        isPaused = false
        nowPlayingID = nil
        playbackPosition = 0
    }

    func seek(to time: TimeInterval) {
        guard let p = player else { return }
        p.currentTime = max(0, min(time, p.duration))
        playbackPosition = p.currentTime
    }

    /// Plays a song with the rest of its library queued after it.
    func playInLibrary(_ song: Song) {
        let list = Array(songs(in: index.placement(for: song.id).library).reversed())  // oldest → newest
        if let i = list.firstIndex(where: { $0.id == song.id }) { play(list[i], queue: list, index: i) }
        else { play(song, queue: [song]) }
    }

    func beginEditing(_ song: Song) {
        loadIntoForm(song)
        selection = .song(song.id)
        editingSongID = song.id
    }

    /// Opens a blank composer. Previous songs keep their details in studio.json, so nothing is lost.
    func newSong() {
        editingSongID = nil
        selection = nil
        idea = ""
        title = ""
        style = ""
        lyrics = ""
        seedText = ""
        mode = .full
        fastDraft = false
        if !isBusy { stageText = ""; progress = nil; errorMessage = nil }
    }

    var composerIsBlank: Bool {
        [idea, title, style, lyrics, seedText].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: Song actions

    func revealInFinder(_ song: Song) {
        NSWorkspace.shared.activateFileViewerSelecting([song.audioURL])
    }

    /// `~/Music/Tunesmith`, falling back to the pre-rename folder when that's where the songs are.
    nonisolated static func defaultOutputRoot(home: URL) -> URL {
        let new = home.appendingPathComponent("Music/Tunesmith")
        let legacy = home.appendingPathComponent("Music/YuE2 Studio")
        let fm = FileManager.default
        if !fm.fileExists(atPath: new.path), fm.fileExists(atPath: legacy.path) { return legacy }
        return new
    }

    nonisolated static let ffmpegPath = "/opt/homebrew/bin/ffmpeg"

    /// Transcodes FLAC → AAC M4A. Blocks until ffmpeg exits.
    nonisolated static func transcodeM4A(from source: URL, to dest: URL) throws {
        guard FileManager.default.fileExists(atPath: ffmpegPath) else {
            throw ClaudeCLI.Failure(message: "ffmpeg not found at \(ffmpegPath) (brew install ffmpeg).")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpegPath)
        proc.arguments = ["-v", "error", "-y", "-i", source.path, "-c:a", "aac", "-b:a", "256k", dest.path]
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 { throw ClaudeCLI.Failure(message: "ffmpeg export failed.") }
    }

    func exportM4A(_ song: Song) {
        guard FileManager.default.fileExists(atPath: Self.ffmpegPath) else {
            errorMessage = "ffmpeg not found at \(Self.ffmpegPath) (brew install ffmpeg)."; return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(song.title).m4a"
        panel.allowedContentTypes = [.mpeg4Audio]
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do { try Self.transcodeM4A(from: song.audioURL, to: dest) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Emails the song (as M4A, with its style and optionally lyrics) through Remail.
    /// Returns the Remail message id.
    func shareByEmail(_ song: Song, to recipients: [String], message: String, includeLyrics: Bool) async throws -> String {
        let client = RemailClient(apiKey: remailAPIKey)
        let from = remailFrom.trimmingCharacters(in: .whitespaces)
        let replyTo = remailReplyTo.trimmingCharacters(in: .whitespaces)
        let note = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lyrics = includeLyrics ? lyrics(for: song).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let filename = song.title.replacingOccurrences(of: "/", with: "-") + ".m4a"

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let source = song.audioURL
        let audio = try await Task.detached {
            try Self.transcodeM4A(from: source, to: tmp)
            return try Data(contentsOf: tmp)
        }.value
        guard audio.count <= RemailClient.maxAttachmentBytes else {
            throw ClaudeCLI.Failure(message: "“\(song.title)” is too large to email (\(audio.count / 1_048_576) MB after conversion).")
        }

        var text = ""
        if !note.isEmpty { text += note + "\n\n" }
        text += "“\(song.title)”\n\(song.style)\n\nThe song is attached (\(filename))."
        if !lyrics.isEmpty { text += "\n\nLyrics\n\n\(lyrics)" }
        text += "\n\n—\nMade with Song Studio"

        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var html = #"<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:560px;color:#222;line-height:1.5">"#
        if !note.isEmpty { html += #"<p style="white-space:pre-wrap">\#(esc(note))</p>"# }
        html += #"<h2 style="margin:24px 0 4px">\#(esc(song.title))</h2>"#
        html += #"<p style="margin:0 0 16px;color:#666">\#(esc(song.style))</p>"#
        html += #"<p>🎧 The song is attached as <b>\#(esc(filename))</b>.</p>"#
        if !lyrics.isEmpty {
            html += #"<h3 style="margin:24px 0 8px">Lyrics</h3><pre style="white-space:pre-wrap;font-family:inherit;margin:0">\#(esc(lyrics))</pre>"#
        }
        html += #"<p style="margin-top:32px;color:#999;font-size:12px">Made with Song Studio</p></div>"#

        return try await client.send(
            from: from.isEmpty ? Self.defaultRemailFrom : from, to: recipients,
            replyTo: replyTo.isEmpty ? nil : replyTo, subject: "“\(song.title)” — a song for you",
            text: text, html: html,
            attachments: [.init(filename: filename, data: audio, contentType: "audio/mp4")])
    }

    func lyrics(for song: Song) -> String {
        if let meta = StudioMeta.load(from: song.directory) { return meta.lyrics }
        guard let data = try? Data(contentsOf: song.directory.appendingPathComponent("request.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return (json["lyrics"] as? String) ?? ""
    }

    func deleteSong(_ song: Song) {
        if nowPlayingID == song.id { stop() }
        try? FileManager.default.trashItem(at: song.directory, resultingItemURL: nil)
        for suffix in [".resources.json", ".resources.jsonl"] {
            try? FileManager.default.trashItem(at: outputRoot.appendingPathComponent(song.id + suffix), resultingItemURL: nil)
        }
        index.placements[song.id] = nil
        for i in index.playlists.indices { index.playlists[i].songIDs.removeAll { $0 == song.id } }
        saveIndex()
        if selectedSongID == song.id { selection = nil }
        refreshLibrary()
    }

    /// Restores everything that produced this song into the composer.
    func loadIntoForm(_ song: Song) {
        targetLibraryID = index.placement(for: song.id).library
        if let meta = StudioMeta.load(from: song.directory) {
            title = meta.title
            idea = meta.idea.hasPrefix("Radio: ") ? "" : meta.idea
            style = meta.style
            lyrics = meta.lyrics
            seedText = "\(meta.seed)"
            mode = SongMode(rawValue: meta.mode) ?? .full
            fastDraft = meta.odeSteps <= 8
            return
        }
        guard let data = try? Data(contentsOf: song.directory.appendingPathComponent("request.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        title = (json["id"] as? String) ?? song.title
        style = (json["style"] as? String) ?? ""
        lyrics = (json["lyrics"] as? String) ?? ""
        if let s = json["seed"] { seedText = "\(s)" }
        if let cot = json["cot"] as? String, let m = SongMode(rawValue: cot) { mode = m }
    }

    // MARK: Lyrics find & replace

    func countMatches(_ find: String, caseSensitive: Bool) -> Int {
        guard !find.isEmpty else { return 0 }
        var count = 0
        var rest = lyrics[...]
        while let r = rest.range(of: find, options: caseSensitive ? [] : [.caseInsensitive]) {
            count += 1
            rest = rest[r.upperBound...]
        }
        return count
    }

    func replaceAll(_ find: String, with replacement: String, caseSensitive: Bool) {
        guard !find.isEmpty else { return }
        lyrics = lyrics.replacingOccurrences(of: find, with: replacement, options: caseSensitive ? [] : [.caseInsensitive])
    }

    // MARK: Helpers

    static func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        var lastDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber { out.append(ch); lastDash = false }
            else if !lastDash { out.append("-"); lastDash = true }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "song" : String(trimmed.prefix(40))
    }

    static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    static let percentRegex = try! NSRegularExpression(pattern: #"\((\d+)%\)"#)
}
