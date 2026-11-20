-- One-time (2026-11-20): merges started before web_merges existed.
--
-- These website accounts were merged into an app account by the first version of
-- the merge (posts moved to the app account), before the app copied the website
-- profile. Their app profile is still blank, so recording the merge lets it finish:
-- the next time the person verifies their school email in the app, /v1/verify/confirm
-- names the website account, the app copies the profile, and the website profile is
-- deleted (or the nightly cron finishes it once the app profile is complete).
--
-- Run once, after `npm run db:init`:
--   npx wrangler d1 execute lac-verification --remote --file=./scripts/backfill-merges.sql
-- Safe to re-run.

INSERT OR IGNORE INTO web_merges (web_user, app_user, requested_at) VALUES
    -- Felix Schura (UC Berkeley)
    ('web_5319f68a8a914e9b9b050c1fa8327c51', '_ec94f34132b4928e5c2bb3d598879845', unixepoch());
