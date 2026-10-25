# Initial content-based evaluation — October 25, 2026

Scope: offline #33 content baseline built on #32 fixtures at base commit `4c844c4`.
No production data, real user interactions, secrets or hosted inference were used.

The first behavioral run passed all 25 new tests after correcting UUID/string
comparisons in test assertions. All ten fixture scenarios returned their eligible
examples and reproducible outputs, and the automated top-choice checks passed:

| Scenario | First result | Result count |
| --- | --- | --- |
| Budget cafe | Budget cafe test variant | 3 |
| Heritage | The Negros Museum | 3 |
| Family nature | Free park test variant | 3 |
| Premium food | Premium dining test variant | 4 |
| Cold start | Free park test variant | 3 |
| Cold start without tags | Free park test variant | 1 |
| Accessibility / indoor | Budget cafe test variant | 1 |
| Distance / duration | Free park test variant | 2 |
| No compatible locations | Empty | 0 |
| Explicit exclusion | Free park test variant | 2 |

At the same budget, switching cafe/relaxing tags to nature changes first place
from the synthetic cafe to the synthetic park. With no tags, switching preferred
category from museum to cafe changes first place accordingly. Premium dining is
excluded at PHP 1199 and becomes eligible at PHP 1200. Zero budget returns only
the confirmed-free synthetic park. Catalog reversal leaves results unchanged.

An initial warm local benchmark on Windows / Python 3.12.10 ran 1,000 calls with
14 candidates per call: median **0.1145 ms**, p95 **0.1371 ms**. These are one-run
observations, not load-test or deployed-API measurements. Saved evidence can have
different timings when rerun; behavioral outputs must remain reproducible.

The [JSON report](content-based-evaluation.json) records each result, reason and
score plus a fresh benchmark. The [model guide](../content-based-recommender.md)
defines weights, formulas, filters, test commands and future hybrid integration.

Limitations: this is a tiny synthetic evaluation without independent real-user
relevance labels. Nine original destinations have unknown upper costs and fail
the existing hard budget policy. Success here establishes behavior and schema
compatibility; it does not establish real-world recommendation accuracy.

Final offline verification passed **167 backend tests**, including **26 new
content-based checks**, Ruff and the diff whitespace check. The one existing
Starlette HTTPX deprecation warning remains. The saved behavioral evidence is
compared against fresh evaluation output by an automated test; timing is excluded
from that equality check because local measurements vary.

PR review, CI, merge and
integrated artifact verification remain pending. No hosted route was added or
deployed, so no hosted recommendation acceptance is claimed.
