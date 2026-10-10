import Foundation

/// The library's `AGENTS.md`: tells any AI agent how to read the meetings without exploring first.
enum LibraryAgentsGuide {
    static let fileName = "AGENTS.md"

    static let text = """
    # Rec Library

    Meeting notes recorded by Rec (macOS menu-bar recorder). Read freely; don't rename or move meeting folders.

    ## Layout

    - `decisions.md`: append-only log of every decision, newest last. Entry: `## YYYY-MM-DD · <title>`, \
    a relative link to the meeting folder, then one bullet per decision (same format as in `summary.md`).
    - `meetings/YYYY/MM/<YYYY-MM-DD-HHmm>-<title>/`: one folder per meeting, kebab-case ASCII, ≤ 60 chars. \
    Until summarized the title part is `meeting`.

    ## Meeting folder

    | File | Content |
    |---|---|
    | `meta.json` | `id`, `title` (null until summarized), `startedAt` (ISO 8601, local offset), `durationSeconds`, \
    `tracks` (`me`, `others`), `echoCancellation`, `files`, \
    `summary` {`model`, `account`, `createdAt`} |
    | `audio.webm` | Opus audio, one track per entry of `meta.json` `tracks`: `me` = the user's microphone, `others` = the call |
    | `video.webm` | Optional screen recording (AV1 video, both voices mixed) |
    | `transcript.json` | Array of `{"start": s, "end": s, "track": "me" or "others", "text": "…"}`, seconds from the start |
    | `transcript.md` | One line per utterance: `[mm:ss] Me: …` (the user) or `[mm:ss] Otros: …` (everyone else); minutes keep counting past 60 |
    | `summary.md` | `# <title>`, then `## TL;DR`, `## Decisiones`, `## Action items`, `## Preguntas abiertas`, `## Riesgos`, `## Temas` |

    ## Reading tips

    - `summary.md` headings are fixed whatever the language; the content uses the meeting's language.
    - A decision bullet is `**<decision>** (explícita|implícita) — "<quote>" [mm:ss]`; the timestamp points into `transcript.md`.
    - Action items are `<owner> — <task> — <due>`; owner `Yo`/`Me` is the user who recorded.
    - Search across meetings with `grep -r` on `summary.md` or `decisions.md` before opening transcripts.

    """
}
