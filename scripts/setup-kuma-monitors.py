#!/usr/bin/env python3
"""Bulk-create Uptime Kuma monitors for space-server public subdomains.

Idempotent: skips monitors whose name already exists. Re-run after adding
new services to register them.

Usage:
    pip install --user uptime-kuma-api
    KUMA_USERNAME=admin KUMA_PASSWORD=... python3 scripts/setup-kuma-monitors.py

Env vars:
    KUMA_URL       (default: https://uptime.cativo.dev)
    KUMA_USERNAME  (required)
    KUMA_PASSWORD  (required)

Tracked as F22 in IMPROVEMENT-PLAN.md.
"""
from __future__ import annotations

import os
import sys

try:
    from uptime_kuma_api import MonitorType, UptimeKumaApi
except ImportError:
    sys.exit("install first: pip install --user uptime-kuma-api")


KUMA_URL = os.environ.get("KUMA_URL", "https://uptime.cativo.dev")

# (name, url, accepted_statuscodes)
# Services behind Traefik basic auth accept 401 — a 401 means the service
# IS up, just credential-gated; that's the signal we want.
MONITORS: list[tuple[str, str, list[str]]] = [
    ("cativo.dev",             "https://cativo.dev",             ["200-299", "301", "302"]),
    ("blog.cativo.dev",        "https://blog.cativo.dev",        ["200-299", "301", "302"]),
    ("api.cativo.dev",         "https://api.cativo.dev",         ["200-299", "301", "302", "404"]),
    ("mail.cativo.dev",        "https://mail.cativo.dev",        ["200-299", "301", "302"]),
    ("devi.cativo.dev",        "https://devi.cativo.dev",        ["200-299", "301", "302"]),
    ("grafana.cativo.dev",     "https://grafana.cativo.dev",     ["200-299", "301", "302"]),
    ("prometheus.cativo.dev",  "https://prometheus.cativo.dev",  ["200-299", "301", "302", "401"]),
    ("alertmanager.cativo.dev","https://alertmanager.cativo.dev",["200-299", "301", "302", "401"]),
    ("dozzle.cativo.dev",      "https://dozzle.cativo.dev",      ["200-299", "301", "302", "401"]),
    ("uptime.cativo.dev",      "https://uptime.cativo.dev",      ["200-299", "301", "302"]),
    ("traefik.cativo.dev",     "https://traefik.cativo.dev",     ["200-299", "301", "302", "401"]),
]


def main() -> int:
    username = os.environ.get("KUMA_USERNAME")
    password = os.environ.get("KUMA_PASSWORD")
    if not username or not password:
        sys.exit("KUMA_USERNAME and KUMA_PASSWORD must be set in env")

    with UptimeKumaApi(KUMA_URL) as api:
        api.login(username, password)

        # Kuma 2.2+ added a NOT NULL `conditions` column, but uptime-kuma-api
        # 1.x doesn't know about it. Patch the dict-building hook to inject
        # an empty list so the INSERT satisfies the constraint.
        _build = api._build_monitor_data
        def _build_with_conditions(**kwargs):
            data = _build(**kwargs)
            data.setdefault("conditions", [])
            return data
        api._build_monitor_data = _build_with_conditions

        existing = {m["name"] for m in api.get_monitors()}
        print(f"connected to {KUMA_URL} — {len(existing)} existing monitors")

        added = skipped = 0
        for name, url, statuses in MONITORS:
            if name in existing:
                print(f"  [skip] {name}")
                skipped += 1
                continue
            api.add_monitor(
                type=MonitorType.HTTP,
                name=name,
                url=url,
                interval=60,
                retryInterval=20,
                maxretries=2,
                accepted_statuscodes=statuses,
            )
            print(f"  [add]  {name} -> {url} (accept {statuses})")
            added += 1

        print(f"\ndone: added {added}, skipped {skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
