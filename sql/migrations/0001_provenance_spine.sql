/*
    0001_provenance_spine.sql

    The part of the schema that is the same for any research subject: where facts came
    from, what they are about, what they say, and what we think they mean.

    Domain tables for a specific research subject go in later migrations and hang off
    research.Entity and research.Source.

    Design rules encoded here:
      - No observation without a source.
      - Every fact has an as-of date distinct from when it was recorded.
      - Observations are immutable. Corrections supersede; nothing is overwritten.
      - Confidence and reliability are explicit, not implied.
*/

IF SCHEMA_ID('research') IS NULL
    EXEC('CREATE SCHEMA research');
GO

/* ------------------------------------------------------------------ lookups */

CREATE TABLE research.EntityType (
    Code        varchar(32)   NOT NULL CONSTRAINT PK_EntityType PRIMARY KEY,
    Name        nvarchar(100) NOT NULL,
    Description nvarchar(500) NULL
);
GO

CREATE TABLE research.SourceType (
    Code               varchar(32)   NOT NULL CONSTRAINT PK_SourceType PRIMARY KEY,
    Name               nvarchar(100) NOT NULL,
    Description        nvarchar(500) NULL,
    DefaultReliability tinyint       NOT NULL
        CONSTRAINT CK_SourceType_Reliability CHECK (DefaultReliability BETWEEN 1 AND 5)
);
GO

/* ------------------------------------------------------------------- sources */

/*
    Reliability, 1 to 5. Redefine these for your own sources in
    knowledge/methods/evidence-standards.md, but keep the shape.

      5  Primary and audited. Filings, audited statements, signed contracts.
      4  Primary, unaudited. Company-published pricing, official press release, a
         direct interview with someone who would know.
      3  Reputable secondary. Established trade press, a named analyst with a stated
         methodology.
      2  Unverified secondary. Aggregator sites, undated listicles, unnamed sourcing.
      1  Anecdote or marketing. A vendor's claim about a competitor, a forum post.
*/
CREATE TABLE research.Source (
    SourceId       int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Source PRIMARY KEY,
    SourceTypeCode varchar(32)    NOT NULL
        CONSTRAINT FK_Source_SourceType REFERENCES research.SourceType(Code),
    Title          nvarchar(400)  NOT NULL,
    Publisher      nvarchar(200)  NULL,
    Url            nvarchar(1000) NULL,
    PublishedOn    date           NULL,
    RetrievedAt    datetime2(0)   NOT NULL
        CONSTRAINT DF_Source_RetrievedAt DEFAULT SYSUTCDATETIME(),
    Reliability    tinyint        NOT NULL
        CONSTRAINT CK_Source_Reliability CHECK (Reliability BETWEEN 1 AND 5),
    -- Path under archive/ to the local copy. Live URLs rot; keep the rendered page.
    ArchivePath    nvarchar(1000) NULL,
    IsPaywalled    bit            NOT NULL CONSTRAINT DF_Source_IsPaywalled DEFAULT 0,
    IsLicensed     bit            NOT NULL CONSTRAINT DF_Source_IsLicensed DEFAULT 0,
    AccessNotes    nvarchar(max)  NULL,
    Notes          nvarchar(max)  NULL
);
GO

CREATE INDEX IX_Source_RetrievedAt ON research.Source(RetrievedAt DESC);
GO

/*
    What was searched for, how, and what came back. Logged whether or not the search
    found anything, because a search that found nothing is the most valuable kind to
    have recorded: it stops you running it again next quarter.
*/
CREATE TABLE research.CollectionRun (
    RunId       int IDENTITY(1,1) NOT NULL CONSTRAINT PK_CollectionRun PRIMARY KEY,
    StartedAt   datetime2(0)   NOT NULL
        CONSTRAINT DF_CollectionRun_StartedAt DEFAULT SYSUTCDATETIME(),
    CompletedAt datetime2(0)   NULL,
    Purpose     nvarchar(500)  NOT NULL,
    Method      nvarchar(200)  NOT NULL,   -- 'web search', 'api:<name>', 'manual read', 'interview'
    QueryText   nvarchar(max)  NULL,       -- the literal query, so it can be repeated or improved
    Operator    nvarchar(100)  NOT NULL,   -- who or what ran it
    SessionDoc  nvarchar(400)  NULL,       -- docs/sessions/... that describes it
    ResultCount int            NULL,
    WasFruitful bit            NULL,
    Notes       nvarchar(max)  NULL
);
GO

CREATE INDEX IX_CollectionRun_StartedAt ON research.CollectionRun(StartedAt DESC);
GO

/* ------------------------------------------------------------------ entities */

CREATE TABLE research.Entity (
    EntityId           int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Entity PRIMARY KEY,
    EntityTypeCode     varchar(32)   NOT NULL
        CONSTRAINT FK_Entity_EntityType REFERENCES research.EntityType(Code),
    CanonicalName      nvarchar(300) NOT NULL,
    -- Matches the knowledge/companies/<slug>.md filename. This is what lines the two stores up.
    Slug               varchar(120)  NOT NULL CONSTRAINT UQ_Entity_Slug UNIQUE,
    Summary            nvarchar(max) NULL,
    KnowledgePath      nvarchar(400) NULL,
    FirstSeenOn        date          NOT NULL
        CONSTRAINT DF_Entity_FirstSeenOn DEFAULT CAST(SYSUTCDATETIME() AS date),
    Status             varchar(20)   NOT NULL
        CONSTRAINT DF_Entity_Status DEFAULT 'active'
        CONSTRAINT CK_Entity_Status CHECK (Status IN ('active','dormant','defunct','merged','duplicate')),
    MergedIntoEntityId int           NULL
        CONSTRAINT FK_Entity_MergedInto REFERENCES research.Entity(EntityId),
    Notes              nvarchar(max) NULL
);
GO

CREATE INDEX IX_Entity_Type ON research.Entity(EntityTypeCode) INCLUDE (CanonicalName, Status);
GO

/*
    The same company shows up as "Acme", "Acme Corp.", "ACME Corporation", its ticker,
    and its domain. Without this table you will create it five times and never notice.
*/
CREATE TABLE research.EntityAlias (
    EntityAliasId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_EntityAlias PRIMARY KEY,
    EntityId      int           NOT NULL
        CONSTRAINT FK_EntityAlias_Entity REFERENCES research.Entity(EntityId),
    Alias         nvarchar(300) NOT NULL,
    AliasType     varchar(32)   NOT NULL
        CONSTRAINT CK_EntityAlias_Type CHECK (AliasType IN
            ('former-name','dba','ticker','domain','abbreviation','misspelling','product-name','legal-name','other')),
    Notes         nvarchar(500) NULL,
    CONSTRAINT UQ_EntityAlias UNIQUE (EntityId, Alias)
);
GO

CREATE INDEX IX_EntityAlias_Alias ON research.EntityAlias(Alias);
GO

CREATE TABLE research.EntityRelationship (
    EntityRelationshipId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_EntityRelationship PRIMARY KEY,
    FromEntityId     int           NOT NULL
        CONSTRAINT FK_EntityRelationship_From REFERENCES research.Entity(EntityId),
    ToEntityId       int           NOT NULL
        CONSTRAINT FK_EntityRelationship_To REFERENCES research.Entity(EntityId),
    RelationshipType varchar(40)   NOT NULL,  -- 'competes-with', 'subsidiary-of', 'sells-to', 'partners-with', 'acquired'
    AsOfDate         date          NOT NULL,
    EndedOn          date          NULL,
    SourceId         int           NULL
        CONSTRAINT FK_EntityRelationship_Source REFERENCES research.Source(SourceId),
    Notes            nvarchar(max) NULL,
    CONSTRAINT CK_EntityRelationship_NotSelf CHECK (FromEntityId <> ToEntityId)
);
GO

CREATE INDEX IX_EntityRelationship_From ON research.EntityRelationship(FromEntityId, RelationshipType);
CREATE INDEX IX_EntityRelationship_To ON research.EntityRelationship(ToEntityId, RelationshipType);
GO

/* ------------------------------------------------------------------- metrics */

/*
    Definition is NOT NULL on purpose. "Revenue" means four different things depending
    on who published it, and a metric without a stated definition will silently mix
    them together and make every comparison downstream worthless.
*/
CREATE TABLE research.Metric (
    MetricId            int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Metric PRIMARY KEY,
    Code                varchar(60)   NOT NULL CONSTRAINT UQ_Metric_Code UNIQUE,
    Name                nvarchar(200) NOT NULL,
    Unit                nvarchar(50)  NULL,   -- 'USD', 'USD/seat/month', 'count', 'percent'
    ValueKind           varchar(10)   NOT NULL
        CONSTRAINT CK_Metric_ValueKind CHECK (ValueKind IN ('numeric','text','date','boolean')),
    Definition          nvarchar(max) NOT NULL,
    AppliesToEntityType varchar(32)   NULL
        CONSTRAINT FK_Metric_EntityType REFERENCES research.EntityType(Code),
    IsActive            bit           NOT NULL CONSTRAINT DF_Metric_IsActive DEFAULT 1
);
GO

/* -------------------------------------------------------------- observations */

/*
    The central fact table. One row is one claim, about one entity, on one metric, as of
    one date, from one source.

    AsOfDate is the date the fact is true of. RecordedAt is when you wrote it down. They
    are different and conflating them is the most common way a research database starts
    lying.

    Confidence, 1 to 5, is your read on this particular figure, which is not the same as
    the source's general reliability. A reliable source can report a number you have
    reason to doubt.
*/
CREATE TABLE research.Observation (
    ObservationId           int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Observation PRIMARY KEY,
    EntityId                int             NOT NULL
        CONSTRAINT FK_Observation_Entity REFERENCES research.Entity(EntityId),
    MetricId                int             NOT NULL
        CONSTRAINT FK_Observation_Metric REFERENCES research.Metric(MetricId),
    AsOfDate                date            NOT NULL,
    NumericValue            decimal(38,10)  NULL,
    TextValue               nvarchar(max)   NULL,
    DateValue               date            NULL,
    BitValue                bit             NULL,
    Unit                    nvarchar(50)    NULL,
    SourceId                int             NOT NULL
        CONSTRAINT FK_Observation_Source REFERENCES research.Source(SourceId),
    RunId                   int             NULL
        CONSTRAINT FK_Observation_Run REFERENCES research.CollectionRun(RunId),
    Confidence              tinyint         NOT NULL
        CONSTRAINT CK_Observation_Confidence CHECK (Confidence BETWEEN 1 AND 5),
    IsEstimate              bit             NOT NULL
        CONSTRAINT DF_Observation_IsEstimate DEFAULT 0,
    EstimateMethod          nvarchar(500)   NULL,
    SupersedesObservationId int             NULL
        CONSTRAINT FK_Observation_Supersedes REFERENCES research.Observation(ObservationId),
    RecordedAt              datetime2(0)    NOT NULL
        CONSTRAINT DF_Observation_RecordedAt DEFAULT SYSUTCDATETIME(),
    RecordedBy              nvarchar(100)   NOT NULL,
    Notes                   nvarchar(max)   NULL,
    CONSTRAINT CK_Observation_HasValue CHECK (
        NumericValue IS NOT NULL OR TextValue IS NOT NULL
        OR DateValue IS NOT NULL OR BitValue IS NOT NULL),
    -- An estimate has to say how it was arrived at, or it is just a guess wearing a suit.
    CONSTRAINT CK_Observation_EstimateExplained CHECK (
        IsEstimate = 0 OR EstimateMethod IS NOT NULL)
);
GO

CREATE INDEX IX_Observation_Entity_Metric_AsOf
    ON research.Observation(EntityId, MetricId, AsOfDate DESC);
CREATE INDEX IX_Observation_Source ON research.Observation(SourceId);
CREATE INDEX IX_Observation_Supersedes ON research.Observation(SupersedesObservationId)
    WHERE SupersedesObservationId IS NOT NULL;
GO

/*
    Immutability, enforced rather than requested. Corrections are new rows that set
    SupersedesObservationId. Annotation after the fact is allowed, because adding a note
    to an existing observation does not change what was claimed.
*/
CREATE TRIGGER research.TR_Observation_Immutable
ON research.Observation
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(EntityId) OR UPDATE(MetricId) OR UPDATE(AsOfDate)
       OR UPDATE(NumericValue) OR UPDATE(TextValue) OR UPDATE(DateValue) OR UPDATE(BitValue)
       OR UPDATE(Unit) OR UPDATE(SourceId) OR UPDATE(Confidence)
       OR UPDATE(IsEstimate) OR UPDATE(RecordedAt) OR UPDATE(RecordedBy)
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50001, 'Observations are immutable. Insert a new observation and set SupersedesObservationId instead of updating this one.', 1;
    END
END;
GO

CREATE TRIGGER research.TR_Observation_NoDelete
ON research.Observation
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    THROW 50002, 'Observations are never deleted. Supersede the row instead; the history is the point.', 1;
END;
GO

/* -------------------------------------------------------------------- theses */

/*
    The bridge between the two stores. The argument lives in markdown. The link from
    claim to evidence lives here so it can be queried, counted, and checked.

    DecidesWhat is required thinking, not required by the schema: if you cannot say what
    decision a thesis informs, you are collecting trivia.
*/
CREATE TABLE research.Thesis (
    ThesisId       int IDENTITY(1,1) NOT NULL CONSTRAINT PK_Thesis PRIMARY KEY,
    Slug           varchar(120)   NOT NULL CONSTRAINT UQ_Thesis_Slug UNIQUE,
    Statement      nvarchar(1000) NOT NULL,
    DecidesWhat    nvarchar(500)  NULL,
    KnowledgePath  nvarchar(400)  NULL,
    Confidence     tinyint        NOT NULL
        CONSTRAINT CK_Thesis_Confidence CHECK (Confidence BETWEEN 1 AND 5),
    Status         varchar(20)    NOT NULL
        CONSTRAINT CK_Thesis_Status CHECK (Status IN ('open','supported','refuted','parked','superseded')),
    FalsifiedBy    nvarchar(1000) NULL,   -- what evidence would kill this thesis
    OpenedOn       date           NOT NULL
        CONSTRAINT DF_Thesis_OpenedOn DEFAULT CAST(SYSUTCDATETIME() AS date),
    LastReviewedOn date           NULL,
    ResolvedOn     date           NULL,
    Notes          nvarchar(max)  NULL
);
GO

CREATE TABLE research.ThesisEvidence (
    ThesisEvidenceId int IDENTITY(1,1) NOT NULL CONSTRAINT PK_ThesisEvidence PRIMARY KEY,
    ThesisId      int           NOT NULL
        CONSTRAINT FK_ThesisEvidence_Thesis REFERENCES research.Thesis(ThesisId),
    ObservationId int           NOT NULL
        CONSTRAINT FK_ThesisEvidence_Observation REFERENCES research.Observation(ObservationId),
    Stance        varchar(12)   NOT NULL
        CONSTRAINT CK_ThesisEvidence_Stance CHECK (Stance IN ('supports','contradicts','context')),
    Weight        tinyint       NOT NULL
        CONSTRAINT CK_ThesisEvidence_Weight CHECK (Weight BETWEEN 1 AND 5),
    Notes         nvarchar(max) NULL,
    CONSTRAINT UQ_ThesisEvidence UNIQUE (ThesisId, ObservationId)
);
GO

/* ---------------------------------------------------------------- seed data */

INSERT INTO research.EntityType (Code, Name, Description) VALUES
    ('company',   N'Company',   N'An organization: competitor, incumbent, supplier, customer, acquirer.'),
    ('product',   N'Product',   N'A named product or service, usually belonging to a company.'),
    ('market',    N'Market',    N'A market, segment, or category under research.'),
    ('person',    N'Person',    N'A named individual in a professional capacity.'),
    ('geography', N'Geography', N'A country, region, or metro used to scope a figure.');
GO

INSERT INTO research.SourceType (Code, Name, Description, DefaultReliability) VALUES
    ('filing',       N'Regulatory filing',  N'Audited or regulator-submitted document.',                5),
    ('company-site', N'Company website',    N'Vendor-published pricing, product, or company page.',     4),
    ('press-release',N'Press release',      N'Official company announcement.',                          4),
    ('interview',    N'Interview',          N'Direct conversation with someone with first-hand knowledge.', 4),
    ('trade-press',  N'Trade press',        N'Established industry publication with named reporting.',  3),
    ('analyst',      N'Analyst report',     N'Named analyst or firm with a stated methodology.',        3),
    ('aggregator',   N'Aggregator',         N'Third-party directory, review site, or data aggregator.', 2),
    ('social',       N'Social or forum',    N'Forum post, social media, unverified commentary.',        1),
    ('internal',     N'Own analysis',       N'Your own estimate or derivation. Always flag IsEstimate.', 3);
GO
