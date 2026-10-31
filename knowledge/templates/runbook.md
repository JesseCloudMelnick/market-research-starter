<!--
Template: runbook

A recurring collection procedure, written so it can be executed without improvisation by
someone who was not there when it was designed. The difference between a runbook and a
method: a method is how to find something out once, a runbook is the thing you do every
quarter.

Copy to knowledge/runbooks/<slug>.md.
-->

---
title: [Runbook name]
type: runbook
status: [active|draft|deprecated]
created: [YYYY-MM-DD]
last_reviewed: [YYYY-MM-DD]
cadence: [weekly|monthly|quarterly|on-trigger]
estimated_time: [realistic, not optimistic]
entities: []
tags: []
---

## Purpose

<!-- What this run keeps current and why it is worth the recurring cost. A runbook nobody
     can justify should be retired rather than skipped quietly. -->

## Trigger

<!-- When to run it: a date, a cadence, or an event. If it is event-driven, say exactly
     what the event is. -->

## Before you start

<!-- What to check first. Query research.vw_CollectionCoverage for the last run, read the
     previous session doc, confirm source access still works. -->

## Steps

<!-- Numbered and specific. For each step: what to collect, from which source, which metric
     to record it against, and what confidence to assign. Include logging the collection
     run at the start and closing it at the end. -->

## Expected output

<!-- Roughly how many observations, against which entities and metrics. Knowing the normal
     volume is how you notice that a source quietly changed or a scrape broke. -->

## What to do when a source has changed

<!-- The most common failure. Say how to tell a real change in the world from a change in
     how the source reports, because recording the second as the first corrupts the
     series. -->

## After the run

<!-- Which theses to revisit given what came in, what to write in the session doc, and
     whether anything needs promoting to a knowledge entry. -->

## History

<!-- Material changes to this procedure and when, so an old result can be interpreted
     against the procedure that produced it. -->
