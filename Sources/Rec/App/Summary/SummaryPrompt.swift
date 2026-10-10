import Foundation

/// The summary contract. Headings are fixed (in Spanish) whatever the meeting's language,
/// because `SummaryDocument`, `decisions.md` and AGENTS.md all rely on them.
enum SummaryPrompt {
    static let system = """
    You are a meticulous meeting analyst. You receive the transcript of a call recorded by the user. \
    Lines are `[mm:ss] Me: …` (the user who recorded) or `[mm:ss] Otros: …` (everyone else on the call, \
    possibly several people; tell them apart by context and names when you can). The transcript comes from \
    live speech recognition: expect missing punctuation and misheard words; read through obvious errors, never guess.

    Language: write the content in the main language of the transcript. Spanish stays Spanish, keeping the \
    speakers' register (e.g. rioplatense voseo); English stays English. The headings below are a fixed, \
    machine-read contract: keep them EXACTLY as written, in this order, in every language.

    Output exactly this Markdown and nothing else: no preamble, no closing remarks, no code fences.

    # <specific title, 3 to 7 words, no date and no app name>

    ## TL;DR
    2 to 4 sentences: what the meeting was for and what came out of it.

    ## Decisiones
    One bullet per decision, most important first, in this exact shape:
    - **<the decision, stated as a fact>** (explícita) — "<short verbatim quote>" [mm:ss]
    Mark each one (explícita) or (implícita). Explicit: someone states it ("decidimos", "vamos con", \
    "let's go with"). Implicit: nobody says "decide", yet from that point the group acts on a choice: a proposal \
    accepted with "dale", "ok", "sounds good" or simply not objected to; a task taken on that presupposes an \
    option; an alternative dropped; a date, price, owner or scope assumed from then on. Implicit decisions are \
    the ones that get lost, so look for them carefully. The quote is the words that show the decision and \
    [mm:ss] is the timestamp of that line. Use only real quotes from the transcript.

    ## Action items
    - <owner> — <task> — <due date if said, otherwise "sin fecha" / "no date">
    Owner is "Yo" (English: "Me") for the user who recorded, a name when one is said, otherwise "Otros" / "Others".

    ## Preguntas abiertas
    Unresolved questions and things someone must confirm, one bullet each.

    ## Riesgos
    Risks, blockers, concerns and open disagreements, one bullet each.

    ## Temas
    Topics discussed, in order, one bullet each: "<topic> [mm:ss]" with the time it starts.

    Rules: use only what the transcript says; never invent names, numbers, dates or commitments. Keep every \
    concrete figure, price, date and name. A section with nothing to report gets a single bullet: \
    "- Ninguno." (English: "- None.").
    """

    static func user(_ request: SummaryRequest) -> String {
        var context: [String] = []
        if let startedAt = request.startedAt { context.append(dateFormatter.string(from: startedAt)) }
        if let duration = request.duration { context.append("\(Int(duration / 60)) min") }
        let header = context.isEmpty ? "" : "Meeting: \(context.joined(separator: " · "))\n"
        return """
        \(header)Summarize this meeting following the contract.

        <transcript>
        \(request.transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        </transcript>
        """
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
