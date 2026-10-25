# Week 3 evaluation results — October 25, 2026

Revision: `week3-eval-v1`, implementation base `fd5a31e`.
Mode: mocked extraction HTTP plus synthetic recommendation evaluation.
Live paid evaluation: **not performed**.

The [JSON report](week3-evaluation.json) contains full fixture/configuration/prompt
digests, runtime observations and per-case accepted/rejected checks. Configuration
captured from the actual mocked helper request: `deepseek-flash`, JSON-object
response, thinking disabled, 512 tokens maximum, no streaming, 30-second timeout.
The provider model revision is unknown because DeepSeek was never contacted.

| Measurement | Local result |
| --- | ---: |
| Representative accepted extraction requests | 12 / 12 |
| Rejection/failure scenarios | 15 / 15 |
| Explicit field-level acceptance checks | 84 / 84 |
| Schema-valid accepted drafts | 12 / 12 |
| Saved-trip/no-write/sanitization checks | Passed in all 27 cases |
| Content recommendation acceptance scenarios | 10 / 10 |
| Synthetic held-out recommendation users | 24 |
| Reported acceptance failures | 0 |

| Synthetic metric | Content | Hybrid |
| --- | ---: | ---: |
| Recall@3 | 0.750000 | 1.000000 |
| NDCG@3 | 0.589777 | 1.000000 |
| HitRate@1 | 0.375000 | 1.000000 |

The held-out comparison retains #51's 256 training events, 24 separate future
ratings, fixed seed 20261025 and training digest. No held-out pair enters training
or inference history. The fixed synthetic structure and deliberately uninformative
content preferences make these implementation results unsuitable as real-user
validation. These are not 100% measured live extraction accuracy or prompt-injection
defense results: provider bodies were supplied by stubs.

The first `python evaluate_week3.py --check` run passed **198 selected regression
checks** and all report acceptance checks. Two runner lint findings were corrected
before final full-suite verification. Final checks passed **293 backend tests in
5.94 seconds without warnings**, Ruff, dependency compatibility (`pip check`) and
diff whitespace verification. This includes six additional API cases plus 32 new
evaluation tests beyond the prior 255-check suite.

Regression detection is explicit: tests compare the current system-prompt,
configuration and fixture hashes to this reviewed baseline and check exact field
acceptance/error behavior. A test deliberately supplies a wrong pace expectation
and confirms it is reported as `field:pace`; the CLI nonzero failure path is tested.
Future changes must explain baseline/fixture revision updates, not overwrite the
expected report to hide failing checks.

[The suite guide and Kyle handoff](../week3-evaluation.md) provides the single offline
command, comparison procedure, evidence distinctions and remaining delivery gates.
Required CI, teammate review/merge, actual integrated artifact verification and
issue/PR links remain pending. No secret, real saved data, deployment, external
message or live provider request was used for this implementation.
