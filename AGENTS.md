# AGENTS.md

Canonical orientation for AI agents and humans working in this repository. Read this before
creating or editing anything under `knowledge/`.

## Purpose

`knowledge/` holds what we believe and how we work. It is markdown with consistent
frontmatter, optimized for direct file-system reading by AI coding tools. It is not where
data lives; see the two-store rule in [CLAUDE.md](./CLAUDE.md).

## Folder taxonomy

One level deep inside each. No subfolders. Keep it flat.

`markets/` a market, segment, or category under research. Its size, structure, dynamics,
buyers, and where the money moves. One file per market you actually research, not per
market you can name.

`companies/` what we believe about a company and why. Competitors, incumbents, potential
acquirers, suppliers, customers. The entry is synthesis and judgment; the company's facts
and figures are observations in the database, cited from here.

`theses/` claims being tested. A thesis is a falsifiable statement with evidence for and
against, a current confidence, and the decision it informs. This folder is the heart of the
repository. If you are researching something that is not traceable to a thesis, ask why you
are researching it.

`sources/` an evaluation of a source: what it covers, how reliable it is, what it costs,
how to access it, its known biases and gotchas, and how to cite it. Write one the second
time you use a source, not the first.

`methods/` how we do a kind of research, so it gets done the same way twice. Market sizing,
pricing comparison, headcount estimation, claim verification, competitor teardown. A method
entry should be followable by someone who was not there when it was invented.

`decisions/` records of significant calls and the reasoning behind them, both research
decisions (we will not track X, we treat Y as authoritative) and the business decisions the
research fed. Lightweight ADR format.

`runbooks/` recurring collection procedures. The quarterly pricing sweep, the monthly
funding check. Written so they can be executed without improvisation.

`templates/` skeletons to copy. Not content, exempt from the rules below.

Boundaries matter. A thesis is a claim being tested. A decision is a call already made. A
method is how to find something out. When two folders seem plausible, prefer the more
specific one.

## Frontmatter spec

Every content file under `knowledge/` starts with this block. The files in `templates/`,
this file, `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`, and session docs are exempt.

```yaml
---
title: [name]
type: [market|company|thesis|source|method|decision|runbook]
status: [active|draft|supported|refuted|parked|deprecated]
created: [YYYY-MM-DD]
last_reviewed: [YYYY-MM-DD]
confidence: [1-5, or omit for methods and runbooks]
entities: [list of entity slugs this entry concerns]
tags: [list]
---
```

### Status values

`active` current and in use. Safe to rely on.

`draft` started, not yet trustworthy. Say what is missing in the body.

`supported` a thesis the evidence currently supports. Still revisable.

`refuted` a thesis the evidence contradicts. Keep it. Knowing what you ruled out and why is
worth as much as knowing what you concluded, and it stops you re-researching it next year.

`parked` deliberately set aside. Record what would make it live again.

`deprecated` superseded or no longer relevant. Keep the file, point at what replaced it.

### Type-specific fields

Markets: `geography`, `time_horizon`.

Companies: `entity_slug` (required, must match a row in `research.Entity`), `ticker`,
`hq_country`, `category`.

Theses: `decides_what` (required, the decision this thesis informs), `opened` (date),
`resolution` (date, when status became supported or refuted).

Sources: `url`, `cost` (free, paid, subscription), `reliability` (1-5),
`refresh_cadence`.

Decisions: `decision_date`, `supersedes`, `superseded_by`.

Runbooks: `cadence`, `estimated_time`.

### Rules

`created` never changes after the file exists.

`last_reviewed` is updated whenever the content materially changes. A typo fix does not
count, a rewrite does. Anything older than six months should be revisited or marked
deprecated. Market research goes stale much faster than engineering documentation, which is
why this window is six months rather than a year.

`confidence` is your honest read on a 1 to 5 scale, defined in
`knowledge/methods/evidence-standards.md`. It is not a formality. An entry that is always a
4 is an entry nobody calibrated.

`entities` lets the lint script check that the slugs resolve to real rows. Keep it current.

Dates are ISO format, `YYYY-MM-DD`.

## File naming

Lowercase, hyphens between words. Predictable and short. Use the name you already say out
loud. One concept per file. Do not bundle two companies or two theses into one file.

For companies, the filename matches the entity slug in the database exactly. That is what
makes the two stores line up.

## Cross-linking

Link relative paths liberally. From a thesis to the companies it concerns, from a company
to the market it competes in, from a market to the methods used to size it.

When you create an entry, update related entries to point at it. An entry nothing links to
will not be found by the person who needs it.

Prefer a link to a specific section anchor over a link to a whole file when the context is
narrow.

Database rows are referenced with the citation forms in [CLAUDE.md](./CLAUDE.md), not with
markdown links.

## How to find things

What do we think about company X: `companies/x.md`, then follow its links.

What are we trying to figure out: `theses/`, sorted by status.

Where did this number come from: query the database, `research.vw_CurrentObservation`
joined to `research.Source`.

How do we size a market: `methods/`.

Why did we stop tracking Y: `decisions/`, and check for a `refuted` or `parked` thesis.

What happened in the last session: the newest file in `docs/sessions/`.

What have we not processed yet: `capture-log.md`.

## Out of scope

Do not put any of the following under `knowledge/`:

Raw data dumps, tables of figures, or lists of companies with their numbers. Those are
database rows.

Credentials of any kind. See [CLAUDE.md](./CLAUDE.md).

Bulk copies of licensed or paid datasets.

Personal information about private individuals.

Anything you would not be comfortable with every reader of this repository seeing, on the
assumption that it may one day be public or shared with a partner, an investor, or a
counterparty.
