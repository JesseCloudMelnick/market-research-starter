# Contributing

How to add, update, and retire knowledge entries. The audience is both humans and AI
agents. If you are an AI agent making changes on behalf of the researcher, follow this
document exactly.

Read [AGENTS.md](./AGENTS.md) first for the taxonomy and frontmatter spec.

## Before you write anything, decide where it goes

The first question is never which folder. It is whether this belongs in markdown at all.

If it is a fact with a source and a date, it is an observation in the database. Write it
there. If you are tempted to put it in markdown because the database does not have a place
for it, the answer is usually a new metric or a schema migration, not a markdown file.

If it is judgment, synthesis, method, or narrative, continue.

## When to add a new entry

Add one when at least one of the following is true.

The thing is a claim you are actually testing, and you will accumulate evidence on it over
more than one session.

The thing is a non-obvious conclusion someone will want to understand later, including you
in four months.

The thing is a procedure you will repeat, and repeating it from memory will produce
inconsistent results.

The thing is a source with gotchas: a methodology quirk, a lag, a known bias, a paywall
boundary, a rate limit.

The thing is a decision with downstream consequences, especially a decision to stop
pursuing something.

Do not add an entry when the information is transient, when it is a single fact (that is an
observation), or when it would duplicate an existing entry that should simply be updated.

## Which folder

Decide in this order.

1. Is it a claim being tested, with evidence for and against? `theses/`.
2. Is it a call already made, with reasoning? `decisions/`.
3. Is it a procedure you will repeat on a cadence? `runbooks/`.
4. Is it how to find something out? `methods/`.
5. Is it an evaluation of where information comes from? `sources/`.
6. Is it what you believe about a specific company? `companies/`.
7. Is it the structure and dynamics of a market or segment? `markets/`.

If two seem plausible, prefer the more specific. A method that is really about one source
belongs in `sources/`. A thesis that has been settled becomes a `decision` only if a call
was made; otherwise it stays a thesis with status `supported` or `refuted`.

## Use the template

Copy the matching file from `knowledge/templates/`, fill in the frontmatter, remove the
instructional comments, and write the content. The templates encode the order the sections
should appear in. Do not reorder them.

## Entry quality

Every entry answers, in this order: what it is, what we currently believe, what the
evidence is, what would change our mind, and what is still open. The templates enforce
this.

State the conclusion first. An entry that builds to its point over four paragraphs will not
be read by the person who needs it at 9pm.

Cite observations rather than restating numbers. `OBS:1420` is checkable. "roughly $40 a
seat" is not, and will be wrong by next quarter with no way to tell.

Record what would change your mind. A thesis without a falsification condition is an
opinion, and it will quietly survive evidence that should have killed it.

Be honest about confidence. The scale in `knowledge/methods/evidence-standards.md` exists so
that a 2 and a 4 mean something. Rating everything 4 destroys the signal for the one entry
where it matters.

## Style rules

These are repo rules, not preferences.

Direct and technical. Assume an experienced reader.

No em dashes. Use commas, colons, semicolons, parentheses, or separate sentences.

No bold inside paragraphs. Bold is for genuine headings.

No horizontal rules between sections.

Prose over bullets when prose works.

Code and query examples should be runnable and fenced with a language.

## Cross-linking

Link liberally with relative paths. When you create an entry, update the entries that
should point at it. Prefer section anchors when the context is narrow.

## Keeping entries fresh

Any entry whose `last_reviewed` is more than six months old should be revisited and either
updated or marked `deprecated`. Market research decays fast; this is a shorter window than
you would use for engineering docs, on purpose.

`scripts/Lint-Knowledge.ps1` reports stale entries, missing frontmatter, and broken
citations. It is a report, not a gate. What matters is that the numbers move the right way
over time, not that they are ever zero.

Review a thesis when new evidence lands against it, not only on a schedule. The whole
structure is wasted if contradicting evidence goes into the database and the thesis that it
contradicts never gets revisited.

## How to retire an entry

Do not delete files.

1. Set `status` to `deprecated`, `refuted`, or `parked` in the frontmatter.
2. Add a note at the top of the body explaining why and pointing to whatever supersedes it.
3. Update entries that link to this one.

A refuted thesis is one of the most valuable files in the repository. It is the record of
something you checked so you do not check it again, and the reason you were wrong is often
more instructive than the cases where you were right. Deleting it throws that away.
