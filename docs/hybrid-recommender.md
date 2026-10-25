# Offline collaborative and hybrid recommendation (#51)

This adds cross-user matrix factorization to the [content baseline](content-based-recommender.md)
without an API, interaction collection, extraction, UI, or scheduling dependency.
The inference interface remains `recommend(RecommendationRequest) -> RecommendationResponse`
and uses S3-01 schema v1 IDs, scores and reason strings.

## Model choice and training data

`signed-svd-v1` uses NumPy's [singular value decomposition](https://numpy.org/doc/stable/reference/generated/numpy.linalg.svd.html)
as the permitted equivalent matrix-factorization implementation instead of LightFM.
It is a low-rank collaborative model, not a content-only proxy. NumPy supplies
portable wheels on the project's Python 3.12 Windows/Linux environments; this avoids
adding LightFM's native build requirement to this first offline implementation.
It is not equivalent to LightFM's WARP/BPR objective, side-feature handling or
implicit-feedback confidence model. The scope/library choice is recorded in the
sprint log and remains within the approved matrix-factorization feature.

`TrainingData` in `app/recommendations/collaborative.py` is a separate cross-user
contract: `provenance` (`synthetic` or `real`), `location_ids`, and `interactions`
(the existing S3-01 event schema). Every event must match the declared provenance
and reference a supplied location. Mixing synthetic and real data is rejected.
The inference request still contains only the target user's snapshot; it is not
repurposed as a training matrix. No raw names, emails or credentials are needed.

Aggregate per user/location pair using the **latest event in each channel**:

| Channel | Raw contribution |
| --- | --- |
| Swipe (left/right share one channel) | Left -1, right +1 |
| Save | +2 |
| Rating | `rating_value - 3`: 1 gives -2, 3 gives 0, 5 gives +2 |

Sum the three channel contributions and divide by 5 to obtain a signed affinity
in `[-1,1]`. Latest is ordered by offset-aware timestamp, then UUID string on equal
timestamps. Repeated saves/ratings/swipes do not accumulate unbounded weight.
Exact repeated event IDs are idempotent; conflicting payloads for one ID are
rejected. Different event IDs at the same pair remain legitimate history but do
not inflate distinct-place support counts. Net-zero affinities are omitted.
`interaction_value` is validated as finite but deliberately not multiplied in:
weights are computed here from event type/rating to avoid double-weighting stored
values. Production ingestion/aggregation changes must be agreed explicitly.

For serving, S3-01's conservative **any-left-swipe exclusion still applies**, even
when a later swipe or a save changes the training affinity. This preserves the
existing contract; it is not latest-event serving semantics.

Sort UUID mappings before building the user-by-location signed matrix. Missing
pairs are zero (unknown/neutral, not explicit dislikes). Compute
`A = U diag(s) Vt`, then retain `k = min(3, min(matrix_shape)-1)` components.
Store `U_k diag(s_k)` and `Vt_k.T`; a dot product predicts affinity. Component
signs are canonicalized for stable artifact serialization. Full SVD is deterministic
and has no stochastic training seed. Fixture sampling uses fixed seed `20261025`;
tests also shuffle input using seed 42 and confirm identical artifacts/results.
Floating-point differences across NumPy/BLAS versions remain possible; use the
recorded dependency/environment versions when comparing factors.

## Thresholds, normalization and fallback

Training requires at least **3 users, 3 observed locations and 8 distinct nonzero
user/location pairs**. Empty, globally sparse, constant matrices or SVD convergence
failures produce no collaborative model. Dense training is capped at **1,000,000
matrix cells**; exceeding this raises a training error rather than allocating an
unbounded dense matrix. This is a small offline baseline, not scalable production
matrix infrastructure.

At inference, a user needs **3 distinct nonzero training locations** and an item
needs **2 distinct contributing training users**. These are support thresholds,
not learned confidence scores. Counts come from the fitted artifact, so adding
request events does not falsely claim the model has learned them; retrain to
incorporate new interactions. An absent user falls back even if the request includes
many new events. A known fitted user may have history even if a caller supplies an
empty request history; callers must supply relevant exclusions/swipes correctly.

Normalize predicted affinity `r` as `(clip(r, -1, 1) + 1) / 2`. Zero maps to 0.5.
Use the unchanged normalized S3-02 content score and blend:

```text
hybrid = 0.60 * content + 0.40 * collaborative
```

The weights and thresholds are initial engineering choices, not tuned or calibrated
on real users. Scores are in `[0,1]` but are not satisfaction probabilities; sharing
a numeric range does not establish statistical calibration. Content scores also
renormalize when tag/category preferences are omitted. Future real-data evaluation
must revisit calibration, thresholds and blend weights.

If the model is absent, the engine returns the exact S3-02 response. Missing,
unreadable, corrupt, wrong-version, wrong-provenance or schema-invalid artifacts
load as no model through `from_artifact`. If a user/item is unseen or insufficiently
supported, that candidate uses the full content score without multiplying by 0.6.
Per-candidate reasons identify `unseen_user`, `insufficient_history`,
`unseen_location` or `sparse_location`; blended reasons include both component
scores and weights. A nonfinite predicted dot product also falls back.

Apply the same content compatibility checks and any-left-swipe exclusions before
scoring. Never blend two independently truncated top-N lists. All eligible
candidates are scored, then sorted by descending score with UUID string ties.
Model-present scores are rounded to 12 decimal places for negligible numeric ties;
return the requested limit afterward. Validate outputs against S3-01 again. Cold,
unseen and sparse candidates can therefore compete with blended candidates on the
same list. The absence of a relevance threshold and cheaper-place bias from the
baseline remain; an uncalibrated candidate fallback may affect relative ranking.

## Artifact and Python procedure

From `backend`, after installing `requirements-dev.txt`:

```powershell
python -m app.recommendations.hybrid_fixtures
python -m app.recommendations.evaluate_hybrid --output ../docs/evidence/hybrid-evaluation.json --artifact model_artifacts/synthetic-svd.json
python -m pytest test_hybrid_recommendations.py -v
```

The CLI trains on **training events only**. The optional artifact is written to the
gitignored `backend/model_artifacts/` directory. JSON artifacts contain version,
provenance, training SHA-256 digest, training event IDs, sorted UUID mappings,
support counts, rank, factor arrays and NumPy version. They contain no executable
pickle/joblib objects. Loading validates finite factors, dimensions, versions,
mappings and support counts. Load only team-controlled paths; a digest identifies
training data, it is not a signature or proof an untrusted model is safe/correct.
Use explicit expected provenance to prevent a synthetic fixture model being loaded
as a real-user model. Real interaction UUIDs and learned factors are private backend
data and must not be committed or sent to Flutter.

```python
from pathlib import Path
from app.recommendations.collaborative import TrainingData, train
from app.recommendations.hybrid import HybridRecommender

# Cross-user data loaded/authorized by the backend, outside request processing:
training = TrainingData.model_validate(training_payload)
model = train(training)  # None for insufficient global training data
engine = HybridRecommender(model)
response = engine.recommend(validated_request)

# Or load a previously approved model at service startup:
engine = HybridRecommender.from_artifact(
    Path("model_artifacts/real-svd.json"), provenance="real",
)
response = engine.recommend(validated_request)
```

For real-data training, supply a single authorized `TrainingData` snapshot marked
`real`, call `train`, and save a non-null model with `model.save(path)`. Do not use
the synthetic evaluation CLI as a production training job. Train/retrain outside
HTTP request handling. No auto-training, artifact deployment hook, model registry,
production data collection or backend route is added here. A caller can observe
`engine.model is None` at startup and log that state without exposing identifiers.
Bad training data raises validation errors rather than silently being dropped.

## Evaluation design and limits

The original sixteen S3-01 synthetic events remain in the training fixture. A
separate deterministic extension adds 24 users in four obvious interest clusters,
12 fully synthetic destinations, and fabricated known costs under separate UUIDs.
Every extended user has two liked cluster destinations (right swipe + save) and
six negative destinations. One other positive user/location pair is held out as a
future rating. Total: **256 training events and 24 held-out events**.

Every held-out pair is absent from training, including other event types at that
same pair. Held-out IDs and labels never enter inference history. The same item
can appear in other users' training history, as required for collaborative inference.
Dates put held-out ratings after the training snapshot. The evaluator rejects
leaking pairs/IDs and real labels; it computes both methods over the same candidate
catalog and excludes all training-seen places for discovery evaluation. This extra
evaluation exclusion is applied identically to both methods; ordinary inference
still permits previously saved/positively visited places unless explicitly excluded.

One positive target per user gives Recall@3 equal to HitRate@3; NDCG@3 rewards a
target higher in the list (discount `1/log2(rank+1)`), and HitRate@1 reports first
place recovery. Macro-average over all 24 users. Original S3-01 users are training
support, not evaluated held-out subjects. Tests check fresh summaries against the
[saved comparison](evidence/hybrid-evaluation.json), model reproducibility,
threshold/fallback selection, artifact validation, repeated interactions, constraints
and all ten original content scenarios with the collaborative model unavailable.

The extension deliberately has no explicit tag/category preferences and identical
costs, leaving the content baseline with ties. It tests recovery of a fabricated
latent cluster signal, not a fair estimate of personalized content-vs-hybrid gains
on real travelers. There are only four discovery candidates per user after seen
exclusions. The perfect synthetic hybrid scores must not be presented as real-user
validation. This is one fixed holdout, not cross-validation or tuning evidence.
Missing=zero SVD underweights unknown interactions, uses no confidence weighting
or learned biases, and can lose recall in genuinely sparse data. Evaluate larger,
independently collected chronological real-data splits before making quality claims.

See [initial comparison results](evidence/hybrid-results.md). Required CI, teammate
review, merged/integrated artifact checks and any applicable deployed-backend
verification remain release gates. No new hosted endpoint exists to exercise in
this offline issue; no deployed inference or artifact availability is claimed.
