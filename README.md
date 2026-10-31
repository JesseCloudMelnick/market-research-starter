# Market Research Starter

A clone-and-go environment for doing market research with an AI coding assistant, built so
the work compounds instead of evaporating at the end of each session.

It gives you two stores and a strict rule about which one gets what.

**Data** lives in a local SQL Server database. Companies, products, markets, metrics,
pricing observations, funding events, the sources everything came from, and the log of what
you searched for and when. Anything you would ever want to filter, aggregate, trend, or
join.

**Knowledge** lives in markdown files in this repo. What you believe, why you believe it,
how the research is conducted, the decisions you have made, and the record of each working
session. Anything that is judgment, synthesis, method, or narrative.

The test: if you would want to run a query against it, it is SQL. If you would want to read
it or hand it to a person, it is markdown. Markdown cites data by its database identifier
rather than copying numbers, so there is exactly one source of truth for every fact.

## Why bother

Most AI-assisted research is a sequence of impressive conversations that leave nothing
behind. Six months later you cannot remember which competitor you dismissed, what number
you found, where it came from, or whether it is still true.

This repo is the opposite bet. Every fact carries its source, its as-of date, and a
confidence rating. Nothing is ever overwritten, only superseded, so you can see what you
believed in March and why it changed. Every research session ends with a short document
that a future session reads to get back up to speed without you in the room.

The discipline is small. The payoff arrives around month six, when the questions get
specific and you can actually answer them.

## What is in the box

```
START-HERE.md          The script your first AI session follows to set everything up
CLAUDE.md              Operating manual read by every session after that
AGENTS.md              Folder taxonomy, frontmatter spec, naming and linking rules
CONTRIBUTING.md        How to add, update, and retire knowledge entries
capture-log.md         Inbox for raw captures not yet turned into knowledge

knowledge/             The markdown knowledge base
  markets/             A market or segment you are researching
  companies/           What you believe about a company, and why
  theses/              Claims you are testing, with evidence and confidence
  sources/             How reliable a source is, what it costs, what its gotchas are
  methods/             How you do a kind of research, so it is done the same way twice
  decisions/           Calls you made and the reasoning behind them
  runbooks/            Recurring collection procedures
  templates/           Skeletons to copy when creating an entry

docs/sessions/         One short document per working session

sql/migrations/        Numbered, tracked schema migrations
sql/queries/           Example and saved queries

scripts/               PowerShell: initialize, migrate, back up, verify, lint
```

The database schema ships with a provenance spine that is the same for any research
domain: sources, collection runs, entities and their aliases, metrics, observations, and
theses with their evidence. Your first session designs the domain tables on top of it for
whatever you are actually researching.

## Getting started

You need Windows, PowerShell, and a local SQL Server instance. If you do not have SQL
Server yet, that is fine, the setup walks you through it.

Clone this repo, open an AI coding session in the folder, and tell it:

```
Read START-HERE.md and follow it.
```

It will interview you about what you are researching, detect or help you install SQL
Server, create and migrate the database, design the domain tables for your subject, seed
the knowledge base, set up backups, and prove the whole thing works end to end before it
finishes.

Expect that first session to take a while and to ask you real questions. That is the point.

## After setup

Start each working session by reading the most recent file in `docs/sessions/`. End each
substantial one by writing a new one. Everything else is in `CLAUDE.md`, which your
assistant reads automatically.

Run `scripts/Lint-Knowledge.ps1` every so often. It reports stale entries, missing
frontmatter, and markdown that cites database rows which no longer exist. It is a report,
not a gate.

## Conventions

The knowledge-base conventions here are generalized from a working engineering knowledge
base that has been in daily use for years. The shape is proven; the subject matter is not
the point. If a convention gets in your way, change it deliberately and write down why in
`knowledge/decisions/`.
