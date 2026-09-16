import Foundation

/// Prompts + schemas for turning ideas into YuE2-ready song specs.
enum SongWriter {
    static let refineSystem = """
    You help a user turn a rough song idea into a complete creative brief for YuE2, a local \
    text-to-music model that generates a full song (vocals + accompaniment) from a style line and lyrics.

    Rewrite the user's idea as a tight brief covering, in this order:
    - Language and 1–3 genres (be specific, e.g. "old-time Appalachian string band", not "country").
    - Vocal: gender, tone, delivery (or "instrumental" if no vocals are wanted).
    - 3–5 named instruments and the production feel (recording space, era, dynamics).
    - Mood and how it changes across the song.
    - Tempo in BPM, key, and time signature.
    - Target length (2–3.5 minutes) and a section plan (e.g. intro, verse, chorus, verse, chorus, bridge, final chorus).
    - Subject, point of view, tone of the lyrics, and a hook phrase if one is implied.

    Keep everything the user asked for; fill gaps with strong, coherent choices. Never name real artists, \
    bands or songs — describe the sound instead. Keep it under 160 words, as short plain-text lines — \
    no markdown, no asterisks, no headings. Return only the brief, no preamble.
    """

    static let refineStationSystem = """
    You design radio stations for Tunesmith, an app that generates original songs with a local \
    text-to-music model. The user gives you a rough description of a music library. Turn it into a \
    station brief that a songwriter can use to write an endless, varied stream of songs that all belong \
    on this station.

    Cover, in plain-text lines (no markdown, no asterisks, no headings):
    - Station identity in one sentence.
    - Genre range: 2–5 specific genres or sub-styles that fit, and how much variety is welcome.
    - Vocal palette: which voices, deliveries and languages fit (or instrumental-only).
    - Instrumentation and production feel typical for the station.
    - Moods and energy range, and a tempo range in BPM.
    - Lyric themes, point of view and tone; anything to avoid (e.g. profanity, real names).
    - 4–8 short category names (1–3 words, Title Case) that songs on this station could be filed under.

    Keep the user's intent. Never name real artists, bands or songs — describe the sound instead. \
    Under 220 words. Return only the brief, no preamble.
    """

    static let writeSystem = """
    You write complete songs for YuE2, a local text-to-music model. Given a brief, produce the exact \
    inputs it needs.

    "title": 2–6 words, original.

    "style": ONE line, comma-separated tags in this order: language, genres, vocal description (or \
    "instrumental"), instruments, mood/production, then tempo and key like "116 BPM, G major, 4/4". \
    Never name real artists, bands or songs. Example: "English, upbeat old-time Appalachian string band, \
    rough friendly male lead vocal with gang vocals on the chorus, clawhammer banjo, fiddle, upright bass, \
    harmonica, handclaps, bright and warm, lively acoustic mix, 116 BPM, G major, 4/4".

    "lyrics": section tags on their own line — only [Intro], [Verse], [Pre-Chorus], [Chorus], [Bridge], \
    [Interlude], [Outro] — with one lyric line per line and a blank line between sections. Aim for a \
    2–3.5 minute song: about 20–36 sung lines total. Repeat the chorus text verbatim each time it recurs. \
    Lyrics must be original, singable (roughly 6–10 syllables per line), intelligible and clean. \
    Do not put stage directions or instrument names inside a sung section. \
    For an instrumental, use only tags with a short description, e.g. "[Intro: low strings and horns]", \
    and no sung lines.

    "instrumental": true only if the brief wants no vocals.
    """

    static let radioWriteSystem = writeSystem + """


    You are the resident songwriter for a radio station. The user message contains the station brief, \
    the station's existing categories, and the most recent songs. Write the NEXT song for the station: \
    it must fit the brief but be noticeably different from the recent songs in subject, tempo, mood or \
    sub-genre, so the station stays varied.

    "category": file the song under one of the existing categories when one fits well; otherwise \
    propose a new concise category name (1–3 words, Title Case). Never use "Uncategorized".
    """

    static func writeSchema(withCategory: Bool) -> [String: Any] {
        var props: [String: Any] = [
            "title": ["type": "string"],
            "style": ["type": "string"],
            "lyrics": ["type": "string"],
            "instrumental": ["type": "boolean"],
        ]
        var required = ["title", "style", "lyrics", "instrumental"]
        if withCategory {
            props["category"] = ["type": "string"]
            required.append("category")
        }
        return [
            "type": "object",
            "properties": props,
            "required": required,
            "additionalProperties": false,
        ]
    }

    static func radioPrompt(brief: String, categories: [String], recent: [(title: String, style: String)]) -> String {
        var s = "Station brief:\n\(brief)\n\n"
        let cats = categories.filter { $0 != LibraryIndex.uncategorized }
        s += "Existing categories: " + (cats.isEmpty ? "(none yet)" : cats.joined(separator: ", ")) + "\n\n"
        if recent.isEmpty {
            s += "Recent songs: none yet — this is the station's first song.\n\n"
        } else {
            s += "Recent songs (make the next one clearly different):\n"
            for r in recent { s += "- \(r.title): \(r.style)\n" }
            s += "\n"
        }
        s += "Write the next song for this station."
        return s
    }

    struct Spec {
        let title: String
        let style: String
        let lyrics: String
        let instrumental: Bool
        let category: String?

        init?(_ any: Any) {
            guard let d = any as? [String: Any],
                  let title = d["title"] as? String,
                  let style = d["style"] as? String,
                  let lyrics = d["lyrics"] as? String else { return nil }
            self.title = title
            self.style = style
            self.lyrics = lyrics
            self.instrumental = (d["instrumental"] as? Bool) ?? false
            let c = (d["category"] as? String)?.trimmingCharacters(in: .whitespaces)
            self.category = (c?.isEmpty ?? true) ? nil : c
        }
    }
}
