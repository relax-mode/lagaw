"""Database failures and races that mocked HTTP responses cannot establish."""

import os
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from threading import Barrier
from uuid import uuid4

import psycopg
import pytest
from psycopg.types.json import Jsonb
from trip_test_support import require_disposable_services

pytestmark = pytest.mark.db
SAVE = "select public.save_generated_itinerary(%s,%s,%s,%s,%s,%s)"


@pytest.fixture
def sql():
    url = os.environ.get("DATABASE_URL", "")
    require_disposable_services(url, os.environ.get("CI_POSTGREST_URL", ""))
    with psycopg.connect(url.replace("postgresql+psycopg://", "postgresql://", 1)) as connection:
        try:
            yield connection
        finally:
            connection.rollback()


def seed(connection):
    owner, trip, first, second = (uuid4() for _ in range(4))
    connection.execute("insert into public.users(id,name,email) values (%s,'Issue54 transaction fixture',%s)",
                       (owner, f"issue54-{owner}@example.invalid"))
    connection.execute("""insert into public.trips(id,user_id,title,start_date,end_date,budget_min,budget_max)
        values (%s,%s,'Issue54 transaction fixture','2026-11-02','2026-11-02',0,500)""", (trip, owner))
    for identifier in (first, second):
        connection.execute("""insert into public.locations(id,name,category,latitude,longitude,
            opening_hours,estimated_cost_min,estimated_cost_max,typical_visit_duration)
            values (%s,'Issue54 transaction fixture','cafe',10.67,122.95,%s,10,20,30)""",
            (identifier, Jsonb({"monday": [{"open": "09:00", "close": "18:00"}]})))
    connection.execute("""insert into public.itinerary_items(trip_id,location_id,day_number,visit_order)
        values (%s,%s,1,1)""", (trip, first))
    connection.execute("update public.trips set estimated_total_cost = 123 where id = %s", (trip,))
    state = connection.execute("select public.itinerary_state(%s,%s)", (owner, trip)).fetchone()[0]
    locations = connection.execute("select jsonb_agg(to_jsonb(l) order by id) from public.locations l where id in (%s,%s)",
                                   (first, second)).fetchone()[0]
    proposed = [{"location_id": str(identifier), "day_number": 1, "visit_order": order,
                 "arrival_time": arrival, "departure_time": departure,
                 "estimated_travel_time": 0, "estimated_cost": "20.00",
                 "recommendation_score": 0.9, "recommendation_reason": "Verified transaction fixture"}
                for identifier, order, arrival, departure in (
                    (first, 1, "09:00", "09:30"), (second, 2, "09:45", "10:15"))]
    return owner, trip, state, proposed, locations


def test_insert_failure_rolls_back_deleted_old_items_inserted_rows_and_total(sql):
    owner, trip, before, proposed, locations = seed(sql)
    sql.execute("""create function pg_temp.issue54_fail_second() returns trigger language plpgsql as $$
        begin if new.visit_order = 2 then raise exception 'Issue54 forced second insert failure';
        end if; return new; end; $$""")
    sql.execute("""create trigger issue54_force_failure before insert on public.itinerary_items
        for each row execute function pg_temp.issue54_fail_second()""")
    with pytest.raises(psycopg.Error), sql.transaction():
        sql.execute(SAVE, (owner, trip, before["revision"], True, Jsonb(proposed), Jsonb(locations)))
    after = sql.execute("select public.itinerary_state(%s,%s)", (owner, trip)).fetchone()[0]
    assert after == before  # Includes original item UUID and total, not merely a row count.


@pytest.mark.parametrize("mutation", ["overlap", "closed", "budget", "location_edit", "new_rejection", "stale", "foreign"])
def test_invalid_or_stale_replacement_preserves_every_saved_field(sql, mutation):
    owner, trip, before, proposed, locations = seed(sql)
    revision = before["revision"]
    caller = owner
    if mutation == "overlap":
        proposed[1]["arrival_time"] = "09:15"
    elif mutation == "closed":
        proposed[0].update(arrival_time="19:00", departure_time="19:30")
    elif mutation == "budget":
        proposed[1]["estimated_cost"] = "1000.00"
    elif mutation == "location_edit":
        sql.execute("update public.locations set name='Changed concurrently' where id=%s", (proposed[0]["location_id"],))
    elif mutation == "new_rejection":
        sql.execute("""insert into public.user_location_interactions(user_id,location_id,interaction_type,interaction_value)
            values (%s,%s,'left_swipe',-1)""", (owner, proposed[0]["location_id"]))
    elif mutation == "stale":
        revision = "0" * 32
    elif mutation == "foreign":
        caller = uuid4()
    baseline = sql.execute("select public.itinerary_state(%s,%s)", (owner, trip)).fetchone()[0]
    with pytest.raises(psycopg.Error), sql.transaction():
        sql.execute(SAVE, (caller, trip, revision, True, Jsonb(proposed), Jsonb(locations)))
    assert sql.execute("select public.itinerary_state(%s,%s)", (owner, trip)).fetchone()[0] == baseline


def test_rpc_execution_is_server_only(sql):
    for name in ("itinerary_state(uuid,uuid)", "itinerary_revision(uuid)",
                 "save_generated_itinerary(uuid,uuid,text,boolean,jsonb,jsonb)"):
        for role in ("anon", "authenticated"):
            assert not sql.execute("select has_function_privilege(%s,%s,'EXECUTE')", (role, name)).fetchone()[0]
        assert sql.execute("select has_function_privilege('service_role',%s,'EXECUTE')", (name,)).fetchone()[0]


def test_simultaneous_confirmations_allow_exactly_one_complete_replacement(sql):
    owner, trip, before, proposed, locations = seed(sql)
    # This test needs independent committed sessions. Register exact cleanup first.
    dsn = sql.info.dsn
    try:
        sql.commit()
        barrier = Barrier(2)

        def generate():
            with psycopg.connect(dsn) as connection:
                barrier.wait(timeout=10)
                try:
                    result = connection.execute(SAVE, (owner, trip, before["revision"], True,
                                                        Jsonb(deepcopy(proposed)), Jsonb(locations))).fetchone()[0]
                    connection.commit()
                    return result
                except psycopg.Error as error:
                    assert error.sqlstate == "PT409"
                    return None

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(generate) for _ in range(2)]
            results = [future.result(timeout=20) for future in futures]
        assert sum(result is not None for result in results) == 1
        final = sql.execute("select public.itinerary_state(%s,%s)", (owner, trip)).fetchone()[0]
        assert final == next(result for result in results if result is not None)
        assert len(final["items"]) == 2 and final["trip"]["estimated_total_cost"] == 40
    finally:
        sql.rollback()
        sql.execute("delete from public.users where id=%s", (owner,))
        sql.execute("delete from public.locations where id in (%s,%s)",
                    tuple(row["location_id"] for row in proposed))
        sql.commit()
