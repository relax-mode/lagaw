"""Offline safety checks for the explicit association database verifier."""

import unittest
from unittest.mock import Mock, patch

from verify_trip_items import CI_URL, VerificationFailed, main, validate_target, verify


class TripItemTargetTests(unittest.TestCase):
    def test_exact_development_target_is_accepted(self):
        validate_target("https://vnpkyvtbupnquvirzlzp.supabase.co/rest/v1/")

    def test_production_and_other_targets_are_refused(self):
        for target in (
            "https://zjnuqqtbapbpudsjbpif.supabase.co/rest/v1/",
            "https://another.supabase.co/rest/v1/",
            "http://vnpkyvtbupnquvirzlzp.supabase.co/rest/v1/",
            "https://user:password@vnpkyvtbupnquvirzlzp.supabase.co/rest/v1/",
            "https://vnpkyvtbupnquvirzlzp.supabase.co:443/rest/v1/",
            "https://vnpkyvtbupnquvirzlzp.supabase.co/rest/v1/?other=1",
            "https://vnpkyvtbupnquvirzlzp.supabase.co/rest/v1/#fragment",
            CI_URL,
        ):
            with self.subTest(target=target), self.assertRaises(VerificationFailed):
                validate_target(target)

    def test_ci_accepts_only_exact_loopback_service(self):
        validate_target(CI_URL, ci=True)
        for target in (
            "https://vnpkyvtbupnquvirzlzp.supabase.co/rest/v1/",
            "https://zjnuqqtbapbpudsjbpif.supabase.co/rest/v1/",
            "http://127.0.0.1:8000/", "http://localhost:53000/",
        ):
            with self.subTest(target=target), self.assertRaises(VerificationFailed):
                validate_target(target, ci=True)

    def test_production_configuration_is_rejected_before_verification(self):
        client = Mock(base_url="https://zjnuqqtbapbpudsjbpif.supabase.co/rest/v1/")

        def configured():
            yield Mock(client=client)

        with patch("verify_trip_items.get_database", configured), \
                patch("verify_trip_items.verify") as run, patch("builtins.print"):
            self.assertEqual(main([]), 1)
        run.assert_not_called()
        client.get.assert_not_called()
        client.post.assert_not_called()
        client.delete.assert_not_called()

    def test_partial_setup_failure_cleans_all_registered_fixtures(self):
        with (
            patch("verify_trip_items.insert", side_effect=VerificationFailed("setup failed")),
            patch("verify_trip_items.delete_exact") as cleanup,
            patch("verify_trip_items.rows", return_value=[]),
            patch("builtins.print"),
            self.assertRaisesRegex(VerificationFailed, "setup failed"),
        ):
            verify(Mock())
        tables = [call.args[1] for call in cleanup.call_args_list]
        self.assertEqual(tables.count("itinerary_items"), 4)
        self.assertEqual(tables.count("trips"), 3)
        self.assertEqual(tables.count("users"), 2)
        self.assertEqual(tables.count("locations"), 3)
        for call in cleanup.call_args_list:
            self.assertNotEqual(str(call.args[2]), "")

    def test_cleanup_continues_after_an_individual_delete_failure(self):
        with patch("verify_trip_items.insert", side_effect=VerificationFailed("setup failed")), \
                patch("verify_trip_items.delete_exact") as cleanup, patch("builtins.print"):
            cleanup.side_effect = [RuntimeError("private details"), *([None] * 11)]
            with self.assertRaisesRegex(VerificationFailed, "Fixture cleanup failed"):
                verify(Mock())
        self.assertEqual(cleanup.call_count, 12)