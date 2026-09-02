#!/usr/bin/env python3
"""Reconcile Uptime Kuma monitors for the space-server stack.

This file is the source of truth for what Kuma probes. It creates monitors that
are missing and reports (or fixes, with --apply) any whose URL or accepted status
codes have drifted away from the table below.

Usage:
    pip install --user uptime-kuma-api
    KUMA_USERNAME=admin KUMA_PASSWORD=... python3 scripts/setup-kuma-monitors.py
    # ...add --apply to actually push edits for drifted monitors:
    KUMA_USERNAME=admin KUMA_PASSWORD=... python3 scripts/setup-kuma-monitors.py --apply

Missing monitors are always created. Drift is only *reported* unless --apply is
passed, so a bare run is safe to execute at any time.

Env vars:
    KUMA_URL       (default: https://uptime.cativo.dev)
    KUMA_USERNAME  (required)
    KUMA_PASSWORD  (required)

Tracked as F22 in IMPROVEMENT-PLAN.md. Probe-target policy: see ADR-0005.
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
#
# Two tiers, deliberately:
#
#   PUBLIC hostname  — for services users actually reach over the internet. The
#     probe traverses DNS + TLS + Traefik, so it catches an expired cert or a
#     broken router. Keep these on https://<host> even though they hairpin
#     through Docker NAT (F47, ADR-0005).
#
#   INTERNAL container URL — for the admin UIs that F47 moved behind the VPN.
#     Their public path is a deliberate 403, so a public probe would be
#     meaningless; we probe the container's own health endpoint instead.
#
# Probe targets must be endpoints that are NOT rate-limited. api.cativo.dev uses
# /health (exempt from portfolio-api's global ThrottlerGuard) rather than `/`,
# which is throttled and produced an 8-for-8 false-positive alert record before
# 2026-09-02. See ADR-0005.
MONITORS: list[tuple[str, str, list[str]]] = [
    # public surface — end-to-end through Traefik
    ("cativo.dev",             "https://cativo.dev",                   ["200-299", "301", "302"]),
    ("blog.cativo.dev",        "https://blog.cativo.dev",              ["200-299", "301", "302"]),
    ("api.cativo.dev",         "https://api.cativo.dev/health",        ["200-299"]),
    ("devi.cativo.dev",        "https://devi.cativo.dev",              ["200-299", "301", "302"]),
    # VPN-gated admin UIs — probed from inside the docker network (F47)
    ("mail.cativo.dev",        "http://webmail:80/",                   ["200-299", "301", "302"]),
    ("grafana.cativo.dev",     "http://grafana:3000/api/health",       ["200-299"]),
    ("prometheus.cativo.dev",  "http://prometheus:9090/-/healthy",     ["200-299"]),
    ("alertmanager.cativo.dev","http://alertmanager:9093/-/healthy",   ["200-299"]),
    ("dozzle.cativo.dev",      "http://dozzle:8080/",                  ["200-299"]),
    ("uptime.cativo.dev",      "http://uptime-kuma:3001/",             ["200-299", "302"]),
    ("traefik.cativo.dev",     "http://traefik:8081/ping",             ["200-299"]),
]


def main() -> int:
    apply_edits = "--apply" in sys.argv[1:]

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

        existing = {m["name"]: m for m in api.get_monitors()}
        print(f"connected to {KUMA_URL} — {len(existing)} existing monitors")

        added = ok = drifted = fixed = 0
        for name, url, statuses in MONITORS:
            current = existing.get(name)
            if current is None:
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
                continue

            # Compare against the table; order of status codes is not meaningful.
            deltas = []
            if current.get("url") != url:
                deltas.append(f"url: {current.get('url')} -> {url}")
            if sorted(current.get("accepted_statuscodes") or []) != sorted(statuses):
                deltas.append(
                    f"accepted: {current.get('accepted_statuscodes')} -> {statuses}"
                )

            if not deltas:
                print(f"  [ok]   {name}")
                ok += 1
                continue

            drifted += 1
            for d in deltas:
                print(f"  [drift]{name}: {d}")
            if apply_edits:
                api.edit_monitor(
                    current["id"], url=url, accepted_statuscodes=statuses
                )
                print(f"  [fix]  {name} reconciled")
                fixed += 1

        print(f"\ndone: added {added}, ok {ok}, drifted {drifted}, fixed {fixed}")
        if drifted and not apply_edits:
            print("re-run with --apply to reconcile the drifted monitors above")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
