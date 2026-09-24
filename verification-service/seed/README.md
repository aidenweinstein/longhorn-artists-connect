# Seeding the nationwide school registry

`schools.sql` only covers the six schools the app already knew about. For the
national rollout you want every accredited US institution and its mail domains.

## Sources

| Source | What it gives you | Notes |
|---|---|---|
| IPEDS `HD` file (NCES) | Every Title IV institution: name, state, `UNITID`, web address | Authoritative for *which schools exist*. Annual CSV download. |
| Hipo `university-domains-list` | Name → domain mapping, worldwide | Community-maintained, good coverage, some staleness. |
| EDUCAUSE `.edu` WHOIS | The registrant of every `.edu` | Only `.edu` registrants — misses subdomains and community colleges on `.cc.xx.us`. |

Practical approach: take IPEDS as the institution list, join Hipo on
name/domain to populate `school_domains`, then hand-fix the top ~200 schools
you actually expect users from. Coverage on the long tail matters less than
correctness on the schools you're launching at.

## Things that will bite you

- **Subdomains.** Many schools mail as `@mail.school.edu` or
  `@my.school.edu`. `domainCandidates()` in `src/util.ts` matches the most
  specific suffix first, so a single `school.edu` row covers subdomains — but
  only if you *want* that. If a school issues `@alumni.school.edu`, add that
  row explicitly with `kind='alumni'` or it inherits the parent's `student`.
- **Systems vs campuses.** `umich.edu` is Ann Arbor; Dearborn and Flint are
  `umd.umich.edu` and `umflint.edu`. Decide whether they're one school or three
  before users do it for you.
- **Community colleges** frequently aren't `.edu` at all — plenty live on
  `.cc.ca.us` and similar. The code doesn't require `.edu`; the registry is the
  allowlist. That's deliberate.
- **Non-`.edu` foreign universities** will show up eventually. Keep `enabled=0`
  rows rather than deleting, so you have a record of a considered decision.

## Applying

```sh
wrangler d1 execute lac-verification --remote --file=./seed/schools.sql
```

For bulk loads, generate a SQL file of `INSERT OR REPLACE` statements and batch
them a few thousand rows at a time; D1 has a statement-size ceiling.
