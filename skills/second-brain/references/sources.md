# Source files — transcripts and notes

Read this before you build a command from a transcript or notes file. Each rule gives one answer for one file, so two sessions produce the same command.

"The user" is the vault owner. Their name is in your context, or in the `owner:` line of `python3 "$B" status`. In a transcript, the user is the speaker with that name.

## 1. Header fields — the file's header wins over your reading of it

- `--title`: the text of the file's `# …` heading after the last `—` or `:`, with parentheses removed. `# Transcript — Spring Plant Sale` → `Spring Plant Sale`.
- `--date`: the file's `Date:` line.
- `--attendees`: the file's `Attendees:` or `Participants:` line, verbatim. With no such line, omit `--attendees`. Never collect names from the body.
- A title or date that the user states in their request wins over the header.

## 2. Write down what the source says

- With `--transcript-file`, you must also pass `--summary-file` (meeting) or `--assessment-file` / `--note` (interview). The CLI refuses the command otherwise.
- The summary is **3–6 bullets**: what was discussed, what changed, and every number, date and commitment in the source.
- Pass one `--decision "…"` for each decision in the source or in the user's request — anything marked "Decision:", "we agreed", "we decided", or "we will standardize on…". Copy it close to verbatim.
- Interview `--verdict`: set it only when the source states a hire decision in those terms ("strong hire", "no hire", "do not proceed"). A recommendation to advance to another round is not a verdict. Omit `--verdict` and put the recommendation in the assessment.

## 3. Which lines become a `--task`

Use the **first** level that finds anything. Ignore the other levels.

1. **Action-item block.** If a line contains `action item`, `action items`, `next steps` or `to-dos`, the tasks are the commitments from that line to the end of the file. Nothing above it counts.
2. **Marked lines.** Otherwise, if lines carry `Action for <name>:`, `Action:`, `TODO` or `To do:`, the tasks are exactly those lines.
3. **The user's commitments.** Otherwise, the tasks are the sentences **the user speaks** that start with `I'll`, `I will`, `I'm going to` or `I owe`. Another speaker's "I'll…" is not a task at this level.

If no level finds anything and the user asked for tasks, write nothing and say the source has no action items.

These are never tasks: a plan, a question, an agreement to talk later, "got it" that repeats another person's commitment, or a decision.

**One sentence gives at most one task.** The desc is that sentence copied verbatim, starting at its **first verb** — drop a speaker label, timestamp, conjunction, pronoun, auxiliary verb or `Action for me:` marker. End it at the first `—`, `.` or `;`. Keep the deadline and the people named in it.

## 4. Who owns each task

- A task sentence spoken by someone else, or addressed to someone else, is **their** task. Put their name in the 4th `--task` field.
  - The speaker label (`Sam:`) or the name it addresses (`Rosa, can you…`) gives the owner.
  - "I'll…" on another speaker's line means that speaker.
- Only the user's own commitments are the user's. Omit the owner field for them.
- When the user is the one who receives the work, drop the recipient. Never put "me", "you" or the user's name in a desc. Sam says "I'll send you the seating chart", or the user says "Sam: send me the seating chart" → both give `--task "send the seating chart|internal|medium|Sam"`.
- When a sentence hands the work to someone else part-way ("I owe Ana the flyer draft — actually, Rosa, you write it and I'll send it"), the handover sets **only the owner**. The desc is still the text before the `—`, from its first verb: `owe Ana the flyer draft`, owner Rosa. Do not make a second task from the words after the dash.

## 5. Follow-up direction

- `--followup "Who|about"` means **the user is waiting on Who**.
- Create a follow-up only from the user's own request to track, chase or wait on something, and only when the user is truly blocked on the other person. Never take a follow-up from a transcript — a transcript gives tasks and decisions only.
- If the source shows that the user owes the other person ("that one's on me", "I'll get you X"), it is not a follow-up. Make a task with no owner field and no `--followup`. This applies even when the user's request says "track the follow-up with <person>". In your reply, say that the user owes them, not the other way round.
