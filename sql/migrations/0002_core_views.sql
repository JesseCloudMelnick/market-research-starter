/*
    0002_core_views.sql

    The questions you will ask constantly, answered once so you are not writing the same
    four joins by hand every session.
*/

/*
    Every observation that has not been superseded, with its entity, metric, and source
    resolved. This is the default thing to query. If you find yourself selecting straight
    from research.Observation you are probably including corrected figures.
*/
CREATE VIEW research.vw_CurrentObservation
AS
SELECT
    o.ObservationId,
    e.Slug              AS EntitySlug,
    e.CanonicalName     AS EntityName,
    e.EntityTypeCode,
    m.Code              AS MetricCode,
    m.Name              AS MetricName,
    o.AsOfDate,
    o.NumericValue,
    o.TextValue,
    o.DateValue,
    o.BitValue,
    COALESCE(o.Unit, m.Unit) AS Unit,
    o.Confidence,
    o.IsEstimate,
    o.EstimateMethod,
    s.SourceId,
    s.Title             AS SourceTitle,
    s.Publisher         AS SourcePublisher,
    s.Url               AS SourceUrl,
    s.Reliability       AS SourceReliability,
    s.PublishedOn       AS SourcePublishedOn,
    o.RecordedAt,
    o.RecordedBy,
    o.RunId,
    o.Notes,
    DATEDIFF(day, o.AsOfDate, CAST(SYSUTCDATETIME() AS date)) AS AgeInDays
FROM research.Observation o
JOIN research.Entity e ON e.EntityId = o.EntityId
JOIN research.Metric m ON m.MetricId = o.MetricId
JOIN research.Source s ON s.SourceId = o.SourceId
WHERE NOT EXISTS (
    SELECT 1 FROM research.Observation sup
    WHERE sup.SupersedesObservationId = o.ObservationId);
GO

/*
    The most recent current observation per entity and metric. What you want when the
    question is "what is X's price now" rather than "how has X's price moved".
*/
CREATE VIEW research.vw_EntityLatestMetric
AS
SELECT v.*
FROM (
    SELECT c.*,
           ROW_NUMBER() OVER (
               PARTITION BY c.EntitySlug, c.MetricCode
               ORDER BY c.AsOfDate DESC, c.Confidence DESC, c.ObservationId DESC) AS rn
    FROM research.vw_CurrentObservation c
) v
WHERE v.rn = 1;
GO

/*
    Facts old enough that you should not quote them without rechecking. The threshold is
    deliberately conservative; adjust it in a later migration if your market moves slower.
*/
CREATE VIEW research.vw_StaleFact
AS
SELECT *
FROM research.vw_EntityLatestMetric
WHERE AgeInDays > 180;
GO

/*
    How much of what you believe rests on which source, and how good that source is.
    A high observation count against a reliability 2 source is a concentration risk.
*/
CREATE VIEW research.vw_SourceUsage
AS
SELECT
    s.SourceId,
    s.Title,
    s.Publisher,
    s.SourceTypeCode,
    s.Reliability,
    s.IsPaywalled,
    s.IsLicensed,
    s.RetrievedAt,
    COUNT(o.ObservationId)      AS ObservationCount,
    AVG(CAST(o.Confidence AS decimal(4,2))) AS AvgConfidence,
    MIN(o.AsOfDate)             AS EarliestAsOf,
    MAX(o.AsOfDate)             AS LatestAsOf
FROM research.Source s
LEFT JOIN research.Observation o ON o.SourceId = s.SourceId
GROUP BY s.SourceId, s.Title, s.Publisher, s.SourceTypeCode, s.Reliability,
         s.IsPaywalled, s.IsLicensed, s.RetrievedAt;
GO

/*
    Where each thesis stands. Weighted counts rather than a single score, because a score
    would imply a precision the evidence does not have. Read the markdown entry for the
    argument; this is the shape of the pile.
*/
CREATE VIEW research.vw_ThesisScorecard
AS
SELECT
    t.ThesisId,
    t.Slug,
    t.Statement,
    t.Status,
    t.Confidence,
    t.DecidesWhat,
    t.FalsifiedBy,
    t.OpenedOn,
    t.LastReviewedOn,
    SUM(CASE WHEN te.Stance = 'supports'    THEN te.Weight ELSE 0 END) AS SupportingWeight,
    SUM(CASE WHEN te.Stance = 'contradicts' THEN te.Weight ELSE 0 END) AS ContradictingWeight,
    SUM(CASE WHEN te.Stance = 'supports'    THEN 1 ELSE 0 END)         AS SupportingCount,
    SUM(CASE WHEN te.Stance = 'contradicts' THEN 1 ELSE 0 END)         AS ContradictingCount,
    SUM(CASE WHEN te.Stance = 'context'     THEN 1 ELSE 0 END)         AS ContextCount,
    DATEDIFF(day, COALESCE(t.LastReviewedOn, t.OpenedOn), CAST(SYSUTCDATETIME() AS date))
        AS DaysSinceReview
FROM research.Thesis t
LEFT JOIN research.ThesisEvidence te ON te.ThesisId = t.ThesisId
GROUP BY t.ThesisId, t.Slug, t.Statement, t.Status, t.Confidence, t.DecidesWhat,
         t.FalsifiedBy, t.OpenedOn, t.LastReviewedOn;
GO

/*
    What has already been searched for. Check this before running a search, especially
    one that feels obvious. The fruitless runs are the valuable rows.
*/
CREATE VIEW research.vw_CollectionCoverage
AS
SELECT
    r.RunId,
    r.StartedAt,
    r.CompletedAt,
    r.Purpose,
    r.Method,
    r.QueryText,
    r.Operator,
    r.SessionDoc,
    r.ResultCount,
    r.WasFruitful,
    COUNT(o.ObservationId) AS ObservationsProduced,
    DATEDIFF(day, r.StartedAt, SYSUTCDATETIME()) AS DaysAgo
FROM research.CollectionRun r
LEFT JOIN research.Observation o ON o.RunId = r.RunId
GROUP BY r.RunId, r.StartedAt, r.CompletedAt, r.Purpose, r.Method, r.QueryText,
         r.Operator, r.SessionDoc, r.ResultCount, r.WasFruitful;
GO

/*
    Entities with little or nothing behind them. Either research them or mark them
    dormant, because a registry full of empty entities makes the real ones harder to see.
*/
CREATE VIEW research.vw_ThinEntity
AS
SELECT
    e.EntityId,
    e.Slug,
    e.CanonicalName,
    e.EntityTypeCode,
    e.Status,
    e.FirstSeenOn,
    e.KnowledgePath,
    COUNT(o.ObservationId) AS ObservationCount,
    MAX(o.AsOfDate)        AS LatestAsOf
FROM research.Entity e
LEFT JOIN research.Observation o ON o.EntityId = e.EntityId
WHERE e.Status = 'active'
GROUP BY e.EntityId, e.Slug, e.CanonicalName, e.EntityTypeCode, e.Status,
         e.FirstSeenOn, e.KnowledgePath
HAVING COUNT(o.ObservationId) < 3;
GO

/*
    The correction history for anything that has been restated. Worth reading before you
    trust a figure that has moved more than once.
*/
CREATE VIEW research.vw_SupersededObservation
AS
SELECT
    old.ObservationId      AS OldObservationId,
    new.ObservationId      AS NewObservationId,
    e.Slug                 AS EntitySlug,
    m.Code                 AS MetricCode,
    old.AsOfDate           AS OldAsOfDate,
    new.AsOfDate           AS NewAsOfDate,
    old.NumericValue       AS OldNumericValue,
    new.NumericValue       AS NewNumericValue,
    old.TextValue          AS OldTextValue,
    new.TextValue          AS NewTextValue,
    new.RecordedAt         AS CorrectedAt,
    new.RecordedBy         AS CorrectedBy,
    new.Notes              AS CorrectionNotes
FROM research.Observation new
JOIN research.Observation old ON old.ObservationId = new.SupersedesObservationId
JOIN research.Entity e ON e.EntityId = new.EntityId
JOIN research.Metric m ON m.MetricId = new.MetricId;
GO
