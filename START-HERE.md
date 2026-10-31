# START HERE

You are setting up a persistent market research environment. This session is for building
the environment. Do not perform any market research yet, however tempting the subject
turns out to be.

Work through the phases below in order. Do not skip ahead, and do not create the database
before the researcher has approved the schema.

Read [CLAUDE.md](./CLAUDE.md) and [AGENTS.md](./AGENTS.md) before you start, because the
rules in them govern everything you write from here on.

## Phase 0: understand what you are building

Ask the researcher these questions, in one round, and wait for the answers. Do not proceed
on assumptions.

1. What market or markets are you researching, and what decisions is the research meant to
   support? If the answer is vague, push once. A research environment built with no
   decision in mind produces a tidy archive nobody reads.
2. What entity types matter most: companies, products, markets and segments, people,
   geographies, funding rounds, job postings, pricing plans, patents, something else?
3. What will you actually be pulling from: open web, filings, app store data, analyst
   reports, professional networks, paid APIs, your own interviews? Which, if any, are paid
   or licensed?
4. How often will you work on this, and over what horizon: a few intense weeks, or
   something you tend for a year?
5. One database, or one per market?
6. What should the database be called, and what SQL Server instance should it live on if
   one already exists?

Record the answers. They drive everything below, and they go into the first session doc.

## Phase 1: find or install SQL Server

Detect what is already present and report it plainly:

```powershell
Get-Service | Where-Object { $_.Name -like 'MSSQL*' } | Select-Object Name, Status, DisplayName
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL' -ErrorAction SilentlyContinue
```

Also check for SQL Server Management Studio or Azure Data Studio, and tell the researcher
which they have.

If no instance exists, do not attempt a silent install. Tell them what to install and why:

- SQL Server 2022 Developer Edition, which is free for non-production use and is the full
  feature set. Express is also fine and has a 10 GB database cap that a research database
  will not approach for a long time.
- SQL Server Management Studio, or Azure Data Studio if they prefer something lighter.

Give them the download links, tell them to choose a default instance or note the instance
name they pick, and tell them to enable Windows authentication, which is the default. Then
wait, and verify the install yourself once they say it is done.

The scripts in this repo use `System.Data.SqlClient` directly, so no command-line tools
beyond Windows PowerShell are required.

## Phase 2: configure and create the database

Edit [settings.json](./settings.json) with the instance and database name you agreed on.
Leave `"integratedSecurity": true`. If the researcher asks for SQL authentication, stop and
explain why we are not doing that: a password would have to live somewhere, and this repo
is designed so that it never does. Only proceed with SQL authentication if they insist
after hearing that, and if they do, the password goes in a file that is gitignored and you
tell them exactly which one.

Then:

```powershell
.\scripts\Initialize-Database.ps1
```

That creates the database if it does not exist and applies every migration in
`sql/migrations/`, recording them in `research.SchemaMigration`. It is safe to re-run.

Migration `0001` creates the provenance spine, which is the same for any research subject:

- `research.Source` and `research.SourceType`: where everything came from, with a
  reliability rating.
- `research.CollectionRun`: what was searched for, when, how, and what came back. This is
  what stops the same fruitless search being run every quarter.
- `research.Entity`, `research.EntityAlias`, `research.EntityRelationship`: the registry of
  things being researched, with aliases, because the same company appears under five
  spellings and a ticker.
- `research.Metric`: the definition of a measurable thing, including how it is measured.
  Ambiguity here poisons every comparison downstream.
- `research.Observation`: the central fact table. Immutable, sourced, dated, confidence
  rated. A trigger blocks updates and deletes; corrections are new rows that supersede old
  ones.
- `research.Thesis` and `research.ThesisEvidence`: the bridge between the two stores. The
  argument lives in markdown; the link from claim to evidence lives here so it can be
  queried.

Migration `0002` creates the views. Read both files before you go further, because the
domain schema you are about to design has to sit on top of them properly.

## Phase 3: design the domain schema

Now design the tables specific to what the researcher is actually studying, as migration
`0003` and beyond. Propose the design in chat and get approval before writing any DDL.

Hold to these principles:

Most facts are observations, not columns. Before adding a table, ask whether the thing is
really a metric with observations against an entity. Revenue, headcount, price, rating,
and market share are all observations. A table is warranted when the thing has its own
structure and lifecycle: a funding round, a pricing plan with tiers, a job posting, a
product release.

Everything references an entity and a source. A domain table with no path back to a source
is a liability.

Everything is dated, with the as-of date distinct from the recorded-at date.

Normalize enough to trust, stay simple enough to use. This is one researcher, not a data
warehouse. Do not build a star schema for a few thousand rows.

No speculative tables. Build what the answers in Phase 0 call for. The migration mechanism
exists precisely so that later needs are cheap.

Seed the metrics the researcher named in Phase 0 into `research.Metric`, each with a real
`Definition`. A metric called "revenue" with no definition will be compared against three
incompatible numbers inside a month.

Seed `research.EntityType` with anything beyond what `0001` ships.

## Phase 4: seed the knowledge base

Create, using the templates in `knowledge/templates/`:

One entry in `knowledge/markets/` for the primary market, even if most of it is unknown.
Fill in what is known, state what is not, and mark it `draft`.

One entry in `knowledge/theses/` for each thing the researcher actually wants to find out,
drawn from their Phase 0 answers. Each one gets a `decides_what` field. These are the spine
of the work and they will be revised constantly.

`knowledge/methods/evidence-standards.md`. This one is important enough to write carefully.
Define the 1 to 5 reliability scale for sources and the 1 to 5 confidence scale for
observations and theses, with concrete examples drawn from the researcher's actual sources
rather than generic ones. Everything else depends on these scales meaning something.

One entry in `knowledge/sources/` for each source named in Phase 0, with its cost, access
method, refresh cadence, and known gotchas.

Register the corresponding theses in `research.Thesis` so the slugs in markdown resolve.

Do not invent market content to fill these files. An honest `draft` entry that says what is
unknown is correct at this stage. A confident entry written from your general knowledge of
the industry is exactly the failure mode this repository is built to prevent, and it will
be believed later precisely because it is written down.

## Phase 5: backups

The database is the thing that cannot be recreated. Set up a local scheduled backup:

```powershell
.\scripts\Backup-Database.ps1 -RegisterScheduledTask
```

That writes a nightly backup to the path in `settings.json` and keeps the configured number
of days. Run it once manually first, then restore the backup into a scratch database to
prove the restore path works. Do not skip the restore test. An untested backup is a
hypothesis.

Tell the researcher that `archive/` holds local copies of sources, is gitignored, and needs
to be in whatever backs up their machine, because the database backup does not cover it.

## Phase 6: verify

```powershell
.\scripts\Test-Environment.ps1
```

This proves the whole path end to end: it connects, inserts a source, a collection run, an
entity, a metric, and an observation, reads them back through the views, confirms that the
immutability trigger actually blocks an update and a delete, and then rolls it all back.

Show the researcher the real output. If anything fails, fix it before you finish. Do not
report success you did not observe.

Then run:

```powershell
.\scripts\Lint-Knowledge.ps1
```

and show them that too.

## Phase 7: hand off

Write the first session doc at `docs/sessions/YYYY-MM-DD-environment-setup.md` following
the template in `docs/sessions/README.md`. Record the Phase 0 answers, the schema design
and why it is shaped that way, and anything you had to assume. Stage it, do not commit it.

Then give the researcher a short tour in chat, no more than a screen:

- What exists now and where.
- How to add an observation, with one real example they can paste.
- How to ask the database a question, with one real example.
- How to start the next session.
- Anything you were unsure about or had to assume.

Finally, tell them the single most useful first research session to run, and stop there.
Do not start it.

## A note on what you are for

The researcher could get plausible-sounding answers about their market from any model in
thirty seconds. That is not what this is. The value here is that in six months there will
be a thousand sourced, dated observations, a dozen theses with evidence on both sides, and
a record of what was checked and found wanting.

That only happens if you are rigorous now, when it is boring, and if you say "I do not
know" rather than producing a number that sounds right. Every unfounded figure you write
into this database will be read later as fact by someone who trusts the structure.
