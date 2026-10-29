"""Seed shape, cleanup SQL and the offline training command, with no network or real IDs."""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import httpx
import pytest

import seed_demo_interactions as seed
import train_collaborative_model as trainer
from app.recommendations.collaborative import CollaborativeModel, TrainingData, train
from app.recommendations.contracts import Interaction

CATALOG = [uuid4() for _ in range(seed.CATALOG_SIZE)]
PROFILES = {letter: uuid4() for letter in seed.LETTERS}
START = datetime(2026, 11, 1, tzinfo=UTC)


def plan_events(user_letters=seed.LETTERS):
    events = []
    for letter in user_letters:
        for index, kind in seed.PLAN[letter]:
            events.append(Interaction(
                id=uuid4(), user_id=PROFILES[letter], location_id=CATALOG[index], interaction_type=kind,
                interaction_value=-1 if kind == "left_swipe" else 1,
                created_at=START + timedelta(minutes=len(events)), provenance="real",
            ))
    return events


def test_seed_plan_clears_every_gate_and_leaves_fallback_cases():
    model = train(TrainingData(provenance="real", location_ids=CATALOG, interactions=plan_events()))
    assert model is not None
    target = PROFILES["A"]
    assert model.user_counts[model.user_ids.index(target)] >= 3
    assert model.user_counts[model.user_ids.index(PROFILES["E"])] < 3
    modes = {model.score(target, location)[1] for location in CATALOG}
    assert modes == {"hybrid", "sparse_location", "unseen_location"}
    supported = [loc for loc in CATALOG if model.score(target, loc)[1] == "hybrid"]
    assert len(supported) >= 5
    assert model.score(PROFILES["E"], CATALOG[0])[1] == "insufficient_history"
    assert model.score(uuid4(), CATALOG[0])[1] == "unseen_user"


def test_plan_has_a_left_swipe_exclusion_and_only_valid_event_types():
    assert any(kind == "left_swipe" for kind in (k for _, k in seed.PLAN["A"]))
    assert {kind for events in seed.PLAN.values() for _, kind in events} <= {"left_swipe", "right_swipe", "save"}
    assert max(index for events in seed.PLAN.values() for index, _ in events) < seed.CATALOG_SIZE - 1


def manifest():
    return {"supabase_ref": "ref", "accounts": {
        letter: {"email": f"lagaw-demo-staging-{letter.lower()}@example.invalid",
                 "profile_id": str(PROFILES[letter]), "auth_user_id": str(uuid4()),
                 "events": [str(uuid4()), str(uuid4())], "trip_id": str(uuid4()) if letter in "AE" else None}
        for letter in seed.LETTERS}}


def test_cleanup_sql_names_exact_ids_and_rolls_back_by_default():
    data = manifest()
    sql = seed.cleanup_sql(data, commit=False)
    assert sql.rstrip().endswith("rollback;") and sql.startswith("-- Exact-ID cleanup")
    for account in data["accounts"].values():
        for value in (*account["events"], account["profile_id"], account["auth_user_id"], account["email"]):
            assert value in sql
    assert "delete from auth.users where id in" in sql and "email in" in sql
    assert "cascade" in sql.lower()  # Documented scope of the profile delete.
    assert seed.cleanup_sql(data, commit=True).rstrip().endswith("commit;")
    assert "id in (null)" in seed.cleanup_sql({"supabase_ref": "ref", "accounts": {}}, commit=False)


def test_private_files_stay_outside_the_repository_and_are_never_overwritten(tmp_path):
    with pytest.raises(seed.SeedFailed):
        seed.private_path(seed.ROOT / "docs", "staging", "manifest.json")
    path = seed.private_path(tmp_path, "staging", "manifest.json")
    seed.write_private(path, "{}")
    assert oct(path.stat().st_mode & 0o777) == "0o600"
    with pytest.raises(seed.SeedFailed):
        seed.write_private(path, "{}")


def test_targets_are_pinned_to_known_projects_and_apis(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://zjnuqqtbapbpudsjbpif.supabase.co")
    with pytest.raises(seed.SeedFailed):
        seed.supabase_settings("staging")
    seed.supabase_settings("production")
    with pytest.raises(ValueError):
        seed.validate_api("production", "https://example.com")
    with pytest.raises(ValueError):
        seed.validate_api("production", "http://127.0.0.1:8000")


# ---- offline training command ---------------------------------------------------

class FakeProject:
    """Answers the Data API calls the trainer makes; filters by the requested owner."""

    def __init__(self, events, catalog=CATALOG):
        self.events, self.catalog = events, catalog
        self.requests = []

    def handle(self, request):
        self.requests.append(request)
        assert request.method == "GET"
        params = request.url.params
        if request.url.path.endswith("/locations"):
            rows = [{
                "id": str(loc), "name": "Public place", "description": None, "category": "cafe", "vibe_tags": [],
                "address": None, "latitude": None, "longitude": None, "opening_hours": {},
                "estimated_cost_min": 1, "estimated_cost_max": 2, "typical_visit_duration": 30,
                "suitable_group_types": ["friends"], "image_url": None, "is_active": True,
            } for loc in self.catalog]
            return httpx.Response(200, json=rows[int(params["offset"]):int(params["offset"]) + int(params["limit"])])
        owner = params["user_id"].removeprefix("eq.")
        rows = [{**e.model_dump(mode="json", exclude={"provenance"})} for e in self.events if str(e.user_id) == owner]
        return httpx.Response(200, json=rows[int(params["offset"]):int(params["offset"]) + int(params["limit"])])


@pytest.fixture
def private(tmp_path):
    return tmp_path / "private", tmp_path / "artifacts"


def run_trainer(monkeypatch, tmp_path, capsys, events, profiles=None, base="https://vnpkyvtbupnquvirzlzp.supabase.co/rest/v1/",
                environment="staging", output=None):
    from app.database import LocationDatabase

    project = FakeProject(events)
    rest = httpx.Client(base_url=base, transport=httpx.MockTransport(project.handle))

    def connection():
        yield LocationDatabase(rest)

    monkeypatch.setattr(trainer, "get_database", connection)
    monkeypatch.setattr(trainer, "ARTIFACTS", tmp_path / "model_artifacts")
    tmp_path.mkdir(parents=True, exist_ok=True)
    allow = tmp_path / "profiles.txt"
    allow.write_text("# demo\n" + "\n".join(str(p) for p in (profiles or PROFILES.values())) + "\n")
    output = output or tmp_path / "model_artifacts" / "staging.json"
    code = trainer.main(["--environment", environment, "--profiles-file", str(allow), "--output", str(output)])
    return code, capsys.readouterr().out, output, project


def test_trainer_writes_a_private_artifact_and_prints_only_counts(monkeypatch, tmp_path, capsys):
    code, out, path, project = run_trainer(monkeypatch, tmp_path, capsys, plan_events())
    assert code == 0, out
    model = CollaborativeModel.load(path, provenance="real")
    assert (len(model.user_ids), len(model.item_ids), sum(model.user_counts)) == (5, 10, 24 - 2)
    assert oct(path.stat().st_mode & 0o777) == "0o600"
    assert f"Training digest: {model.training_digest}" in out and "Model state: trained" in out
    assert "Users: 5; items: 10; pairs: 22" in out
    for identifier in (*map(str, PROFILES.values()), *map(str, CATALOG), *map(str, model.training_event_ids)):
        assert identifier not in out
    # Only allowlisted owners were ever requested, and only by exact owner filter.
    owners = {r.url.params["user_id"] for r in project.requests if "user_id" in r.url.params}
    assert owners == {f"eq.{p}" for p in PROFILES.values()}


def test_trainer_ignores_non_allowlisted_users_and_stays_below_the_gates_without_them(monkeypatch, tmp_path, capsys):
    outsider = uuid4()
    extra = Interaction(id=uuid4(), user_id=outsider, location_id=CATALOG[0], interaction_type="save",
                        interaction_value=1, created_at=START, provenance="real")
    code, out, path, project = run_trainer(monkeypatch, tmp_path, capsys, [*plan_events(), extra])
    assert code == 0, out
    assert outsider not in CollaborativeModel.load(path, provenance="real").user_ids
    assert not any(str(outsider) in str(r.url) for r in project.requests)
    code, out, path, _ = run_trainer(monkeypatch, tmp_path / "second", capsys, plan_events("AB"),
                                     profiles=[PROFILES["A"], PROFILES["B"]])
    assert code == 1 and "Model state: none" in out and not path.exists()


def test_trainer_refuses_wrong_project_repo_paths_and_oversized_artifacts(monkeypatch, tmp_path, capsys):
    code, out, path, _ = run_trainer(monkeypatch, tmp_path, capsys, plan_events(),
                                     base="https://zjnuqqtbapbpudsjbpif.supabase.co/rest/v1/")
    assert code == 1 and "not the staging project" in out and not path.exists()
    code, out, path, _ = run_trainer(monkeypatch, tmp_path / "elsewhere", capsys, plan_events(),
                                     output=tmp_path / "elsewhere" / "outside.json")
    assert code == 1 and "under backend/model_artifacts" in out
    monkeypatch.setattr(trainer, "SECRET_LIMIT_BYTES", 100)
    code, out, path, _ = run_trainer(monkeypatch, tmp_path / "big", capsys, plan_events())
    assert code == 1 and "delivery limit" in out and not path.exists()
    inside = trainer.ROOT / "docs" / "profiles.txt"
    with pytest.raises(trainer.TrainingFailed):
        trainer.read_profiles(inside)


def test_trainer_rejects_bad_allowlists(tmp_path):
    for text in ("not-a-uuid\n", "", f"{UUID(int=0)}\n", f"{PROFILES['A']}\n{PROFILES['A']}\n"):
        path = tmp_path / "bad.txt"
        path.write_text(text)
        with pytest.raises(trainer.TrainingFailed):
            trainer.read_profiles(path)


def test_events_for_inactive_locations_are_dropped_before_training(monkeypatch, tmp_path, capsys):
    events = plan_events()
    events.append(Interaction(id=uuid4(), user_id=PROFILES["A"], location_id=uuid4(), interaction_type="save",
                              interaction_value=1, created_at=START, provenance="real"))
    code, out, _, _ = run_trainer(monkeypatch, tmp_path, capsys, events)
    assert code == 0 and "Interaction events read: 24; in the active catalog: 23" in out
