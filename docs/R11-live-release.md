# R11 coordinated LIVE release candidate

The owner explicitly approved this coordinated LIVE release on 16 November 2026. Publication and
verification are pending; this plan is not completion evidence. The owner accepted retaining the
existing rate settings and the original T14 three-email limitation. No SMTP change, paid service,
database migration, data change, rate-setting increase or replay of hosted fixtures is part of this
release.

The owner confirmed regenerating the private widget secret; it remains outside the repository and
must be entered directly in LIVE Supabase only after frontend verification.

## Prepared changes and verification

- The owner-supplied LIVE public site key is in `shared/auth-captcha.js`. No secret is in the files.
- Only the teacher HTML permits `https://challenges.cloudflare.com` in script, frame and connection
  policies. Inline scripts remain blocked and the pinned Supabase library/SRI is unchanged.
- The generated teacher mirror matches its staged source byte for byte. The pupil entry is unchanged
  and does not load CAPTCHA or allow the Cloudflare origin.
- TEST staging clears the LIVE widget configuration first, then applies an explicitly supplied TEST
  public key. Its CSP directives are replaced rather than duplicated.
- The complete mocked browser suite passed on this candidate, including actual current/TEST package
  token lifecycle and provider failure scenarios. Eleven offline staging checks passed. Existing
  teacher, recovery, pupil, access, timing and rate-message browser regressions passed.
- No hosted Auth tests were repeated. Previous database CI remains applicable because this candidate
  changes no SQL. After the candidate is pushed, normal PR/main CI still must pass.

Local package hashes and results are in [candidate evidence](r11/live-candidate.json). They
establish local preparation, not working LIVE provider enforcement or a completed release.

## Prerequisites and approval boundary

The earlier value sent in conversation may have been the widget secret. The owner must regenerate
that LIVE widget secret before using it and keep the replacement private. It must only be entered
directly into the LIVE Supabase CAPTCHA setting at the coordinated activation step below. A public
site key does not establish that a corresponding secret is safely available or that the hostname
configuration works. Confirm regeneration without sending the value.

No merge/publication or LIVE Supabase change is authorized by supplying a public key or accepting
the rate policy/email limitation. Obtain explicit approval for pushing this candidate to PR #7,
merging after green checks, publishing the separate teacher mirror and activating LIVE Turnstile.
The existing PR #7 does not yet contain this local LIVE configuration candidate.

## Release order after explicit approval

1. Recheck both repository main heads and PR #7's head. Review any intervening changes; do not
   overwrite them. Push the candidate to PR #7, wait for its normal checks and merge only the
   reviewed green head. This publishes the hub automatically from `main:/`.
2. Verify deployed hub assets against the approved source. Publish the reviewed generated teacher
   mirror to `history-teacher-dashboard` and verify its HTML, scripts, CSP, library/SRI and assets.
   Both teacher paths need the public widget configuration before server enforcement is enabled.
3. Ask the owner to hard-refresh the LIVE teacher page and confirm a real challenge can complete.
   The managed test environment previously could not reach Cloudflare; do not fabricate a solved
   challenge. Existing SMTP, Auth redirect and limits remain unchanged.
4. Only after both frontend deployments are ready, have the owner enter the regenerated secret in
   LIVE Supabase Auth bot protection and enable Turnstile. Do not enable it ahead of the frontend:
   pages without a valid token would be unable to sign in or request recovery email. Previously
   opened tabs must be refreshed. Keep a dashboard tab available for rollback.
5. Verify enforcement with one bounded missing-token request: expect `captcha_failed`. Then have the
   owner complete one normal LIVE sign-in/sign-out with an existing approved fictional teacher.
   Record owner-observed challenge/login separately from API-verified rejection. Check the password
   recovery request form's CAPTCHA behavior without sending another email solely for this release.
6. Observe normal CI passing on the merged `main` commit. Record deployed commit IDs, public-byte
   verification, owner configuration confirmation and actual smoke outcomes. R11 remains open until
   release verification is complete; T14 remains an accepted limitation rather than a fabricated
   pass.

The frontend-first transition retains the existing server policy until activation; a rendered widget
alone is not evidence of backend protection. Allow a short coordinated release window. No password
bursts, emails, password changes, new accounts or changes to real pupil data are planned.

## Rollback

If provider enforcement blocks expected sign-in, first have the owner disable LIVE CAPTCHA in
Supabase; do not remove token-capable frontend files while enforcement is still on. Keep SMTP and
rate settings unchanged. Then revert the approved frontend release commits through reviewed Git
reverts, regenerate/publish the matching teacher mirror, and verify restored public bytes.

The observed pre-release main heads are hub `d04821f9e43d4e0b300dffcc5a5b199aae36216b` and teacher
`309e45bb78f7d5582a7f1a56b1aa341f8ffb4f9f`; recheck before release. Do not hard reset remote
branches.
