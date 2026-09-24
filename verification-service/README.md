# Student verification service

Confirms that a user controls an email address belonging to a school in the
registry, then writes a `Verification` record into the app's public CloudKit
database using a key only this service holds.

## Why it's shaped this way

Two constraints drove every decision:

1. **A `.edu` address proves affiliation, not enrollment.** Alumni, staff and
   continuing-ed registrants keep addresses for years. Call this "verified
   university email" in user-facing copy, never "verified student", until an
   enrollment vendor is wired in (see Follow-ups).
2. **CloudKit's public database cannot enforce this.** Security roles are only
   World / Authenticated / Creator — there is no way to say "only verified
   users may create a `FilmSubmission`". So:
   - the in-app gate (`VerificationGate.swift`) is a *courtesy*, giving honest
     users an explanation instead of a silent failure;
   - `src/sweep.ts` is the actual enforcement, running nightly server-side;
   - the verified flag lives on a **separate record type** the client cannot
     write. A field on `UserProfile` would be writable by its owner and
     therefore worthless.

## Flow

```
app                          worker                        cloudkit
 |-- POST /verify/request ----->|
 |                              |-- registry lookup (D1)
 |                              |-- store HMAC(code), nonce
 |                              |-- send mail (Resend)
 |<-- { pendingID, nonce } -----|
 |-- write nonce to own UserProfile record ------------------->|
 |-- POST /verify/confirm ----->|
 |                              |-- compare HMAC(code), constant time
 |                              |-- read UserProfile, check nonce ---->|
 |                              |-- write Verification record -------->|
 |<-- { verified: true } -------|
 |-- re-read Verification record ---------------------------->|
```

The nonce step is the part that's easy to leave out and important to keep. The
client asserts its own `userRecordName` at request time, which is spoofable;
requiring the nonce to appear on that account's own `UserProfile` record —
which only its owner may write — is what proves the caller owns the account.

## Setup

### 1. CloudKit schema

Create these in the CloudKit Dashboard **in both Development and Production**.

New record type `Verification`:

| Field | Type |
|---|---|
| `userRecordName` | String (queryable) |
| `emailHash` | String |
| `schoolID` | String (queryable) |
| `schoolName` | String |
| `domainKind` | String |
| `method` | String |
| `verifiedAt` | Int64 |
| `enrollmentVerified` | Int64 |

Security roles for `Verification` — **this is the part that matters**:

| Role | Permission |
|---|---|
| World | none |
| Authenticated | **Read** |
| Creator | Read |

No write for anyone. The server-to-server key bypasses role checks, so the
service can still write it while no client can.

Add one field to the existing `UserProfile` type:

| Field | Type |
|---|---|
| `verificationNonce` | String |

Also add a `Verification` index on `userRecordName` (queryable) so the sweep
can look records up.

### 2. Server-to-server key

```sh
# Generate a P-256 key, then convert SEC1 -> PKCS#8, which is what WebCrypto
# can import. Skipping the second step produces a constant 401 that looks
# exactly like a wrong key.
openssl ecparam -name prime256v1 -genkey -noout -out ck-key-sec1.pem
openssl pkcs8 -topk8 -nocrypt -in ck-key-sec1.pem -out ck-key-pkcs8.pem
openssl ec -in ck-key-sec1.pem -pubout -out ck-key-public.pem
```

Paste `ck-key-public.pem` into CloudKit Dashboard → your container → Tokens &
Keys → Server-to-Server Keys. Copy the Key ID it gives back.

Keep `ck-key-pkcs8.pem` out of git. It is the credential that can write
verification records for anyone.

### 3. Resend and DNS

University mail filters are the strictest you'll meet, and this is the most
common reason a rollout like this fails. Before launch:

- Add a sending domain in Resend (a subdomain such as `send.yourdomain.com`
  keeps the root domain's reputation separate). Whatever you choose must match
  `MAIL_FROM` in `wrangler.toml`.
- Publish the records Resend generates. As of September 2026 a new domain gets
  four, routed through Resend's own MTA (no MX, no Amazon SES):

  | Type | Name | Content |
  |---|---|---|
  | TXT | `resend._domainkey` | the `p=...` DKIM key |
  | CNAME | `rsend` | `rsend.forge.rmta.net` |
  | CNAME | `send` | `send.forge.rmta.net` |
  | TXT | `_dmarc` | see below |

  Older Resend domains instead show an SPF TXT plus an MX at `send` pointing to
  `feedback-smtp.<region>.amazonses.com`; if you see that, all MX records must
  agree on one region.
- **Check for pre-existing anti-email hardening first.** Website builders
  (Squarespace does this by default) publish a "this domain sends no mail"
  preset: `v=spf1 -all` at the apex, a null `v=DKIM1; p=` at `_domainkey`, and
  a DMARC record at `p=reject` with strict alignment (`adkim=s; aspf=s`).
  Left in place these bounce every verification code, and `p=reject` means
  hard rejection rather than spam-foldering. Delete that preset before adding
  Resend's records, and re-add DMARC at `p=none` with a `rua=` address.
- **Copy the DKIM value with the copy button.** The dashboard truncates it for
  display, and a partial key is the most common verification failure.
- **If DNS is on Cloudflare, set both CNAMEs to DNS-only (grey cloud).** A
  proxied record can't be read by Resend and the domain will never verify.
  Cloudflare defaults new CNAMEs to proxied.
- Then publish DMARC yourself — TXT at `_dmarc`,
  `v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.com; fo=1; pct=100`. Read the
  reports for a couple of weeks before tightening to `quarantine`/`reject`.
  Note DKIM gets strict alignment but SPF only relaxed, so DKIM is what
  actually carries DMARC compliance here.
- Send test codes to real addresses at your first launch schools and confirm
  they reach the inbox, not quarantine. Gmail-hosted `.edu` tenants behave
  differently from on-premise Exchange; test both.
- Warm up gradually. A cold domain sending hundreds of codes on day one gets
  throttled.

### 4. Deploy

```sh
cd verification-service
npm install

wrangler d1 create lac-verification        # paste the id into wrangler.toml
npm run db:init
npm run db:seed

wrangler secret put CK_KEY_ID
wrangler secret put CK_PRIVATE_KEY         # contents of ck-key-pkcs8.pem
wrangler secret put CODE_PEPPER            # openssl rand -base64 32
wrangler secret put RESEND_API_KEY

npm run typecheck
npm run deploy
```

Then set `MAIL_FROM` and `SWEEP_GRANDFATHER_BEFORE` in `wrangler.toml`.

### 5. App configuration

Add the Worker URL to the git-ignored `Longhorn Artists Connect/10) Cloudkit/Secrets.plist`:

```xml
<key>VerificationServiceBaseURL</key>
<string>https://lac-verification.YOUR-SUBDOMAIN.workers.dev</string>
```

`StudentVerificationManager.isConfigured` is false without it, and the app
falls through as though verification didn't exist — so a build missing this key
behaves like the old build rather than walling users out.

## Rollout order

1. Deploy with `SWEEP_ACTION = "report"`.
2. Set `SWEEP_GRANDFATHER_BEFORE` to the unix timestamp of the day you ship.
   **Do this before step 5 or you will delete the entire pre-verification back
   catalogue.**
3. Ship the app build. New signups verify during onboarding; existing accounts
   are exempt (`StudentVerificationManager.markAccountEraIfNeeded`).
4. Watch `sweep_findings` for several nights:
   ```sh
   wrangler d1 execute lac-verification --remote \
     --command "SELECT record_type, COUNT(*) FROM sweep_findings GROUP BY record_type"
   ```
5. Only once the findings look like genuine unverified posts, switch
   `SWEEP_ACTION = "delete"`.

The sweep also aborts on its own if a single pass would flag more than half of
all records (`MAX_FLAG_RATIO`), which is what prevents an expired key or an
empty registry from turning into a mass deletion.

## Multi-school feeds: backfilling `schoolID`

Feeds are scoped by a `schoolID` field on each submission record, holding the
same registry slug this service uses (`ut-austin`, `berkeley`). The app side is
`SchoolScope`; a post is stamped on save and every feed query filters on it.

**CloudKit cannot query for "this field is nil."** An unstamped record is
therefore invisible to *every* school's feed, not merely misfiled — so the
order below is not optional.

### 1. Add the field to the schema, both environments

| Record type | Field | Type |
|---|---|---|
| `FilmSubmission` | `schoolID` | String (**queryable**) |
| `MusicSubmission` | `schoolID` | String (**queryable**) |
| `ReelSubmission` | `schoolID` | String (**queryable**) |
| `ProjectSubmission` | `schoolID` | String (**queryable**) |
| `EventSubmission` | `schoolID` | String (**queryable**) |
| `PhotographySubmission` | `schoolID` | String (**queryable**) |
| `DesignSubmission` | `schoolID` | String (**queryable**) |

Development *and* production. Without the field, `CloudKitManager.save` drops it
via the schema-rejection path and posts upload unstamped; without the queryable
index, every feed query fails outright.

### 2. Back-fill every existing record

```sh
wrangler secret put ADMIN_TOKEN            # openssl rand -base64 32
npm run deploy

export BASE_URL=https://lac-verification.YOUR-SUBDOMAIN.workers.dev
export ADMIN_TOKEN=...

node scripts/backfill-schools.mjs          # dry run
node scripts/backfill-schools.mjs --write  # for real
node scripts/backfill-schools.mjs          # confirm: stamped=0, no skips
```

Each record's school comes from its creator's verified school in D1. Creators
with no verification — the grandfathered accounts, exempt by design — get
`BACKFILL_DEFAULT_SCHOOL` (`ut-austin`), which must stay in step with
`SchoolScope.legacyDefault`.

Check the dry run's per-school tally before writing, and treat a non-empty
`skippedTypes` as a stop sign: those records are still unstamped.

### 3. Only then ship the app build that filters

Steps 1 and 2 are backwards-compatible with the build already in the field — an
older client ignores `schoolID` entirely. The filtering build is not
backwards-compatible with an unstamped database.

### Adding a school

1. Rows in `seed/schools.sql` for `schools` and `school_domains` (see Berkeley).
2. The slug in `SchoolScope.slugsByDisplayName`.
3. The display name in `UserProfileModel.otherSchools`.

Skip any one of the three and the school is either unpickable, unverifiable, or
its posts land in the wrong feed.

### The schoolID cross-check

`schoolID` is written by the client, so it's spoofable in exactly the way
membership of the record type is. The sweep cross-checks each record's
`schoolID` against its creator's verified school in D1 and records a
`school-mismatch` finding, alongside the existing `creator-unverified` one, in
the `reason` column of `sweep_findings`.

Two rules worth knowing before you read the findings table:

- **A mismatch is never deleted**, even under `SWEEP_ACTION="delete"`. The post
  is real work by a verified student and the only wrong thing about it is one
  string, so the remedy is to correct `schoolID` (the backfill endpoint already
  writes that field), not to destroy the work. Only `creator-unverified`
  deletes.
- **An unstamped record is not a mismatch.** `schoolID` is absent on every
  record until the backfill runs, and absent is not the same as wrong —
  flagging it would flag the whole container on the first night. Only a
  stamped-and-different value counts.

The rules live in `classifyRecord` in `src/sweep.ts`, which is pure and covered
by `npm test`; the sweep can delete real work, so they're tested there rather
than discovered against a live container.

## Follow-ups, in priority order

- **App Attest.** The app has none today, so the endpoints are reachable by
  anything that can make an HTTPS request; only rate limiting stands in the
  way. The `APP_ATTEST_REQUIRED` flag and the seam are in place, but attestation
  verification (CBOR parsing plus X.509 chain validation against Apple's root)
  is unimplemented — roughly 400 lines, and worse than useless if done wrong,
  which is why it isn't stubbed out half-finished.
- **Enrollment verification.** `verified_emails.enrollment_verified_at` and
  `enrollment_provider` exist unused so a vendor becomes an UPDATE rather than a
  migration.
- **Re-verification.** Nothing expires today. A yearly re-check is how you stop
  graduates accumulating.
- **Registry coverage.** `seed/schools.sql` has seven schools. See
  `seed/README.md` before launching anywhere new.

## Known gaps

- As of 2026-09-23 `npm run typecheck`, `npm test` (16 tests) and
  `npx wrangler deploy --dry-run` all pass. Nothing here has run against a real
  D1 or a real CloudKit key, so the SQL and the request signing are still
  unproven end to end.
- The grandfather flag is client-side (UserDefaults), so deleting and
  reinstalling the app drops the exemption. It only ever grants leniency, and
  the sweep's date-based grandfathering is authoritative.
- Housekeeping (pruning expired codes and rate-limit rows) is skipped when the
  sweep hits its safety abort, since it runs after the flagging stage.
