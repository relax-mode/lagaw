"""Reject oversized request bodies before FastAPI parses them.

The largest legitimate body (a 2,000-character extraction prompt, or 100
excluded location IDs) is a few kilobytes. Without a cap, multi-megabyte JSON
is read and validated in full before the route rejects it.
"""

import json

MAX_BODY_BYTES = 64 * 1024
_TOO_LARGE = json.dumps({"detail": "Request body is too large."}).encode()


class BodySizeLimit:
    """Pure ASGI middleware: checks Content-Length, then counts streamed bytes."""

    def __init__(self, app, max_bytes: int = MAX_BODY_BYTES):
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] in ("GET", "HEAD", "OPTIONS"):
            await self.app(scope, receive, send)
            return
        declared = dict(scope["headers"]).get(b"content-length")
        if declared is not None:
            try:
                too_large = int(declared) > self.max_bytes
            except ValueError:
                too_large = True
            if too_large:
                await self._reject(send)
                return

        # Buffer the (small) body so a chunked upload cannot exceed the cap.
        chunks, size = [], 0
        while True:
            message = await receive()
            if message["type"] != "http.request":
                # Client disconnected; let the app observe it normally.
                pending = [message]
                break
            chunk = message.get("body", b"")
            size += len(chunk)
            if size > self.max_bytes:
                await self._reject(send)
                return
            chunks.append(chunk)
            if not message.get("more_body", False):
                pending = [{"type": "http.request", "body": b"".join(chunks),
                            "more_body": False}]
                break

        async def replay():
            if pending:
                return pending.pop(0)
            return await receive()

        await self.app(scope, replay, send)

    @staticmethod
    async def _reject(send):
        await send({
            "type": "http.response.start", "status": 413,
            "headers": [(b"content-type", b"application/json"),
                        (b"content-length", str(len(_TOO_LARGE)).encode())],
        })
        await send({"type": "http.response.body", "body": _TOO_LARGE})
