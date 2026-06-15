from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import StreamingResponse

from .core import verify_signature
from .store import SQLiteStore


def create_app() -> FastAPI:
    app = FastAPI(title="CI Scope GitHub App Backend")
    db_path = os.environ.get("CI_SCOPE_BACKEND_DB", "./ci-scope-backend.sqlite3")
    webhook_secret = os.environ.get("CI_SCOPE_WEBHOOK_SECRET", "")
    client_token = os.environ.get("CI_SCOPE_CLIENT_TOKEN", "")
    store = SQLiteStore(Path(db_path))

    def require_client(authorization: str | None) -> None:
        if not client_token:
            return
        expected = f"Bearer {client_token}"
        if authorization != expected:
            raise HTTPException(status_code=401, detail="Invalid client token.")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/github/webhook")
    async def github_webhook(
        request: Request,
        x_github_event: str = Header(default=""),
        x_github_delivery: str = Header(default=""),
        x_hub_signature_256: str = Header(default=""),
    ) -> dict[str, object]:
        body = await request.body()
        if not verify_signature(body, x_hub_signature_256, webhook_secret):
            raise HTTPException(status_code=401, detail="Invalid webhook signature.")
        if not x_github_event or not x_github_delivery:
            raise HTTPException(status_code=400, detail="Missing GitHub webhook headers.")
        try:
            payload = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError as exc:
            raise HTTPException(status_code=400, detail="Invalid JSON payload.") from exc
        result = store.record_webhook(x_github_event, x_github_delivery, payload)
        return {"ok": True, "duplicate": result["duplicate"], "eventId": result["eventId"]}

    @app.get("/v1/snapshot")
    def snapshot(authorization: str | None = Header(default=None)) -> dict[str, object]:
        require_client(authorization)
        return store.snapshot()

    @app.get("/v1/events/stream")
    async def events_stream(
        last_event_id: int = 0,
        authorization: str | None = Header(default=None),
        last_event_id_header: str | None = Header(default=None, alias="Last-Event-ID"),
    ) -> StreamingResponse:
        require_client(authorization)
        try:
            cursor = int(last_event_id_header or last_event_id or 0)
        except ValueError:
            cursor = 0

        async def stream():
            nonlocal cursor
            heartbeat = 0
            while True:
                events = store.events_after(cursor, limit=100)
                if events:
                    for item in events:
                        cursor = item["id"]
                        yield sse(item["id"], item["event"], item["payload"])
                    heartbeat = 0
                else:
                    heartbeat += 1
                    if heartbeat >= 15:
                        yield ": heartbeat\n\n"
                        heartbeat = 0
                    await asyncio.sleep(1)

        return StreamingResponse(stream(), media_type="text/event-stream")

    return app


def sse(event_id: int, event: str, payload: dict[str, object]) -> str:
    data = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    return f"id: {event_id}\nevent: {event}\ndata: {data}\n\n"


app = create_app()

