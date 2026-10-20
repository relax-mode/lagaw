"""Offline failure checks: no credentials or network required."""

import json
import os
import unittest
from unittest.mock import MagicMock, patch

import httpx

from app.deepseek import DeepSeekFailure, extract_preferences


class FailureTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-only-placeholder"}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.dotenv = patch("app.deepseek.load_dotenv")
        self.dotenv.start()
        self.addCleanup(self.dotenv.stop)

    def test_missing_key(self):
        os.environ.pop("DEEPSEEK_API_KEY")
        with patch("app.deepseek.httpx.Client") as client:
            with self.assertRaisesRegex(DeepSeekFailure, "^missing_api_key$"):
                extract_preferences("coffee")
            client.assert_not_called()

    def test_invalid_input(self):
        with self.assertRaisesRegex(DeepSeekFailure, "^invalid_request$"):
            extract_preferences("")

    def test_provider_failures_are_sanitized(self):
        status_codes = {
            400: "provider_rejected_request", 401: "authentication_failed",
            402: "insufficient_balance", 403: "access_denied", 404: "model_unavailable",
            429: "rate_limited", 500: "provider_unavailable",
        }
        cases = [
            (httpx.HTTPStatusError(
                "private provider detail",
                request=httpx.Request("POST", "https://api.deepseek.com/chat/completions"),
                response=httpx.Response(status),
            ), expected)
            for status, expected in status_codes.items()
        ]
        cases.extend([
            (httpx.ReadTimeout("private provider detail"), "provider_timeout"),
            (httpx.ConnectError("private provider detail"), "network_error"),
        ])
        for failure, expected in cases:
            with self.subTest(expected=expected), patch("app.deepseek.httpx.Client") as factory:
                client = factory.return_value.__enter__.return_value
                client.post.side_effect = failure
                with self.assertRaises(DeepSeekFailure) as caught:
                    extract_preferences("coffee")
                self.assertEqual(str(caught.exception), expected)

    def test_invalid_output(self):
        with patch("app.deepseek.httpx.Client") as factory:
            client = factory.return_value.__enter__.return_value
            client.post.return_value = MagicMock()
            client.post.return_value.json.return_value = {"choices": [{"finish_reason": "stop", "message": {"content": '{"tags":["unknown"]}'}}]}
            with self.assertRaisesRegex(DeepSeekFailure, "^invalid_provider_output$"):
                extract_preferences("coffee")

    def test_valid_output(self):
        expected = {
            "budget_level": "low", "tags": ["cafe", "photography", "relaxing"],
            "duration": "afternoon", "pace": "slow",
        }
        with patch("app.deepseek.httpx.Client") as factory:
            client = factory.return_value.__enter__.return_value
            client.post.return_value = httpx.Response(
                200, request=httpx.Request("POST", "https://api.deepseek.com/chat/completions"),
                json={"choices": [{"finish_reason": "stop", "message": {
                    "content": json.dumps(expected),
                }}]},
            )
            self.assertEqual(extract_preferences("cheap afternoon coffee").model_dump(), expected)
            call = client.post.call_args
            self.assertEqual(call.args[0], "https://api.deepseek.com/chat/completions")
            self.assertEqual(call.kwargs["json"]["response_format"], {"type": "json_object"})
            self.assertEqual(call.kwargs["headers"]["Authorization"], "Bearer test-only-placeholder")

    def test_malformed_envelopes(self):
        for payload in ({}, {"choices": []}, {"choices": [None]}):
            with self.subTest(payload=payload), patch("app.deepseek.httpx.Client") as factory:
                client = factory.return_value.__enter__.return_value
                client.post.return_value.json.return_value = payload
                with self.assertRaisesRegex(DeepSeekFailure, "^invalid_provider_output$"):
                    extract_preferences("coffee")

    def test_truncated_and_malformed_outputs_are_rejected(self):
        valid = {
            "budget_level": "low", "tags": ["cafe"],
            "duration": "afternoon", "pace": "slow",
        }
        valid_json = json.dumps(valid)
        choices = (
            {"finish_reason": "length", "message": {"content": valid_json}},
            {"finish_reason": "content_filter", "message": {"content": valid_json}},
            {"finish_reason": "stop", "message": {"content": "not-json"}},
            {"finish_reason": "stop", "message": {
                "content": json.dumps({**valid, "extra": True}),
            }},
        )
        for choice in choices:
            with self.subTest(choice=choice), patch("app.deepseek.httpx.Client") as factory:
                client = factory.return_value.__enter__.return_value
                client.post.return_value.json.return_value = {"choices": [choice]}
                with self.assertRaisesRegex(DeepSeekFailure, "^invalid_provider_output$"):
                    extract_preferences("coffee")

    def test_invalid_configuration(self):
        for timeout in ("abc", "999", "120001"):
            with self.subTest(timeout=timeout):
                os.environ["DEEPSEEK_TIMEOUT_MS"] = timeout
                with self.assertRaisesRegex(DeepSeekFailure, "^invalid_configuration$"):
                    extract_preferences("coffee")


if __name__ == "__main__":
    unittest.main()
