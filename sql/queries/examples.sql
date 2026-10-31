/*
    Example queries. Not applied by the migration runner; copy and adapt.

    The shapes here are the ones you will reach for constantly. Read them once early;
    knowing these exist is most of what stops the database turning into a write-only
    archive.
*/

/* ---------------------------------------------------------------- the basics */

-- What do we currently believe about one company?
SELECT MetricName, AsOfDate, NumericValue, TextValue, Unit, Confidence,
       SourceTitle, SourceReliability, AgeInDays
FROM research.vw_EntityLatestMetric
WHERE EntitySlug = 'acme-corp'
ORDER BY MetricName;

-- One metric across every entity, newest value each. The core comparison query.
SELECT EntityName, AsOfDate, NumericValue, Unit, Confidence, SourceTitle, AgeInDays
FROM research.vw_EntityLatestMetric
WHERE MetricCode = 'price_per_seat_month'
ORDER BY NumericValue;

-- How has one figure moved over time, including corrections?
SELECT AsOfDate, NumericValue, Confidence, IsEstimate, SourceTitle, RecordedAt
FROM research.vw_CurrentObservation
WHERE EntitySlug = 'acme-corp' AND MetricCode = 'price_per_seat_month'
ORDER BY AsOfDate;

/* ------------------------------------------------------- finding the resolver */

-- Resolve a name you found in the wild to an entity, including aliases. Run this
-- before creating an entity, or you will create the same company twice.
DECLARE @name nvarchar(300) = N'ACME Corporation';
SELECT e.EntityId, e.Slug, e.CanonicalName, e.Status, 'canonical' AS MatchedOn
FROM research.Entity e WHERE e.CanonicalName = @name
UNION ALL
SELECT e.EntityId, e.Slug, e.CanonicalName, e.Status, a.AliasType
FROM research.EntityAlias a
JOIN research.Entity e ON e.EntityId = a.EntityId
WHERE a.Alias = @name;

/* --------------------------------------------------------------- what to do next */

-- Facts old enough that quoting them would be careless.
SELECT EntityName, MetricName, AsOfDate, NumericValue, AgeInDays, SourceTitle
FROM research.vw_StaleFact
ORDER BY AgeInDays DESC;

-- Theses that have not been looked at lately, or that have no evidence at all.
SELECT Slug, Status, Confidence, SupportingWeight, ContradictingWeight, DaysSinceReview, DecidesWhat
FROM research.vw_ThesisScorecard
WHERE Status = 'open' AND (DaysSinceReview > 90 OR SupportingCount + ContradictingCount = 0)
ORDER BY DaysSinceReview DESC;

-- Theses where the evidence against outweighs the evidence for. Read these first;
-- they are where you are most likely to still be wrong.
SELECT Slug, Statement, Confidence, SupportingWeight, ContradictingWeight, FalsifiedBy
FROM research.vw_ThesisScorecard
WHERE ContradictingWeight > SupportingWeight
ORDER BY ContradictingWeight - SupportingWeight DESC;

-- Entities you registered and then never researched.
SELECT Slug, CanonicalName, EntityTypeCode, FirstSeenOn, ObservationCount
FROM research.vw_ThinEntity
ORDER BY FirstSeenOn;

/* ----------------------------------------------------------- quality control */

-- How concentrated is your picture on any one source?
SELECT Title, Publisher, Reliability, ObservationCount, AvgConfidence, LatestAsOf
FROM research.vw_SourceUsage
WHERE ObservationCount > 0
ORDER BY ObservationCount DESC;

-- Everything resting on weak sourcing. Worth a periodic look.
SELECT EntityName, MetricName, AsOfDate, NumericValue, Confidence,
       SourceTitle, SourceReliability
FROM research.vw_CurrentObservation
WHERE SourceReliability <= 2 OR Confidence <= 2
ORDER BY SourceReliability, Confidence;

-- Estimates, and whether they explain themselves.
SELECT EntityName, MetricName, AsOfDate, NumericValue, EstimateMethod, Confidence
FROM research.vw_CurrentObservation
WHERE IsEstimate = 1
ORDER BY Confidence;

-- Where two sources disagree about the same entity, metric, and date. The most
-- interesting query in this file: disagreement usually means the two sources are
-- measuring different things, which is worth more than either number.
SELECT a.EntitySlug, a.MetricCode, a.AsOfDate,
       a.NumericValue AS ValueA, a.SourceTitle AS SourceA, a.SourceReliability AS RelA,
       b.NumericValue AS ValueB, b.SourceTitle AS SourceB, b.SourceReliability AS RelB,
       ABS(a.NumericValue - b.NumericValue) AS Gap
FROM research.vw_CurrentObservation a
JOIN research.vw_CurrentObservation b
  ON  b.EntitySlug = a.EntitySlug
  AND b.MetricCode = a.MetricCode
  AND b.AsOfDate   = a.AsOfDate
  AND b.ObservationId > a.ObservationId
WHERE a.NumericValue IS NOT NULL
  AND b.NumericValue IS NOT NULL
  AND a.NumericValue <> b.NumericValue
ORDER BY Gap DESC;

-- Corrections: what you used to believe and what changed it.
SELECT EntitySlug, MetricCode, OldNumericValue, NewNumericValue,
       CorrectedAt, CorrectedBy, CorrectionNotes
FROM research.vw_SupersededObservation
ORDER BY CorrectedAt DESC;

/* ------------------------------------------------------------------ coverage */

-- Have I already searched for this? Check before running a search that feels obvious.
SELECT StartedAt, Purpose, Method, QueryText, ResultCount, WasFruitful,
       ObservationsProduced, DaysAgo
FROM research.vw_CollectionCoverage
WHERE Purpose LIKE '%pricing%' OR QueryText LIKE '%pricing%'
ORDER BY StartedAt DESC;

-- Searches that found nothing. The rows that save you the most time.
SELECT StartedAt, Purpose, Method, QueryText, Notes
FROM research.vw_CollectionCoverage
WHERE WasFruitful = 0
ORDER BY StartedAt DESC;

-- Coverage matrix: which entities have which metrics, and which gaps are real.
SELECT e.Slug, m.Code AS MetricCode,
       MAX(o.AsOfDate) AS LatestAsOf,
       COUNT(o.ObservationId) AS Observations
FROM research.Entity e
CROSS JOIN research.Metric m
LEFT JOIN research.Observation o ON o.EntityId = e.EntityId AND o.MetricId = m.MetricId
WHERE e.Status = 'active' AND m.IsActive = 1
  AND (m.AppliesToEntityType IS NULL OR m.AppliesToEntityType = e.EntityTypeCode)
GROUP BY e.Slug, m.Code
ORDER BY e.Slug, m.Code;

/* ----------------------------------------------------- recording observations */

/*
    The shape of a complete capture. Always inside a transaction, always with a
    collection run, always with a source. Parameterize in real use.
*/
BEGIN TRANSACTION;

DECLARE @RunId int, @SourceId int, @EntityId int, @MetricId int;

INSERT INTO research.CollectionRun (Purpose, Method, QueryText, Operator)
VALUES (N'Quarterly pricing sweep', N'web search', N'acme corp pricing per seat', N'claude');
SET @RunId = SCOPE_IDENTITY();

INSERT INTO research.Source (SourceTypeCode, Title, Publisher, Url, PublishedOn, Reliability, ArchivePath)
VALUES ('company-site', N'Acme Corp pricing page', N'Acme Corp',
        N'https://example.invalid/pricing', '2026-10-01', 4,
        N'archive/2026-10-31/acme-pricing.html');
SET @SourceId = SCOPE_IDENTITY();

SELECT @EntityId = EntityId FROM research.Entity WHERE Slug = 'acme-corp';
SELECT @MetricId = MetricId FROM research.Metric WHERE Code = 'price_per_seat_month';

INSERT INTO research.Observation
    (EntityId, MetricId, AsOfDate, NumericValue, Unit, SourceId, RunId, Confidence, RecordedBy, Notes)
VALUES
    (@EntityId, @MetricId, '2026-10-01', 49.00, N'USD/seat/month', @SourceId, @RunId, 4, N'claude',
     N'Entry tier, billed annually. Monthly billing is listed at 59.');

UPDATE research.CollectionRun
SET CompletedAt = SYSUTCDATETIME(), ResultCount = 1, WasFruitful = 1
WHERE RunId = @RunId;

COMMIT TRANSACTION;

/*
    Correcting an earlier figure. Never UPDATE; the trigger will stop you anyway.
*/
-- INSERT INTO research.Observation
--     (EntityId, MetricId, AsOfDate, NumericValue, Unit, SourceId, Confidence, RecordedBy,
--      SupersedesObservationId, Notes)
-- VALUES
--     (@EntityId, @MetricId, '2026-10-01', 44.00, N'USD/seat/month', @SourceId, 5, N'claude',
--      1234, N'Earlier figure was the monthly-billed price, not annual.');
