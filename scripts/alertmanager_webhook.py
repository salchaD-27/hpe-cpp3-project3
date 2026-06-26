#!/usr/bin/env python3
"""Minimal Alertmanager webhook bridge for heartbeat recovery alerts."""

from __future__ import annotations

import json
import os
import logging
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import Request, urlopen

ALERTMANAGER_URL = os.environ.get(
    "ALERTMANAGER_URL", "http://alertmanager:9093/api/v2/alerts"
)
LISTEN_ADDR = os.environ.get("LISTEN_ADDR", ":8085")
RECOVERY_ALERTNAME = os.environ.get("RECOVERY_ALERTNAME", "NodeHeartbeatDetected")
TARGET_ALERTNAME = os.environ.get("TARGET_ALERTNAME", "NodeHeartbeatMissing")

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO").upper(),
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("alert-resolve-webhook")


def parse_listen_addr(value: str) -> tuple[str, int]:
    host, port_text = value.rsplit(":", 1)
    host = "0.0.0.0" if host in {"", ":"} else host
    return host, int(port_text)


def build_resolve_payload(alert) -> list[dict]:
    labels = dict(alert["labels"])
    labels["alertname"] = TARGET_ALERTNAME

    return [{
        "labels": labels,
        "endsAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    }]


def post_resolve(payload: list[dict]) -> None:
    body = json.dumps(payload, indent=2)
    print(body, flush=True)

    logger.info("Posting resolve payload to Alertmanager at %s", ALERTMANAGER_URL)
    request = Request(
        ALERTMANAGER_URL,
        data=body.encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=10) as response:
        logger.info("Alertmanager response status=%s", getattr(response, "status", "<unknown>"))
        response.read()


class Handler(BaseHTTPRequestHandler):
    def do_POST(self) -> None:
        logger.info("Incoming webhook request path=%s from=%s", self.path, self.client_address[0])
        if self.path not in {"/", "/webhook"}:
            logger.warning("Rejected request with unsupported path=%s", self.path)
            self.send_error(404)
            return

        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        logger.info("Webhook payload bytes=%d", len(raw_body))

        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except json.JSONDecodeError:
            logger.exception("Failed to decode webhook payload as JSON")
            self.send_error(400, "invalid JSON")
            return

        print(json.dumps(payload, indent=2), flush=True)

        alerts = payload.get("alerts") or []
        logger.info("Webhook contained %d alert(s)", len(alerts))
        matched = [
            alert
            for alert in alerts
            if alert.get("labels", {}).get("alertname") == RECOVERY_ALERTNAME
            and alert.get("status") == "firing"
        ]

        logger.info(
            "Matched %d recovery alert(s) for alertname=%s",
            len(matched),
            RECOVERY_ALERTNAME,
        )

        if not matched:
            logger.info("No matching recovery alert found; ignoring webhook")
            self.send_response(202)
            self.end_headers()
            self.wfile.write(b"ignored")
            return

        try:
            resolve = build_resolve_payload(matched[0])
            logger.info("Built fixed resolve payload labels=%s endsAt=%s", resolve[0].get("labels"), resolve[0].get("endsAt"))
            post_resolve(resolve)
        except Exception as exc:  # noqa: BLE001
            logger.exception("Failed while posting resolve payload: %s", exc)
            self.send_error(502, f"failed to resolve alert: {exc}")
            return

        logger.info("Resolve flow completed successfully")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"resolved")

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    host, port = parse_listen_addr(LISTEN_ADDR)
    logger.info(
        "Starting webhook bridge host=%s port=%s alertmanager_url=%s recovery_alertname=%s target_alertname=%s",
        host,
        port,
        ALERTMANAGER_URL,
        RECOVERY_ALERTNAME,
        TARGET_ALERTNAME,
    )
    server = ThreadingHTTPServer((host, port), Handler)
    logger.info("Listening on %s:%s", host, port)
    server.serve_forever()


if __name__ == "__main__":
    main()
