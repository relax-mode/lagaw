# Hybrid recommendation comparison — October 25, 2026

Base: `fe9c02c` (main after merged prerequisites #32/#33 and extraction work).
Model: signed rank-3 NumPy SVD, content/collaborative blend 0.60/0.40.
The [model guide](../hybrid-recommender.md) defines weights, support thresholds,
fallbacks and artifact procedure. The [JSON evidence](hybrid-evaluation.json)
records training digest, held-out targets, per-user rankings, reasons and metrics.

| Metric | Content baseline | Hybrid |
| --- | ---: | ---: |
| Recall@3 / HitRate@3 | 0.750000 | 1.000000 |
| NDCG@3 | 0.589777 | 1.000000 |
| HitRate@1 | 0.375000 | 1.000000 |

Twenty-four synthetic users have one held-out positive each. The training snapshot
contains 256 events, including the original sixteen S3-01 synthetic events; 24
future held-out ratings are kept separate. No held-out user/location pair or event
ID appears in training. Both methods exclude training-seen places and receive the
same candidates/history. The generated clusters are intentionally recoverable;
the baseline has no tag/category input and equal candidate costs. These are
implementation checks under a constructed signal, not real-world quality evidence.

Behavior observed: supported fitted users receive blended scores; unknown/sparse
users/items receive content scores; absent/corrupt/wrong-provenance artifacts use
the baseline. Hard constraints, left swipes, exclusions, stable sorting and top N
remain enforced. Reordering training inputs leaves the fitted artifact unchanged.
Repeated interaction events do not inflate distinct-place support.

Reproduce from `backend`:

```powershell
python -m app.recommendations.hybrid_fixtures
python -m app.recommendations.evaluate_hybrid --output ../docs/evidence/hybrid-evaluation.json
python -m pytest test_hybrid_recommendations.py -v
python -m pytest -q
ruff check .
```

The initial focused run passed 27 tests; two test-setup Decimal assignment warnings
were corrected before final verification. Additional fallback/evaluation-source
checks were added. Final verification passed **255 backend tests**, including
**38 hybrid checks**, in 4.49 seconds with no warnings. Ruff, dependency
compatibility (`pip check`) and diff whitespace checks passed. No paid
provider, live database, production model, endpoint, deployment or real-user
validation was used. The seed is 20261025; SVD itself has no stochastic training.

Pending: actual CI run, teammate review, issue/PR evidence links, merge, integrated
artifact checks and deployed verification where applicable. No Definition of Done
release gate is claimed complete from local test success alone.
