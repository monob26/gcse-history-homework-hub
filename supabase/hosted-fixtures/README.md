# Owner-approved hosted fixtures

These are environment-specific fixture migrations, kept separate from the replayable
application schema migrations. They depend on owner-created fictional Auth accounts;
never include them in blanket db push or local fresh schema reconstruction.

The owner explicitly approved only 11 application records. Migration
20261115203341_r2_hosted_access_fixtures.sql was applied individually to
inxsjdogxvqbvxydxmym via MCP as hosted version 20261115203420. It resolves Auth
UUIDs by approved fictional emails and atomically inserts 3 teacher approvals,
2 classes, 2 allocations, 2 pupils and 2 synthetic completed attempts. It generates
pupil codes server-side without printing/exporting them. There are no schema edits,
Auth user creation, invitations, updates, deletes, signups or logins.

Do not replay this migration: it intentionally fails on existing fixture records.
No cleanup or hosted test execution is authorised by the fixture approval.
Verification: docs/r2/hosted-preparation/fixture-creation.json.
