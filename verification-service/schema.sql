-- D1 schema for the student verification service.
-- Apply with: wrangler d1 execute lac-verification --remote --file=./schema.sql

-- ---------------------------------------------------------------------------
-- School registry. Seeded from IPEDS + the public university-domains dataset;
-- see seed/README.md. Kept server-side so new schools go live without an app
-- release, which is the whole point of not hardcoding the list.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schools (
    id          TEXT PRIMARY KEY,          -- stable slug, e.g. "ut-austin"
    name        TEXT NOT NULL,             -- "The University of Texas at Austin"
    short_name  TEXT,                      -- "UT Austin"
    state       TEXT,                      -- "TX"
    enabled     INTEGER NOT NULL DEFAULT 1 -- 0 parks a school without deleting it
);

CREATE INDEX IF NOT EXISTS idx_schools_name ON schools(name);

-- One school has many domains: utexas.edu, mail.utexas.edu, alumni.utexas.edu.
-- `kind` lets you accept students but refuse alumni addresses per-policy.
CREATE TABLE IF NOT EXISTS school_domains (
    domain     TEXT PRIMARY KEY,           -- lowercase, no leading dot
    school_id  TEXT NOT NULL,
    kind       TEXT NOT NULL DEFAULT 'student',  -- student | alumni | staff
    FOREIGN KEY (school_id) REFERENCES schools(id)
);

CREATE INDEX IF NOT EXISTS idx_domains_school ON school_domains(school_id);

-- ---------------------------------------------------------------------------
-- In-flight verifications. Rows are short-lived; the cron prunes them.
-- The raw address is held only until the code is confirmed, then discarded in
-- favour of the hash.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pending_verifications (
    id                TEXT PRIMARY KEY,    -- opaque id handed to the client
    email_normalized  TEXT NOT NULL,
    email_hash        TEXT NOT NULL,
    code_hash         TEXT NOT NULL,       -- HMAC-SHA256(code, CODE_PEPPER)
    school_id         TEXT NOT NULL,
    user_record_name  TEXT NOT NULL,       -- claimed CloudKit user; proven at confirm
    nonce             TEXT NOT NULL,       -- ownership proof, see README
    attempts          INTEGER NOT NULL DEFAULT 0,
    created_at        INTEGER NOT NULL,
    expires_at        INTEGER NOT NULL,
    consumed_at       INTEGER
);

CREATE INDEX IF NOT EXISTS idx_pending_expiry ON pending_verifications(expires_at);
CREATE INDEX IF NOT EXISTS idx_pending_email ON pending_verifications(email_hash);

-- ---------------------------------------------------------------------------
-- Completed verifications. email_hash PK + user_record_name UNIQUE together
-- enforce one address per account AND one account per address.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS verified_emails (
    email_hash             TEXT PRIMARY KEY,
    user_record_name       TEXT NOT NULL UNIQUE,
    school_id              TEXT NOT NULL,
    domain_kind            TEXT NOT NULL DEFAULT 'student',
    verified_at            INTEGER NOT NULL,
    method                 TEXT NOT NULL DEFAULT 'email',
    -- Reserved for the enrollment-vendor second factor (SheerID et al) so
    -- adding it later is an UPDATE, not a migration.
    enrollment_verified_at INTEGER,
    enrollment_provider    TEXT,
    revoked_at             INTEGER
);

CREATE INDEX IF NOT EXISTS idx_verified_user ON verified_emails(user_record_name);

-- ---------------------------------------------------------------------------
-- Rate limiting. Fixed windows, keyed by "<dimension>:<value>:<window>".
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rate_limits (
    bucket       TEXT PRIMARY KEY,
    count        INTEGER NOT NULL,
    window_start INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_rate_window ON rate_limits(window_start);

-- ---------------------------------------------------------------------------
-- Sweep findings, so "report" mode leaves an audit trail you can review before
-- switching to "delete".
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sweep_findings (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    found_at         INTEGER NOT NULL,
    record_type      TEXT NOT NULL,
    record_name      TEXT NOT NULL,
    creator          TEXT,
    action           TEXT NOT NULL,       -- report | deleted | skipped
    -- Why the record was flagged. Defaulted so a database created before this
    -- column existed reads back sensibly:
    --   creator-unverified  the creator has no verification on file
    --   school-mismatch     the post's schoolID isn't the creator's school
    -- Only creator-unverified is ever deleted; see src/sweep.ts.
    reason           TEXT NOT NULL DEFAULT 'creator-unverified'
);

CREATE INDEX IF NOT EXISTS idx_findings_time ON sweep_findings(found_at);
CREATE INDEX IF NOT EXISTS idx_findings_reason ON sweep_findings(reason);

-- Already have a deployed database from before `reason` existed? This file is
-- re-runnable, but CREATE TABLE IF NOT EXISTS won't add a column to a table
-- that already exists. Run once, by hand:
--
--   wrangler d1 execute lac-verification --remote \
--     --command "ALTER TABLE sweep_findings ADD COLUMN reason TEXT NOT NULL DEFAULT 'creator-unverified'"
