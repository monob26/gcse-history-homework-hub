# Handoff backup and credential review

15 November 2026. Owner approved backup, pending-file review and local commits only.
No application, database, browser or hosted-access tests were run for this handoff.
No Supabase changes, GitHub push/merge or website publication occurred.

## Recovery backup

Local directory: /workspace/handoff-backups/r2-r4-20261115T212725Z

For each repository, an all-refs Git bundle preserves commit/branch history, and a
working-files archive preserves tracked and nonignored files, including uncommitted
and untracked work. Bundle integrity and archive entry counts were checked. MANIFEST.json
records original branch/HEAD/status, file counts, sizes and SHA256 checksums. Backups
are outside the repositories and are not committed or proposed for upload.

The backup includes 80 Hub working files and 2 teacher working files from before
handoff edits, plus the historical permissions assessment. Ignored runtime credentials,
Supabase link temp files, caches, dependencies and logs are deliberately excluded.
The two backed-up checkouts remain in place. New documentation is preserved by the
handoff commits themselves; recover the pre-handoff state from the private backup.

## Pending-file review

All modified/untracked nonignored files in both repositories were scanned before
backup and again after handoff documentation was prepared. Checks cover Supabase
PAT/server-secret formats, GitHub credentials, private keys, encoded JWTs, database
URLs containing passwords, AWS access-key formats and literal secret assignments.
Available runtime values whose names identify passwords/tokens/secrets/private keys
were also compared without printing them. No credential findings were detected.

The content review distinguishes schema-only metadata and fictional account IDs
from pupil rows or credentials. predeploy-*.json contains catalog metadata, not pupil
row exports. The confirmed account emails/UUIDs identify only the three owner-created
fictional users. Existing quiz ID, project ref, UUIDs and SHA256 checksums are identifiers,
not credentials. Fixture SQL generates pupil codes server-side and never records them.
The repository's existing publishable browser key is public by design; no new server
key is introduced. Runner examples contain explicit offline placeholders, not passwords.

No secrets, password hashes, actual pupil codes, session/attempt tokens or reset links
are included in the pending handoff files. The owner-created passwords remain outside
Git. No scanner can prove the absence of every conceivable secret; these automated
checks were supported by review of the pending content and its metadata-only sources.

Machine-readable file coverage/findings: docs/handoff-secret-scan.json. The scan did
not retrieve new credentials or attempt to authenticate to hosted services.
