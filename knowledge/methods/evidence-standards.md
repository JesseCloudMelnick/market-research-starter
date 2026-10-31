---
title: Evidence Standards
type: method
status: active
created: 2026-10-31
last_reviewed: 2026-10-31
entities: []
tags: [method, confidence, reliability, foundational]
---

The two scales every observation and thesis is rated on. Everything else in this
repository depends on these meaning something, so read this before rating anything, and
replace the examples below with ones drawn from your own sources the first time you use
them.

A scale nobody calibrates collapses to a single value. If every observation you record is
a 4, you have spent the effort of rating and bought none of the benefit.

## Source reliability, 1 to 5

A property of the source, set once when you create the source record. It answers: how much
would I trust this publisher on a figure like this, before seeing the figure?

5. Primary and audited. Regulatory filings, audited financial statements, signed contracts,
   court records. Someone with a professional obligation checked it.

4. Primary and unaudited. The company's own pricing page, an official press release, a
   product changelog, a direct conversation with someone who would know first-hand.
   Authoritative about what the company says; not necessarily about what is true.

3. Reputable secondary. Established trade press with named reporting, a named analyst with
   a stated methodology, a well-run industry survey that publishes its sample.

2. Unverified secondary. Aggregator sites, review platforms, undated roundups, anything
   that cites "sources" without naming them. Useful for direction, not for a number you
   will quote.

1. Anecdote or marketing. A vendor's claim about a competitor, a forum post, a conference
   rumor, a figure that appears everywhere with no original source. Record it if it is all
   you have, rate it honestly, and never let it survive into a conclusion unchallenged.

## Observation confidence, 1 to 5

A property of the specific figure, set each time you record one. Reliability is about the
publisher; confidence is about this number. They come apart constantly.

A reliability 5 filing can yield a confidence 2 observation when the figure is a segment
you had to disaggregate yourself. A reliability 2 aggregator can yield a confidence 4
observation when three independent aggregators agree and the number is easy to check.

5. Directly stated by an authoritative source, unambiguous, current, and consistent with
   everything else you know.

4. Directly stated and credible, with one caveat: it is slightly stale, or the definition
   is marginally different from yours, or it is self-reported.

3. Stated but with a real problem: a definition mismatch you had to bridge, a date you had
   to infer, or a single source with nothing corroborating it.

2. Derived, inferred, or reported at second hand. You believe it is in the right range.
   You would not put it in front of a client without saying where it came from.

1. A placeholder. You recorded it so the gap is visible, not because you believe it. Always
   pair this with a note saying what would replace it.

## Estimates

An estimate is any figure you produced rather than read. Flag it with `IsEstimate` and
record the method in `EstimateMethod` in enough detail that someone else could reproduce
it: the inputs, the assumption, the arithmetic.

"Headcount times average revenue per employee for the segment, using the three public
comparables" is a method. "Industry benchmarks" is not a method, it is a way of avoiding
saying you guessed.

An estimate built on other estimates compounds error quickly. When you find yourself at
three layers deep, the honest output is a range and a confidence of 2, not a point
estimate.

## What never gets recorded as an observation

Your own interpretation. That is a thesis, and it belongs in `knowledge/theses/` with the
observations cited as evidence.

A number a language model produced from its own knowledge, including you. Model recall is
not a source. If you cannot point to where a figure came from, it does not go in the
database at any confidence, because a 1 recorded today reads as a fact in six months.

A figure with no as-of date. Find the date or do not record it.

## Handling disagreement

When two sources give different numbers for the same thing, record both observations. Do
not average them, do not pick the one you like, and do not quietly drop the inconvenient
one. The disagreement is itself a finding, and it usually means the two sources are
measuring different things, which is worth more than either number.

Note the conflict on both observations and, if it matters, write the reconciliation into
the relevant market or company entry.

## Review

Confidence decays. A confidence 4 observation about pricing is a confidence 2 observation
eighteen months later and nothing in the database will tell you that on its own. Use
`research.vw_StaleFact` to find figures that need rechecking, and re-record rather than
re-rate: a new observation with a current as-of date, superseding the old one.
