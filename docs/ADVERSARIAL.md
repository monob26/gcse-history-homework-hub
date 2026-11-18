# Quiz Manager access and integrity results

The hosted run on 18 November 2026 used the isolated TEST project. The checks ran under `anon` and
`authenticated` in PostgreSQL using generated fictional pupils and teacher identities, then rolled
back. They ran before and after removing the code-check delay. The same SQL runs in the disposable
CI database. The hosted SQL run checks grants and behavior at the database boundary. A separate
HTTPS request verified the TEST pupil RPC profile and response.

| Check                                              | Disposable rebuild | Hosted TEST                                  |
| -------------------------------------------------- | ------------------ | -------------------------------------------- |
| Anonymous Quiz Manager table reads                 | Refused            | Refused                                      |
| Unapproved account sees quizzes/answers            | No quiz rows       | No quiz rows                                 |
| Unapproved account sees allocations                | No rows            | No rows, including after release             |
| Quiz Manager function EXECUTE allow-list           | Pass               | Catalog ACLs matched the initial LIVE export |
| Failure budget on list, home and start             | Pass               | Pass, including Retry-After                  |
| Unreleased or out-of-class deep link               | No quiz or start   | No quiz or start                             |
| Correct answer submitted after deadline            | Zero credit        | Zero credit                                  |
| Review before completion                           | Refused            | Refused                                      |
| Completed result and review                        | Score 24/25, pass  | Score 24/25, pass                            |
| Unapproved writes, imports and releases            | Refused            | Refused                                      |
| Publish before approval                            | Refused            | Refused                                      |
| Invalid import and draft atomicity                 | Refused, no draft  | Refused, no draft                            |
| Teacher reads results of unallocated class         | Refused            | Refused                                      |
| Approved colleague edits and publishes shared quiz | Pass               | Pass                                         |

The owner approved shared editing and publishing on 18 November 2026. This is the intentional
exception to R13's proposed creator-ownership check. Teacher approval, publication validation,
class-result isolation and pupil visibility still apply.
