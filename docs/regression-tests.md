# Regression tests

Run backend checks from `backend/` after installing `requirements-dev.txt` and Ruff:

```sh
python -m pytest -v
python -m ruff check .
```

The backend CI job runs these checks on pull requests, pushes to `main`, and
manual workflow runs. The tests use HTTPX mock transports or mocked clients and
dummy credentials, with local dotenv loading disabled. They cover locations,
Trip CRUD HTTP behavior, pagination, safe database failures, CORS, and validated DeepSeek extraction.
They never call the live database or paid AI provider. `smoke_test.py` remains
an explicit live connectivity check and is not part of regression discovery.

Run frontend checks from `frontend/`:

```sh
flutter pub get
flutter test
flutter analyze
```

Use a Flutter SDK with Dart compatible with the `^3.13.5` requirement in
`frontend/pubspec.yaml` (Flutter 3.47.7 includes Dart 3.13.5). CI installs Flutter
from the stable channel.

The Flutter CI job runs tests, analysis, and the web build on pull requests,
pushes to `main`, and manual workflow runs. Its HTTP tests use injected
`MockClient` responses, so they do not call the live backend, database, or LLM.
The CI job does not build an Android APK.

The current API service tests cover location parsing, pagination request
headers, successful empty pages, malformed or empty HTTP 200 bodies, server
errors, transport failures, and retrying a request. A failing regression command
fails its CI job; failed Flutter tests prevent the web build and its dependent
Cloudflare deployment job from running.

Trip HTTP CRUD tests are present and run in the backend job. They use mocked
Supabase responses, so they do not prove API persistence through PostgREST.
The database job separately checks migrations and SQLAlchemy relationships
against disposable PostgreSQL. Database-backed API fixtures and persistence
checks remain tracked in [#29](https://github.com/relax-mode/lagaw/issues/29).
Deployment gates, branch protection, and measured pipeline improvement are
tracked in [#31](https://github.com/relax-mode/lagaw/issues/31).
