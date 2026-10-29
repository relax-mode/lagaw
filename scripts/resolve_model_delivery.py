"""Turn two per-environment GitHub variables into Cloud Run deploy settings.

MODEL_ARTIFACT_SECRET (`SECRET_NAME:VERSION`, numeric version) and MODEL_FILE_SHA256
(64 hex characters) are set together to mount the trained collaborative artifact
read-only, or left unset to serve the content baseline. The deploy steps overwrite the
service's secrets (the mount, and its volume, disappear when the line does) but merge
environment variables, so disabled output explicitly removes the two model variables.
Prints `name=value` lines for $GITHUB_OUTPUT; never reads or prints a secret value.
"""

import os
import re
import sys

MOUNT_PATH = "/secrets/model/artifact.json"  # Dedicated directory; never under /app.
SECRET = re.compile(r"^([A-Za-z][A-Za-z0-9_-]{0,254}):([1-9][0-9]{0,8})$")
SHA256 = re.compile(r"^[a-f0-9]{64}$")


def resolve(secret: str, digest: str) -> dict[str, str]:
    secret, digest = secret.strip(), digest.strip().lower()
    if not secret and not digest:
        return {
            "enabled": "false", "secret_line": "", "path_line": "", "sha_line": "",
            "flags": "--remove-env-vars=MODEL_FILE_PATH,MODEL_FILE_SHA256",
        }
    if not secret or not digest:
        raise ValueError("Set MODEL_ARTIFACT_SECRET and MODEL_FILE_SHA256 together, or neither.")
    if not SECRET.fullmatch(secret):
        raise ValueError("MODEL_ARTIFACT_SECRET must be SECRET_NAME:VERSION with a numeric version, never latest.")
    if not SHA256.fullmatch(digest):
        raise ValueError("MODEL_FILE_SHA256 must be 64 lowercase hexadecimal characters.")
    return {
        "enabled": "true", "secret_line": f"{MOUNT_PATH}={secret}",
        "path_line": f"MODEL_FILE_PATH={MOUNT_PATH}", "sha_line": f"MODEL_FILE_SHA256={digest}",
        "flags": "",
    }


if __name__ == "__main__":
    try:
        settings = resolve(os.environ.get("MODEL_ARTIFACT_SECRET", ""), os.environ.get("MODEL_FILE_SHA256", ""))
    except ValueError as error:
        print(f"::error::{error}")
        sys.exit(1)
    for name, value in settings.items():
        print(f"{name}={value}")
