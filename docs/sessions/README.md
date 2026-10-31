# Session documentation

One short document per substantial working session, so the next session can resume without
a re-briefing and so the reasoning behind a conclusion survives longer than the chat
transcript.

## Naming

```
docs/sessions/YYYY-MM-DD-<short-kebab-slug>.md
```

ISO date first so the directory sorts chronologically. Add `-2`, `-3` for a second session
the same day. No time of day in the filename.

## When to write one

Write one for any session that produces observations in the database, revises a thesis,
makes a real decision, or teaches you something non-obvious about a source or a market.

Skip it for a typo fix, a version bump, or pure exploration that produced nothing. If you
find yourself padding a session doc to justify writing one, you did not need to write one.

## When to read one

At the start of every session, read the most recent file here. If you are picking up a
thread from an earlier session, read that one too. This is part of the session, not
optional preamble.

## Template

Headings are fixed. Content is whatever is true. Skip a section with nothing in it rather
than padding it.

```markdown
# YYYY-MM-DD â€” <short title>

## Session Focus

One sentence. If it takes three, this was probably two sessions.

## What Was Done

Concrete and verifiable. What was searched, what entities and observations were added, what
knowledge entries were created or revised. Not "researched the pricing landscape" but what
was actually collected and from where.

## What Was Found

The substantive findings, stated plainly, each citing its observations. This is the section
a future reader actually wants. Lead with what changed your mind.

## What Was Learned

Non-obvious discoveries about the research itself: a source's methodology quirk, a
reporting lag, a definition that two sources disagree on, a search that looked promising
and was not. The things that would save the next session an hour. Skip if nothing notable.

## Decisions Made

Real choices with downstream consequences, with brief rationale. Not preferences. If a
decision has lasting consequence, promote it to an entry in `knowledge/decisions/` and
reference it here.

## Open Threads

Unfinished work and what to pick up next, written specifically enough that a fresh session
with no access to this conversation can resume. "Verify the seat-count figures for the
three European vendors; only the US ones have been checked against filings" is resumable.
"Finish the pricing work" is not.

## Database Changes

Migrations applied, metrics added, entities created or merged. Omit if none.

## Files Touched

Flat list, grouped by created, modified, deleted.
```

## Rules

Write it at the end of the session, not days later. The value is in what is fresh: the
small surprises, the dead ends, the reason a judgment went one way.

Do not reproduce the conversation or duplicate the git log. Record what the git log cannot.

Do not auto-commit. Stage the file and let the researcher review it. They are the author of
record and responsible for what it says.

Do not put anything sensitive here. Session docs are visible to everyone with repository
access, including every AI tool pointed at it.

## Worked example

```markdown
# 2026-03-14 â€” Seat pricing for the four mid-market vendors

## Session Focus

Establish list pricing per seat for the four mid-market vendors so the pricing-convergence
thesis has something underneath it.

## What Was Done

- Logged four collection runs, one per vendor, against published pricing pages.
- Created four sources (RUN:31-34), all reliability 4: vendor-published, current, but
  self-reported and list rather than transacted.
- Added 23 observations against the `price_per_seat_month` and `min_seats` metrics,
  covering every published tier.
- Revised `knowledge/theses/pricing-is-converging.md`, confidence 2 to 3.

## What Was Found

List pricing at the entry tier has converged inside a $4 band (OBS:1204, OBS:1211,
OBS:1218, OBS:1225), which is tighter than the thesis predicted. The convergence does not
hold at the enterprise tier, where two of the four have stopped publishing prices at all,
which is itself the more interesting signal.

## What Was Learned

Two vendors changed their pricing page layout in the last quarter and the archived copies
from January are no longer comparable tier for tier. Archive the rendered page, not just
the URL, or the comparison cannot be rebuilt later.

List price is not transacted price and the gap is reportedly large in this segment.
Everything collected today carries that caveat; the `price_per_seat_month` metric
definition now says so explicitly.

## Decisions Made

Track list price and transacted price as separate metrics rather than one metric with a
flag. They come from different sources with different reliability and mixing them in one
series would make every average meaningless.

## Open Threads

- Enterprise tier pricing for the two vendors that stopped publishing. Worth one attempt
  via a reseller quote; if that fails, record it as unobtainable rather than estimating.
- The convergence thesis now needs a falsification condition. It does not have one.

## Database Changes

- Migration 0007: added `transacted_price_per_seat_month` metric.
- 4 sources, 4 collection runs, 23 observations.

## Files Touched

- Modified: `knowledge/theses/pricing-is-converging.md`
- Created: `knowledge/sources/vendor-pricing-pages.md`
- Created: `sql/migrations/0007_transacted_price_metric.sql`
```

That doc is short, every section pulls its weight, and a fresh session reading only Open
Threads can resume intelligently.
