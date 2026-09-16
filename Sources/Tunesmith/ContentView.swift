import SwiftUI
import AVFoundation

struct ContentView: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        } detail: {
            VStack(spacing: 0) {
                if let problem = model.setupProblem {
                    Banner(text: problem, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
                if let playlist = model.selectedPlaylist {
                    PlaylistView(playlist: playlist)
                } else if let lib = model.selectedLibrary {
                    LibraryPage(library: lib)
                } else if let song = model.selectedSong, model.editingSongID != song.id {
                    SongPlayerView(song: song)
                } else {
                    if let song = model.selectedSong {
                        EditingHeader(song: song)
                        Divider()
                    }
                    ComposerView()
                    Divider()
                    StatusBar()
                    if let song = model.selectedSong {
                        Divider()
                        SongPanel(song: song)
                    }
                }
                if model.isPlaying, let np = model.nowPlayingID.flatMap(model.song),
                   !(model.selectedSongID == np.id && model.editingSongID == nil) {
                    Divider()
                    NowPlayingBar(song: np)
                }
            }
        }
        .sheet(item: $model.sharingSong) { song in ShareEmailSheet(song: song) }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Sidebar: Library › Category › Song, then Playlists

struct SidebarView: View {
    @Environment(StudioModel.self) private var model
    @State private var newName = ""
    @State private var categoryTarget: UUID? = nil
    @State private var renameTarget: RenameTarget? = nil
    @State private var renameText = ""

    enum RenameTarget: Identifiable {
        case library(UUID), category(UUID, String), playlist(UUID)
        var id: String {
            switch self {
            case .library(let id): return "l:\(id)"
            case .category(let l, let n): return "c:\(l):\(n)"
            case .playlist(let id): return "p:\(id)"
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Libraries") {
                ForEach(model.libraries) { lib in
                    DisclosureGroup {
                        ForEach(lib.categories, id: \.self) { category in
                            let items = model.songs(in: lib.id, category: category)
                            DisclosureGroup {
                                if items.isEmpty {
                                    Text("Empty").font(.caption).foregroundStyle(.tertiary)
                                }
                                ForEach(items) { song in
                                    SongRow(song: song)
                                        .tag(SidebarSelection.song(song.id))
                                        .contextMenu { SongContextMenu(song: song) }
                                }
                            } label: {
                                Label {
                                    HStack {
                                        Text(category)
                                        Spacer()
                                        Text("\(items.count)").font(.caption).foregroundStyle(.tertiary)
                                    }
                                } icon: { Image(systemName: "folder") }
                            }
                            .contextMenu {
                                Button("Shuffle") { model.playShuffled(items) }
                                    .disabled(items.isEmpty)
                                if category != LibraryIndex.uncategorized {
                                    Button("Rename…") { renameText = category; renameTarget = .category(lib.id, category) }
                                    Button("Delete category", role: .destructive) { model.deleteCategory(category, in: lib.id) }
                                }
                            }
                        }
                    } label: {
                        Label {
                            HStack {
                                Text(lib.name).fontWeight(.semibold)
                                if model.isRadioOn(lib.id) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .foregroundStyle(.red).symbolEffect(.variableColor.iterative, isActive: true)
                                }
                                Spacer()
                                Text("\(model.songs(in: lib.id).count)").font(.caption).foregroundStyle(.tertiary)
                            }
                        } icon: { Image(systemName: "books.vertical") }
                        .tag(SidebarSelection.library(lib.id))
                    }
                    .tag(SidebarSelection.library(lib.id))
                    .contextMenu {
                        Button("Open library page") { model.selection = .library(lib.id) }
                        Button("Shuffle") { model.playShuffled(model.songs(in: lib.id)) }
                        Button("New Category…") { newName = ""; categoryTarget = lib.id; model.askNewCategory = true }
                        Button("Rename…") { renameText = lib.name; renameTarget = .library(lib.id) }
                        Divider()
                        Button(model.isRadioOn(lib.id) ? "Stop radio" : "Start radio") { model.setRadio(!model.isRadioOn(lib.id), for: lib.id) }
                        Divider()
                        Button("Delete library", role: .destructive) { model.deleteLibrary(lib.id) }
                            .disabled(model.libraries.count < 2)
                    }
                }
            }
            Section("Playlists") {
                if model.index.playlists.isEmpty {
                    Text("No playlists yet.").font(.caption).foregroundStyle(.tertiary)
                }
                ForEach(model.index.playlists) { playlist in
                    Label(playlist.name, systemImage: "music.note.list")
                        .badge(playlist.songIDs.count)
                        .tag(SidebarSelection.playlist(playlist.id))
                        .contextMenu {
                            Button("Play") { model.playAll(model.songs(in: playlist)) }
                            Button("Shuffle") { model.playShuffled(model.songs(in: playlist)) }
                            Button("Rename…") { renameText = playlist.name; renameTarget = .playlist(playlist.id) }
                            Divider()
                            Button("Delete playlist", role: .destructive) { model.deletePlaylist(playlist.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button { model.newSong() } label: { Label("New Song", systemImage: "square.and.pencil") }
                    .help("Start a new song in a blank composer (⌘N)")
            }
            ToolbarItem {
                Menu {
                    Button("New Library…") { newName = ""; model.askNewLibrary = true }
                    Button("New Category…") {
                        newName = ""
                        categoryTarget = model.selectedLibrary?.id ?? model.selectedSong.map { model.index.placement(for: $0.id).library } ?? model.libraries[0].id
                        model.askNewCategory = true
                    }
                    Button("New Playlist…") { newName = ""; model.askNewPlaylist = true }
                    Divider()
                    Button("Refresh") { model.refreshLibrary() }
                } label: { Label("Add", systemImage: "plus") }
            }
        }
        .alert("New library", isPresented: $model.askNewLibrary) {
            TextField("Name", text: $newName)
            Button("Create") { if let l = model.addLibrary(newName) { model.selection = .library(l.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You can add a description and turn on radio from the library page.") }
        .alert("New category", isPresented: $model.askNewCategory) {
            TextField("Name", text: $newName)
            Button("Create") {
                let target = categoryTarget ?? model.selectedLibrary?.id ?? model.libraries[0].id
                model.addCategory(newName, to: target)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("In “\((categoryTarget ?? model.selectedLibrary?.id).flatMap(model.library)?.name ?? model.libraries[0].name)”")
        }
        .alert("New playlist", isPresented: $model.askNewPlaylist) {
            TextField("Name", text: $newName)
            Button("Create") { if let p = model.addPlaylist(newName) { model.selection = .playlist(p.id) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                switch renameTarget {
                case .library(let id):
                    if var l = model.library(id) { l.name = renameText.trimmingCharacters(in: .whitespaces); if !l.name.isEmpty { model.updateLibrary(l) } }
                case .category(let lib, let old): model.renameCategory(old, to: renameText, in: lib)
                case .playlist(let id): model.renamePlaylist(id, to: renameText)
                case nil: break
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }
}

struct SongRow: View {
    @Environment(StudioModel.self) private var model
    let song: Song

    var body: some View {
        let playing = model.isPlaying(song)
        HStack(spacing: 8) {
            SongTile(song: song, size: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).fontWeight(playing ? .semibold : .regular).lineLimit(1)
                Text(song.created.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SongContextMenu: View {
    @Environment(StudioModel.self) private var model
    let song: Song

    var body: some View {
        let placement = model.index.placement(for: song.id)
        Button(model.isPlaying(song) ? "Stop" : "Play") { model.togglePlay(song) }
        Button("Edit generation details…") { model.beginEditing(song) }
        Menu("Move to category") {
            ForEach(model.library(placement.library)?.categories ?? [], id: \.self) { c in
                Button {
                    model.place(song, in: placement.library, category: c)
                } label: {
                    if placement.category == c { Label(c, systemImage: "checkmark") } else { Text(c) }
                }
            }
        }
        Menu("Move to library") {
            ForEach(model.libraries) { l in
                Button {
                    model.place(song, in: l.id, category: LibraryIndex.uncategorized)
                } label: {
                    if placement.library == l.id { Label(l.name, systemImage: "checkmark") } else { Text(l.name) }
                }
            }
        }
        Menu("Add to playlist") {
            if model.index.playlists.isEmpty { Text("No playlists") }
            ForEach(model.index.playlists) { p in
                Button(p.name) { model.add(song, to: p.id) }
            }
        }
        Divider()
        Button("Share via Email…") { model.sharingSong = song }
        Button("Reveal in Finder") { model.revealInFinder(song) }
        Button("Move to Trash", role: .destructive) { model.deleteSong(song) }
    }
}

// MARK: - Library page (summary, edit sheet, radio)

struct LibraryPage: View {
    @Environment(StudioModel.self) private var model
    let library: MusicLibrary
    @State private var showEdit = false

    var body: some View {
        let lib = model.library(library.id) ?? library
        if model.isRadioOn(lib.id) {
            RadioView(library: lib)
        } else {
            LibrarySummary(library: lib, showEdit: $showEdit)
                .sheet(isPresented: $showEdit) { LibraryEditSheet(libraryID: lib.id) }
        }
    }
}

struct LibrarySummary: View {
    @Environment(StudioModel.self) private var model
    let library: MusicLibrary
    @Binding var showEdit: Bool

    private var canRadio: Bool {
        model.claudeURL != nil && model.setupProblem == nil
            && !library.stationBrief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let lib = library
        let items = model.songs(in: lib.id)
        let cats = lib.categories.filter { $0 != LibraryIndex.uncategorized }
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Artwork(seed: lib.name, size: 66, glyph: "books.vertical.fill")
                VStack(alignment: .leading, spacing: 6) {
                    Text(lib.name).font(.title2.bold())
                    Text(lib.description.isEmpty ? "No description yet — press Edit to describe this library and enable radio." : lib.description)
                        .font(.callout).foregroundStyle(lib.description.isEmpty ? .tertiary : .secondary)
                        .lineLimit(4)
                    HStack(spacing: 6) {
                        StatChip(icon: "music.note", text: "\(items.count) song\(items.count == 1 ? "" : "s")")
                        StatChip(icon: "folder", text: "\(cats.count) categor\(cats.count == 1 ? "y" : "ies")")
                        if !lib.refinedDescription.isEmpty { StatChip(icon: "checkmark.seal", text: "Station brief ready") }
                    }
                    .padding(.top, 2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Button {
                        model.setRadio(true, for: lib.id)
                    } label: { Label("Start radio", systemImage: "dot.radiowaves.left.and.right") }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canRadio || model.isBusy)
                        .help(canRadio ? "Continuously write, render and file new songs for this library" : "Add a description (Edit) first")
                }
            }
            .padding(20)
            if model.radioWindingDown == lib.id {
                Divider()
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.radioStatus.isEmpty ? "Finishing the last song…" : model.radioStatus)
                            .font(.caption).lineLimit(1)
                        if let p = model.progress { ProgressView(value: p).frame(width: 220) }
                    }
                    Spacer()
                    Button("Cancel") { model.cancel() }.controlSize(.small)
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.quaternary.opacity(0.3))
            }
            Divider()
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No songs yet", systemImage: "music.note.list")
                } description: {
                    Text(canRadio ? "Start radio to fill this library automatically, or compose a song and save it here."
                                  : "Press Edit to describe the library, then start radio — or compose a song and save it here.")
                } actions: {
                    Button("Generate one song now") { model.generateOneForRadio(lib.id) }
                        .disabled(!canRadio || model.isBusy)
                }
            } else {
                List {
                    ForEach(lib.categories, id: \.self) { cat in
                        let rows = model.songs(in: lib.id, category: cat)
                        if !rows.isEmpty {
                            Section(cat) {
                                ForEach(rows) { song in LibrarySongRow(song: song, showCategory: false) }
                            }
                        }
                    }
                }
                HStack {
                    Button("Generate one song now") { model.generateOneForRadio(lib.id) }
                        .disabled(!canRadio || model.isBusy)
                    if model.isBusy, !model.radioStatus.isEmpty {
                        ProgressView().controlSize(.small)
                        Text(model.stageText.isEmpty ? model.radioStatus : model.stageText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { model.playShuffled(items) } label: { Label("Shuffle", systemImage: "shuffle") }
                        .disabled(items.isEmpty)
                        .help("Play everything in this library in a random order")
                    Button { model.playAll(items) } label: { Label("Play all", systemImage: "play.fill") }
                        .disabled(items.isEmpty)
                }
                .padding(12)
            }
        }
    }
}

struct LibrarySongRow: View {
    @Environment(StudioModel.self) private var model
    let song: Song
    var showCategory = true

    var body: some View {
        let playing = model.isPlaying(song)
        HStack(spacing: 12) {
            SongTile(song: song, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).fontWeight(playing ? .semibold : .regular).lineLimit(1)
                Text(song.style).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if showCategory {
                Text(model.index.placement(for: song.id).category).font(.caption).foregroundStyle(.tertiary)
            }
            Text(song.created.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            Button { model.togglePlay(song) } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.plain).foregroundStyle(playing ? Color.accentColor : .secondary)
        }
        .padding(.vertical, 3)
        .contextMenu { SongContextMenu(song: song) }
    }
}

struct LibraryEditSheet: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let libraryID: UUID

    var body: some View {
        let lib = model.library(libraryID) ?? MusicLibrary(name: "")
        VStack(spacing: 0) {
            Form {
                Section("Library") {
                    TextField("Name", text: Binding(get: { lib.name }, set: { var l = lib; l.name = $0; model.updateLibrary(l) }))
                }
                Section {
                    TextEditor(text: Binding(get: { lib.description }, set: { var l = lib; l.description = $0; model.updateLibrary(l) }))
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                    HStack {
                        Button {
                            model.refineStation(lib.id)
                        } label: {
                            if model.isRefiningStation { ProgressView().controlSize(.small).padding(.trailing, 4) }
                            Text(lib.refinedDescription.isEmpty ? "Refine description" : "Refine again")
                        }
                        .disabled(model.isRefiningStation || model.claudeURL == nil || lib.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        Text("Claude turns this into a station brief the radio writes from.").font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Description") } footer: {
                    Text("Genres, moods, instruments, vocal styles, lyric themes, languages, what to avoid.")
                }
                if !lib.refinedDescription.isEmpty {
                    Section {
                        TextEditor(text: Binding(get: { lib.refinedDescription }, set: { var l = lib; l.refinedDescription = $0; model.updateLibrary(l) }))
                            .font(.callout)
                            .frame(minHeight: 160)
                            .scrollContentBackground(.hidden)
                    } header: { Text("Station brief") } footer: {
                        Text("Editable. The radio uses this instead of the description when it exists.")
                    }
                }
                Section("Radio options") {
                    Toggle("Fast drafts (8 steps, ~2× faster, lower quality)", isOn: Binding(get: { lib.radioFastDrafts }, set: { var l = lib; l.radioFastDrafts = $0; model.updateLibrary(l) }))
                    Toggle("Keep the station playing (new songs on air as they finish, library songs in between)",
                           isOn: Binding(get: { lib.radioAutoplay }, set: { var l = lib; l.radioAutoplay = $0; model.updateLibrary(l) }))
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 640, height: 620)
    }
}

// MARK: - Radio (on air) view

struct RadioView: View {
    @Environment(StudioModel.self) private var model
    let library: MusicLibrary
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var nowPlaying: Song? { model.nowPlayingID.flatMap(model.song) }
    private var isLive: Bool { model.isPlaying && !model.isPaused }

    var body: some View {
        let items = model.songs(in: library.id)
        VStack(spacing: 0) {
            header(items)
            Divider()
            deck(items)
            if let err = model.radioError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20).padding(.vertical, 7)
                    .background(.orange.opacity(0.1))
            }
            Divider()
            if items.isEmpty {
                ContentUnavailableView("No songs yet", systemImage: "music.note.list",
                                       description: Text("The first song goes on the air as soon as it's rendered."))
            } else {
                List(items) { song in LibrarySongRow(song: song) }
            }
        }
    }

    // MARK: Header

    private func header(_ items: [Song]) -> some View {
        let lib = library
        let cats = max(0, lib.categories.count - 1)
        return HStack(spacing: 16) {
            Artwork(seed: lib.name, size: 66, glyph: "dot.radiowaves.left.and.right", playing: isLive)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    OnAirPill()
                    Text(lib.name).font(.title2.bold())
                }
                HStack(spacing: 6) {
                    StatChip(icon: "waveform.badge.plus", text: "\(model.radioCount) this session")
                    StatChip(icon: "music.note", text: "\(items.count) in library")
                    StatChip(icon: "folder", text: "\(cats) categor\(cats == 1 ? "y" : "ies")")
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Toggle("Auto-play", isOn: Binding(get: { lib.radioAutoplay },
                                                  set: { var l = lib; l.radioAutoplay = $0; model.updateLibrary(l) }))
                    .toggleStyle(.switch).controlSize(.small)
                    .help("Keeps the station playing: new songs go on air as they finish, library songs fill the gaps")
                Button(role: .destructive) {
                    model.setRadio(false, for: lib.id)
                } label: { Label("Stop radio", systemImage: "stop.fill") }
                    .help("Stops writing new songs. Anything already rendering finishes and is filed.")
            }
        }
        .padding(20)
        .background(backdrop)
    }

    private var backdrop: some View {
        let h = Double(stableHash(library.name) % 1000) / 1000
        return LinearGradient(colors: [Color(hue: h, saturation: 0.45, brightness: 0.75).opacity(0.22),
                                       Color(hue: h, saturation: 0.45, brightness: 0.75).opacity(0.02)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Deck

    private func deck(_ items: [Song]) -> some View {
        HStack(alignment: .top, spacing: 18) {
            nowPlayingPane(items)
            Divider().frame(height: 118)
            upNextPane().frame(width: 235, height: 118, alignment: .topLeading)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(.quaternary.opacity(0.22))
    }

    private func nowPlayingPane(_ items: [Song]) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                Artwork(seed: nowPlaying?.id ?? library.name + "-idle", size: 118,
                        glyph: nowPlaying == nil ? "music.note" : "waveform", playing: isLive)
                if nowPlaying != nil {
                    EQBars(bars: 5, active: isLive, height: 20)
                        .padding(7)
                        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                if let s = nowPlaying {
                    Text(s.title).font(.title3.bold()).lineLimit(1)
                    Text(s.style).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).frame(height: 26, alignment: .top)
                } else {
                    Text(items.isEmpty ? "Waiting for the first song…" : "Nothing playing")
                        .font(.title3.bold()).foregroundStyle(.secondary)
                    Text(library.radioAutoplay ? "New songs go on air as they finish; library songs fill the gaps."
                                               : "Turn on Auto-play, or press play.")
                        .font(.caption).foregroundStyle(.tertiary)
                        .lineLimit(2).frame(height: 26, alignment: .top)
                }
                scrubber
                transport(items)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scrubber: some View {
        let live = nowPlaying != nil
        return HStack(spacing: 9) {
            Text(fmt(live ? (scrubbing ? scrubValue : model.playbackPosition) : 0))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
            Slider(value: Binding(get: { scrubbing ? scrubValue : (live ? model.playbackPosition : 0) },
                                  set: { scrubValue = $0 }),
                   in: 0...max(model.playbackDuration, 1)) { editing in
                scrubbing = editing
                if !editing { model.seek(to: scrubValue) }
            }
            .disabled(!live)
            Text(fmt(live ? model.playbackDuration : 0))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
        }
    }

    private func transport(_ items: [Song]) -> some View {
        HStack(spacing: 16) {
            Button { model.playPrevious() } label: { Image(systemName: "backward.fill") }
                .buttonStyle(.plain).disabled(nowPlaying == nil)
            Button {
                if nowPlaying != nil { model.togglePause() } else { model.playAll(items) }
            } label: {
                Image(systemName: (nowPlaying == nil || model.isPaused) ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 34))
            }
            .buttonStyle(.plain).foregroundStyle(.tint).disabled(items.isEmpty)
            Button { model.playNext() } label: { Image(systemName: "forward.fill") }
                .buttonStyle(.plain).disabled(nowPlaying == nil)
                .help("Skip — airs the new song if one is ready, otherwise another from the library")
            if nowPlaying != nil, model.isPaused {
                Text("Paused").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Up next

    @ViewBuilder
    private func upNextPane() -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("UP NEXT").font(.caption2.bold()).tracking(1.1).foregroundStyle(.tertiary)
            if let up = model.radioUpNext {
                HStack(spacing: 10) {
                    Artwork(seed: up.id, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NEW").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.green, in: Capsule())
                        Text(up.title).font(.callout.weight(.semibold)).lineLimit(2)
                    }
                }
                Text(model.isPlaying ? "Goes on air when this song ends." : "Starting…")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else if model.isBusy {
                Text(model.renderingTitle ?? "Writing the next song…")
                    .font(.callout.weight(.semibold)).lineLimit(2)
                RenderingMeter(progress: model.progress, active: true)
                Text(model.stageText.isEmpty ? model.radioStatus : model.stageText)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text(model.radioStatus.isEmpty ? "Cueing up the next song…" : model.radioStatus)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func fmt(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Visual bits

/// FNV-1a: stable across launches, unlike Swift's per-process seeded hashValue.
func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
    return h
}

/// Deterministic cover art: a gradient tile with record grooves, seeded by the song id.
struct Artwork: View {
    let seed: String
    var size: CGFloat = 56
    var glyph = "music.note"
    var playing = false

    var body: some View {
        let h = Double(stableHash(seed) % 1000) / 1000
        let c1 = Color(hue: h, saturation: 0.5, brightness: 0.86)
        let c2 = Color(hue: (h + 0.14).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.44)
        let shape = RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                ZStack {
                    ForEach(1...3, id: \.self) { i in
                        Circle()
                            .strokeBorder(.white.opacity(0.13), lineWidth: max(1, size * 0.015))
                            .frame(width: size * (0.3 + 0.24 * Double(i)))
                    }
                    Image(systemName: glyph)
                        .font(.system(size: size * 0.26, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.25), radius: size * 0.03)
                }
            }
            .overlay(shape.strokeBorder(.white.opacity(0.16)))
            .shadow(color: .black.opacity(0.2), radius: size * 0.05, y: size * 0.02)
    }
}

/// A song's artwork, with a live meter over it while that song is playing.
struct SongTile: View {
    @Environment(StudioModel.self) private var model
    let song: Song
    var size: CGFloat = 32
    var bars = 3

    var body: some View {
        ZStack {
            Artwork(seed: song.id, size: size,
                    glyph: song.source == "radio" ? "dot.radiowaves.left.and.right" : "music.note")
            if model.isPlaying(song) {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous).fill(.black.opacity(0.38))
                EQBars(bars: bars, active: !model.isPaused, height: size * 0.4)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Little animated level meter. Frozen (and not redrawing) when `active` is false.
struct EQBars: View {
    var bars = 4
    var active = true
    var height: CGFloat = 16
    var tint: Color = .white

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2.5) {
                ForEach(0..<bars, id: \.self) { i in
                    let wobble = abs(sin(t * (1.9 + Double(i) * 0.41) + Double(i) * 1.7))
                    let f = active ? 0.22 + 0.78 * wobble : 0.22
                    Capsule().fill(tint).frame(width: 3, height: max(2, height * f))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
    }
}

/// Pulsing ON AIR badge.
struct OnAirPill: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 6, height: 6)
                .phaseAnimator([0.2, 1.0]) { dot, p in dot.opacity(p) } animation: { _ in .easeInOut(duration: 0.85) }
            Text("ON AIR").font(.caption.bold()).foregroundStyle(.white)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.red, in: Capsule())
    }
}

struct StatChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption).foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

/// Render progress as a strip of bars; shimmers while the step has no percentage yet.
struct RenderingMeter: View {
    var progress: Double?
    var active = true
    private let count = 20

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    let x = Double(i) / Double(count - 1)
                    let lit = progress.map { x <= $0 } ?? (abs(sin(t * 1.3 - x * 3.0)) > 0.62)
                    let h = 5 + 13 * abs(sin(t * 2.1 + Double(i) * 0.55))
                    Capsule()
                        .fill(lit ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(height: lit ? h : 5)
                }
            }
            .frame(height: 18, alignment: .bottom)
        }
    }
}


// MARK: - Song player page

struct EditingHeader: View {
    @Environment(StudioModel.self) private var model
    let song: Song

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil").foregroundStyle(.tint)
            Text("Editing “\(song.title)”").font(.headline)
            Text("Change anything below, then Regenerate… to replace this song, or Generate to make a new one.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Done") { model.editingSongID = nil }.keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.bar)
    }
}

struct SongPlayerView: View {
    @Environment(StudioModel.self) private var model
    let song: Song
    @State private var showScore = false
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        let p = model.index.placement(for: song.id)
        let meta = StudioMeta.load(from: song.directory)
        let playing = model.isPlaying(song)
        let duration = playing ? model.playbackDuration : (meta.map { _ in cachedDuration } ?? cachedDuration)
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top, spacing: 16) {
                SongTile(song: song, size: 92, bars: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title).font(.title2.bold())
                    Text(song.style).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 6) {
                        StatChip(icon: "folder", text: "\(model.library(p.library)?.name ?? "") › \(p.category)")
                        if song.source == "radio" { StatChip(icon: "dot.radiowaves.left.and.right", text: "radio") }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 6) {
                        if let m = meta {
                            StatChip(icon: "slider.horizontal.3",
                                     text: m.mode == "off" ? "Direct" : (m.mode == "melody" ? "Melody" : "Full score"))
                            StatChip(icon: m.odeSteps <= 8 ? "bolt" : "sparkles",
                                     text: m.odeSteps <= 8 ? "Fast draft" : "Standard quality")
                            StatChip(icon: "number", text: String(m.seed))
                        }
                        StatChip(icon: "calendar", text: song.created.formatted(date: .abbreviated, time: .shortened))
                        Spacer(minLength: 0)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button { model.beginEditing(song) } label: { Label("Edit", systemImage: "pencil") }
                        .help("Open the generation details (idea, style, lyrics, settings) to change and regenerate")
                    HStack {
                        Button { model.sharingSong = song } label: { Label("Share", systemImage: "envelope") }
                            .help("Email this song")
                        Button("Export M4A…") { model.exportM4A(song) }
                        Button("Score") { showScore = true }
                            .disabled(!FileManager.default.fileExists(atPath: song.scoreURL.path))
                        Button { model.revealInFinder(song) } label: { Image(systemName: "folder") }
                            .help("Reveal in Finder")
                    }
                }
            }
            .padding(20)

            // Transport + timeline
            VStack(spacing: 8) {
                HStack(spacing: 18) {
                    Button { model.playPrevious() } label: { Image(systemName: "backward.fill").font(.title3) }
                        .buttonStyle(.plain).disabled(!playing)
                    Button {
                        if playing { model.togglePause() } else { model.playInLibrary(song) }
                    } label: {
                        Image(systemName: playing && !model.isPaused ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                    }
                    .buttonStyle(.plain).foregroundStyle(.tint)
                    Button { model.playNext() } label: { Image(systemName: "forward.fill").font(.title3) }
                        .buttonStyle(.plain).disabled(!playing)
                    Button { model.stop() } label: { Image(systemName: "stop.fill").font(.title3) }
                        .buttonStyle(.plain).disabled(!playing)
                    Button { model.shuffleQueue() } label: { Image(systemName: "shuffle").font(.title3) }
                        .buttonStyle(.plain).disabled(!model.canShuffleQueue)
                        .help("Shuffle the songs still to come")
                    Spacer()
                    if playing, model.isPaused { Text("Paused").font(.caption).foregroundStyle(.secondary) }
                }
                HStack(spacing: 10) {
                    Text(fmt(playing ? (scrubbing ? scrubValue : model.playbackPosition) : 0))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { scrubbing ? scrubValue : (playing ? model.playbackPosition : 0) },
                            set: { scrubValue = $0 }
                        ),
                        in: 0...max(duration, 1),
                        onEditingChanged: { editing in
                            scrubbing = editing
                            if !editing {
                                if playing { model.seek(to: scrubValue) }
                                else { model.playInLibrary(song); model.seek(to: scrubValue) }
                            }
                        }
                    )
                    Text(fmt(duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)

            Divider()

            // Lyrics / idea
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let m = meta, !m.idea.isEmpty, !m.idea.hasPrefix("Radio: ") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Idea").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(m.idea).font(.callout).textSelection(.enabled)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Lyrics").font(.caption.bold()).foregroundStyle(.secondary)
                        let text = meta?.lyrics ?? requestLyrics
                        Text(text.isEmpty ? "(instrumental / no lyrics saved)" : text)
                            .font(.body.monospaced())
                            .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .sheet(isPresented: $showScore) {
            TextSheet(title: "Score — \(song.title)", text: (try? String(contentsOf: song.scoreURL, encoding: .utf8)) ?? "")
        }
        .onAppear { loadDuration() }
        .onChange(of: song.id) { _, _ in loadDuration() }
    }

    @State private var cachedDuration: Double = 0
    private func loadDuration() {
        cachedDuration = 0
        let url = song.audioURL
        Task.detached {
            let asset = AVURLAsset(url: url)
            let d = (try? await asset.load(.duration)).map { $0.seconds } ?? 0
            await MainActor.run { cachedDuration = d.isFinite ? d : 0 }
        }
    }

    private var requestLyrics: String {
        guard let data = try? Data(contentsOf: song.directory.appendingPathComponent("request.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return (json["lyrics"] as? String) ?? ""
    }

    private func fmt(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}


// MARK: - Global now-playing bar

struct NowPlayingBar: View {
    @Environment(StudioModel.self) private var model
    let song: Song

    var body: some View {
        HStack(spacing: 14) {
            SongTile(song: song, size: 26)
            Button {
                model.selection = .song(song.id)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text("\(model.library(model.index.placement(for: song.id).library)?.name ?? "") · \(fmt(model.playbackPosition)) / \(fmt(model.playbackDuration))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .help("Show this song")
            ProgressView(value: model.playbackDuration > 0 ? model.playbackPosition / model.playbackDuration : 0)
                .frame(maxWidth: 220)
            Spacer()
            Button { model.playPrevious() } label: { Image(systemName: "backward.fill") }.buttonStyle(.plain)
            Button { model.togglePause() } label: { Image(systemName: model.isPaused ? "play.fill" : "pause.fill").frame(width: 16) }.buttonStyle(.plain)
            Button { model.stop() } label: { Image(systemName: "stop.fill") }.buttonStyle(.plain)
            Button { model.playNext() } label: { Image(systemName: "forward.fill") }.buttonStyle(.plain)
            Button { model.shuffleQueue() } label: { Image(systemName: "shuffle") }
                .buttonStyle(.plain)
                .disabled(!model.canShuffleQueue)
                .help("Shuffle the songs still to come")
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.bar)
    }

    private func fmt(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Playlist detail

struct PlaylistView: View {
    @Environment(StudioModel.self) private var model
    let playlist: Playlist

    var body: some View {
        let items = model.songs(in: playlist)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Artwork(seed: playlist.name, size: 56, glyph: "music.note.list")
                VStack(alignment: .leading, spacing: 5) {
                    Text(playlist.name).font(.title2.bold())
                    StatChip(icon: "music.note", text: "\(items.count) song\(items.count == 1 ? "" : "s")")
                }
                Spacer()
                if model.isPlaying, let id = model.nowPlayingID, playlist.songIDs.contains(id) {
                    Button { model.playPrevious() } label: { Image(systemName: "backward.fill") }
                    Button { model.stop() } label: { Image(systemName: "stop.fill") }
                    Button { model.playNext() } label: { Image(systemName: "forward.fill") }
                    Button { model.shuffleQueue() } label: { Image(systemName: "shuffle") }
                        .disabled(!model.canShuffleQueue)
                        .help("Shuffle the songs still to come")
                } else {
                    Button { model.playShuffled(items) } label: { Label("Shuffle", systemImage: "shuffle") }
                        .disabled(items.isEmpty)
                        .help("Play this playlist in a random order")
                    Button { model.playAll(items) } label: { Label("Play all", systemImage: "play.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(items.isEmpty)
                }
            }
            .padding(20)
            Divider()
            if items.isEmpty {
                ContentUnavailableView("Empty playlist", systemImage: "music.note.list",
                                       description: Text("Right-click a song in a library and choose “Add to playlist”."))
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, song in
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 22, alignment: .trailing)
                            Button { model.playAll(items, from: i) } label: { SongTile(song: song, size: 30) }
                                .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title).fontWeight(model.isPlaying(song) ? .semibold : .regular)
                                Text(song.style).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            let p = model.index.placement(for: song.id)
                            Text("\(model.library(p.library)?.name ?? "") › \(p.category)").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("Open in composer") { model.selection = .song(song.id) }
                            Button("Remove from playlist") {
                                if let idx = playlist.songIDs.firstIndex(of: song.id) {
                                    model.removeFromPlaylist(playlist.id, at: IndexSet(integer: idx))
                                }
                            }
                        }
                    }
                    .onMove { from, to in model.movePlaylistSongs(playlist.id, from: from, to: to) }
                    .onDelete { offsets in model.removeFromPlaylist(playlist.id, at: offsets) }
                }
                Text("Drag to reorder · ⌫ to remove").font(.caption).foregroundStyle(.tertiary).padding(8)
            }
        }
    }
}

// MARK: - Composer form

struct ComposerView: View {
    @Environment(StudioModel.self) private var model
    @State private var showFind = false
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var caseSensitive = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    if model.idea.isEmpty {
                        Text("A funny country song about space truckers in the year 2526…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.idea)
                        .frame(minHeight: 70)
                        .scrollContentBackground(.hidden)
                }
                HStack {
                    Button("Refine prompt") { model.refineIdea() }
                        .disabled(!model.canUseIdea)
                    Button("Write song") { model.writeSong(thenGenerate: false) }
                        .disabled(!model.canUseIdea)
                        .help("Fills in Title, Style and Lyrics below so you can review them first")
                    Button("Write & generate") { model.writeSong(thenGenerate: true) }
                        .disabled(!model.canUseIdea || model.setupProblem != nil)
                        .buttonStyle(.borderedProminent)
                    Spacer()
                    if model.claudeURL == nil {
                        Label("claude CLI not found", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            } header: {
                HStack {
                    Text("Idea")
                    Spacer()
                    if !model.composerIsBlank {
                        Button { model.newSong() } label: { Label("New song", systemImage: "square.and.pencil") }
                            .buttonStyle(.borderless)
                            .help("Clear the composer and start a new song (⌘N)")
                    }
                }
            } footer: {
                Text("Describe the song in plain English. Claude (via your Claude Code login) turns it into a title, a style line and full lyrics.")
            }

            Section {
                TextField("Title", text: $model.title, prompt: Text("Night Shift"))
                TextField("Style", text: $model.style, prompt: Text("English, synthwave pop, driving analog bass, confident male vocal, 112 BPM"), axis: .vertical)
                    .lineLimit(2...4)
            } header: {
                Text("Song")
            } footer: {
                Text("Describe language, genre, vocal, instruments, mood and tempo. Be specific — the style line does most of the work.")
            }

            Section {
                if showFind {
                    HStack(spacing: 8) {
                        TextField("Find", text: $findText).textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField("Replace with", text: $replaceText).textFieldStyle(.roundedBorder)
                        Toggle("Aa", isOn: $caseSensitive).toggleStyle(.button).help("Match case")
                        let n = model.countMatches(findText, caseSensitive: caseSensitive)
                        Text(findText.isEmpty ? "" : "\(n) match\(n == 1 ? "" : "es")")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                        Button("Replace all") { model.replaceAll(findText, with: replaceText, caseSensitive: caseSensitive) }
                            .disabled(n == 0)
                            .keyboardShortcut(.return, modifiers: [.command, .shift])
                    }
                }
                ZStack(alignment: .topLeading) {
                    if model.lyrics.isEmpty {
                        Text("[Verse]\nFirst line here…\n\n[Chorus]\n…\n\nLeave empty (or use only section tags like [Intro]) for an instrumental.")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.lyrics)
                        .font(.body.monospaced())
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                }
            } header: {
                HStack {
                    Text("Lyrics")
                    Spacer()
                    Button {
                        showFind.toggle()
                    } label: {
                        Label("Find & Replace", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("f", modifiers: [.command, .option])
                }
            }

            Section("Generation") {
                Picker("Save to library", selection: Binding(
                    get: { model.resolvedTargetLibrary.id },
                    set: { model.targetLibraryID = $0 }
                )) {
                    ForEach(model.libraries) { l in Text(l.name).tag(l.id) }
                }
                Picker("Mode", selection: $model.mode) {
                    ForEach(SongMode.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                Text(model.mode.help).font(.caption).foregroundStyle(.secondary)

                Toggle("Fast draft (8 steps, lower quality, ~2× faster)", isOn: $model.fastDraft)
                TextField("Seed", text: $model.seedText, prompt: Text("random"))
                    .frame(maxWidth: 220)
                Toggle("Allow running on battery", isOn: $model.allowBattery)
            }
        }
        .formStyle(.grouped)
        .disabled(model.isBusy)
    }
}

// MARK: - Status / generate bar

struct StatusBar: View {
    @Environment(StudioModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.stageText.isEmpty ? "Ready" : model.stageText)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(model.stageText == "Failed" ? .red : .primary)
                if model.isBusy {
                    HStack(spacing: 10) {
                        RenderingMeter(progress: model.progress, active: true).frame(maxWidth: 260)
                        if let p = model.progress {
                            Text("\(Int((p * 100).rounded()))%")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer()
            if model.isBusy {
                if let radioID = model.radioLibraryID {
                    Button("Stop radio") { model.setRadio(false, for: radioID) }
                        .help("Stops writing new songs; the one rendering now finishes and is filed")
                }
                Button(model.radioLibraryID != nil ? "Cancel render" : "Cancel", role: .cancel) { model.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button {
                    model.generate()
                } label: {
                    Label("Generate", systemImage: "waveform.badge.plus")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canGenerate)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

// MARK: - Selected song panel

struct SongPanel: View {
    @Environment(StudioModel.self) private var model
    let song: Song
    @State private var showScore = false
    @State private var showLog = false
    @State private var confirmRegenerate = false

    var body: some View {
        let p = model.index.placement(for: song.id)
        HStack(spacing: 16) {
            Button {
                model.togglePlay(song)
            } label: {
                SongTile(song: song, size: 36)
            }
            .buttonStyle(.plain)
            .help(model.isPlaying(song) ? "Stop" : "Play")

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).font(.headline)
                Text(song.style).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(model.library(p.library)?.name ?? "") › \(p.category)")
                    if song.source == "radio" { Label("radio", systemImage: "dot.radiowaves.left.and.right") }
                    if model.isPlaying(song) {
                        Text("· \(fmt(model.playbackPosition)) / \(fmt(model.playbackDuration))").monospacedDigit()
                    }
                }
                .font(.caption).foregroundStyle(.tertiary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            Spacer()
            Button("Load") { model.loadIntoForm(song) }
                .help("Restore this song's idea, style, lyrics, seed and settings into the composer")
            Button("Regenerate…") { confirmRegenerate = true }
                .disabled(!model.canGenerate)
                .help("Re-render from the composer and replace this song")
            Button("Score") { showScore = true }
                .disabled(!FileManager.default.fileExists(atPath: song.scoreURL.path))
            Button("Export M4A…") { model.exportM4A(song) }
            Button { model.sharingSong = song } label: { Image(systemName: "envelope") }
                .help("Share via Email")
            Button {
                model.revealInFinder(song)
            } label: { Image(systemName: "folder") }
                .help("Reveal in Finder")
            if !model.log.isEmpty {
                Button { showLog = true } label: { Image(systemName: "doc.text") }
                    .help("Show last generation log")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .confirmationDialog("Replace “\(song.title)”?", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("Regenerate and replace") { model.regenerate(replacing: song) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Renders a new version using the composer's current Title, Style and Lyrics, then replaces this song's audio. It keeps its library, category and playlists. The old audio goes to the Trash.")
        }
        .sheet(isPresented: $showScore) {
            TextSheet(title: "Score — \(song.title)", text: (try? String(contentsOf: song.scoreURL, encoding: .utf8)) ?? "")
        }
        .sheet(isPresented: $showLog) {
            TextSheet(title: "Generation log", text: model.log)
        }
    }

    private func fmt(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct TextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 480)
    }
}

struct ShareEmailSheet: View {
    @Environment(StudioModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let song: Song
    @AppStorage("shareRecipients") private var to = ""
    @State private var message = ""
    @State private var includeLyrics = true
    @State private var isSending = false
    @State private var sentID: String? = nil
    @State private var error: String? = nil

    private var recipients: [String] {
        to.split(whereSeparator: { ",; \n".contains($0) }).map(String.init).filter { !$0.isEmpty }
    }
    private var recipientsValid: Bool {
        !recipients.isEmpty && recipients.count <= 50 && recipients.allSatisfy { r in
            let parts = r.split(separator: "@")
            return parts.count == 2 && parts[1].contains(".")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    LabeledContent("Song", value: song.title)
                    LabeledContent("From", value: model.remailFrom.isEmpty ? StudioModel.defaultRemailFrom : model.remailFrom)
                    TextField("To", text: $to, prompt: Text("friend@example.com, another@example.com"))
                    TextField("Message", text: $message, prompt: Text("optional note"), axis: .vertical)
                        .lineLimit(3...8)
                    Toggle("Include lyrics", isOn: $includeLyrics)
                } footer: {
                    Text("Attaches “\(song.title).m4a” (converted from FLAC).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.remailAPIKey.isEmpty {
                    Label("Add a Remail API key in Settings → Email sharing first.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let sentID {
                    Label("Sent to \(recipients.joined(separator: ", ")) · id \(sentID)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green).textSelection(.enabled)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .disabled(isSending || sentID != nil)

            HStack {
                if isSending {
                    ProgressView().controlSize(.small)
                    Text("Converting and sending…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if sentID != nil {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel) { dismiss() }.disabled(isSending)
                    Button("Send") { send() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isSending || !recipientsValid || model.remailAPIKey.isEmpty)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .frame(width: 500)
        .interactiveDismissDisabled(isSending)
    }

    private func send() {
        isSending = true
        error = nil
        Task {
            do { sentID = try await model.shareByEmail(song, to: recipients, message: message, includeLyrics: includeLyrics) }
            catch { self.error = error.localizedDescription }
            isSending = false
        }
    }
}

struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            Text(text).font(.callout)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(tint.opacity(0.12))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(StudioModel.self) private var model
    @State private var remailChecking = false
    @State private var remailStatus: (ok: Bool, text: String)? = nil

    private func checkRemail() {
        remailChecking = true
        remailStatus = nil
        Task {
            do { remailStatus = (true, try await RemailClient(apiKey: model.remailAPIKey).accountStatus()) }
            catch { remailStatus = (false, error.localizedDescription) }
            remailChecking = false
        }
    }

    var body: some View {
        @Bindable var model = model
        Form {
            LabeledContent("Project folder") {
                HStack {
                    Text(model.projectDir.path).lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { pick(for: \.projectDir) }
                }
            }
            LabeledContent("Songs folder") {
                HStack {
                    Text(model.outputRoot.path).lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { pick(for: \.outputRoot) }
                }
            }
            if let problem = model.setupProblem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            } else {
                Label("mlx-Yue runtime and weights found", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }

            Section("Claude (song writing)") {
                TextField("claude CLI path", text: $model.claudePathOverride, prompt: Text("auto-detect"))
                TextField("Model", text: $model.claudeModel, prompt: Text("claude-opus-5"))
                if let url = model.claudeURL {
                    Label("Using \(url.path) with your Claude Code login", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Text("claude CLI not found. Install Claude Code and run `claude` once to log in.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Email sharing (Remail)") {
                SecureField("API key", text: $model.remailAPIKey, prompt: Text("rk_…"))
                TextField("From", text: $model.remailFrom, prompt: Text(StudioModel.defaultRemailFrom))
                TextField("Reply-to", text: $model.remailReplyTo, prompt: Text("optional"))
                HStack {
                    Button("Check connection") { checkRemail() }
                        .disabled(model.remailAPIKey.isEmpty || remailChecking)
                    if remailChecking { ProgressView().controlSize(.small) }
                }
                if let status = remailStatus {
                    Label(status.text, systemImage: status.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(status.ok ? .green : .orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding()
    }

    private func pick(for key: ReferenceWritableKeyPath<StudioModel, URL>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = model[keyPath: key]
        if panel.runModal() == .OK, let url = panel.url {
            model[keyPath: key] = url
        }
    }
}
