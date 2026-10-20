"""Offline checks for target restrictions, rollback, and private diagnostics."""

import io
import os
import unittest
from contextlib import redirect_stdout
from types import SimpleNamespace
from unittest.mock import Mock, patch

from sqlalchemy.engine import make_url
from sqlalchemy.exc import OperationalError

from app import db_session
from verify_trip_relationships import VerificationFailed, main, validate_target

DEV_URL = (
    "postgresql+psycopg://postgres.vnpkyvtbupnquvirzlzp:dummy"
    "@aws-0-test.pooler.supabase.com:5432/postgres"
)
PROD_URL = (
    "postgresql+psycopg://postgres.zjnuqqtbapbpudsjbpif:dummy"
    "@aws-0-test.pooler.supabase.com:5432/postgres"
)
CI_URL = "postgresql+psycopg://postgres:dummy@localhost:5432/lagaw_test?sslmode=disable"


class TargetTests(unittest.TestCase):
    def test_development_target_is_allowed(self):
        validate_target(SimpleNamespace(url=make_url(DEV_URL)))

    def test_hosted_production_is_rejected_in_both_modes(self):
        for ci in (False, True):
            with self.subTest(ci=ci), self.assertRaises(VerificationFailed):
                validate_target(SimpleNamespace(url=make_url(PROD_URL)), ci=ci)

    def test_ci_requires_loopback_and_the_disposable_database(self):
        validate_target(SimpleNamespace(url=make_url(CI_URL)), ci=True)
        for url in (
            DEV_URL,
            "postgresql+psycopg://postgres:dummy@localhost:5432/postgres",
            "postgresql+psycopg://postgres:dummy@remote.invalid:5432/lagaw_test",
        ):
            with self.subTest(url=url), self.assertRaises(VerificationFailed):
                validate_target(SimpleNamespace(url=make_url(url)), ci=True)

    def test_ci_target_needs_explicit_ci_mode(self):
        with self.assertRaises(VerificationFailed):
            validate_target(SimpleNamespace(url=make_url(CI_URL)))

    def test_rejected_target_never_opens_a_session(self):
        engine = Mock(url=make_url(PROD_URL))
        with (
            patch("verify_trip_relationships.get_engine", return_value=engine),
            patch("verify_trip_relationships.Session") as session_factory,
            redirect_stdout(io.StringIO()),
        ):
            result = main([])
        self.assertEqual(result, 1)
        session_factory.assert_not_called()
        engine.dispose.assert_called_once()


class CleanupTests(unittest.TestCase):
    def test_driver_failure_rolls_back_and_hides_private_error_details(self):
        engine = Mock(url=make_url(DEV_URL))
        output = io.StringIO()
        failure = OperationalError("statement", {}, Exception("private-driver-details"))
        with (
            patch("verify_trip_relationships.get_engine", return_value=engine),
            patch("verify_trip_relationships.Session") as session_factory,
            patch("verify_trip_relationships.verify", side_effect=failure),
            redirect_stdout(output),
        ):
            result = main([])
            session_factory.return_value.__enter__.return_value.rollback.assert_called_once()
        self.assertEqual(result, 1)
        self.assertIn("OperationalError", output.getvalue())
        self.assertNotIn("private-driver-details", output.getvalue())
        engine.dispose.assert_called_once()


class EngineTests(unittest.TestCase):
    def setUp(self):
        db_session.get_engine.cache_clear()
        self.addCleanup(db_session.get_engine.cache_clear)

    def test_hosted_database_defaults_to_ssl(self):
        with (
            patch.dict(os.environ, {"DATABASE_URL": DEV_URL}, clear=True),
            patch("app.db_session.load_dotenv"),
            patch("app.db_session.create_engine") as factory,
        ):
            db_session.get_engine()
        self.assertEqual(factory.call_args.kwargs["connect_args"]["sslmode"], "require")

    def test_local_ci_database_can_explicitly_disable_ssl(self):
        with (
            patch.dict(os.environ, {"DATABASE_URL": CI_URL}, clear=True),
            patch("app.db_session.load_dotenv"),
            patch("app.db_session.create_engine") as factory,
        ):
            db_session.get_engine()
        self.assertEqual(factory.call_args.kwargs["connect_args"]["sslmode"], "disable")

    def test_hosted_database_cannot_disable_ssl(self):
        with (
            patch.dict(os.environ, {"DATABASE_URL": DEV_URL + "?sslmode=disable"}, clear=True),
            patch("app.db_session.load_dotenv"),
            patch("app.db_session.create_engine") as factory,
            self.assertRaises(RuntimeError),
        ):
            db_session.get_engine()
        factory.assert_not_called()


if __name__ == "__main__":
    unittest.main()
