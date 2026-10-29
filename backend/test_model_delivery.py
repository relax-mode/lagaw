"""The deploy wiring is all-or-nothing, version-pinned and fully removable."""

import importlib.util
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("resolve_model_delivery", ROOT / "scripts" / "resolve_model_delivery.py")
delivery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(delivery)

DIGEST = "ab" * 32


def test_enabled_delivery_mounts_a_pinned_version_read_only_outside_the_app():
    result = delivery.resolve("STAGING_MODEL_ARTIFACT:3", DIGEST.upper())
    assert result == {
        "enabled": "true", "secret_line": "/secrets/model/artifact.json=STAGING_MODEL_ARTIFACT:3",
        "path_line": "MODEL_FILE_PATH=/secrets/model/artifact.json",
        "sha_line": f"MODEL_FILE_SHA256={DIGEST}", "flags": "",
    }
    assert not delivery.MOUNT_PATH.startswith("/app")


@pytest.mark.parametrize("secret, digest", [("", ""), ("  ", "\n")])
def test_unset_variables_remove_the_mount_and_variables(secret, digest):
    result = delivery.resolve(secret, digest)
    assert result["enabled"] == "false"
    assert result["secret_line"] == result["path_line"] == result["sha_line"] == ""
    assert result["flags"] == (
        "--remove-secrets=/secrets/model/artifact.json "
        "--remove-env-vars=MODEL_FILE_PATH,MODEL_FILE_SHA256"
    )


@pytest.mark.parametrize("secret, digest", [
    ("NAME:1", ""), ("", DIGEST), ("NAME:latest", DIGEST), ("NAME", DIGEST), ("NAME:0", DIGEST),
    ("NAME:1 --extra", DIGEST), ("1NAME:1", DIGEST), ("NAME:1", "abc"), ("NAME:1", "g" * 64),
    ("NAME:1\nMODEL_FILE_PATH=/etc/passwd", DIGEST),
])
def test_partial_or_unpinned_settings_fail_the_deploy(secret, digest):
    with pytest.raises(ValueError):
        delivery.resolve(secret, digest)


def test_both_deploy_jobs_use_the_resolver_and_never_mount_latest():
    workflow = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    assert workflow.count("python3 scripts/resolve_model_delivery.py") == 2
    for variable in ("secret_line", "path_line", "sha_line"):
        assert workflow.count(f"steps.model.outputs.{variable}") == 2
    assert workflow.count("steps.model.outputs.flags") == 2
    assert not re.search(r"/secrets/model.*:latest", workflow)
