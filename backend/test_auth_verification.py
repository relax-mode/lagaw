"""Hosted acceptance must refuse production before asking for account credentials."""

from unittest.mock import patch

import pytest

from app.auth import DEVELOPMENT_URL
from verify_auth import validate_target, verify


@pytest.mark.parametrize("api,url", [
    ("https://lagaw-api-i5kvldluga-as.a.run.app", DEVELOPMENT_URL),
    ("http://127.0.0.1:8000", "https://zjnuqqtbapbpudsjbpif.supabase.co"),
    ("https://another-api.invalid", DEVELOPMENT_URL),
    ("http://127.0.0.1:8000/", DEVELOPMENT_URL),
])
def test_unsafe_targets_are_refused_before_credentials_or_network(api, url):
    with patch("getpass.getpass") as prompt, patch("httpx.Client") as client, pytest.raises(ValueError):
        verify(api, url, "synthetic-only")
    prompt.assert_not_called()
    client.assert_not_called()


def test_development_local_and_staging_targets_are_accepted():
    validate_target("http://127.0.0.1:8000", DEVELOPMENT_URL)
    validate_target("https://lagaw-api-staging-i5kvldluga-as.a.run.app", DEVELOPMENT_URL)
