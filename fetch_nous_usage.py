#!/usr/bin/env python3
"""
Nous Usage fetch — menu-bar widget backend.

Shells out to Hermes' own Nous Portal account machinery so OAuth refresh,
token storage, and entitlement parsing are handled by the exact code that
drives the CLI/desktop app. This script only prints JSON; it never touches
credentials itself.

Run with the Hermes venv python, e.g.:
    ~/.hermes/hermes-agent/venv/bin/python fetch_nous_usage.py

Output (stdout, stable schema):
    {"ok": true, "plan": "Super", "subscription_remaining": 76.2, ...}
    {"ok": false, "error": "..."}
"""

from __future__ import annotations

import json
import sys


def main() -> None:
    try:
        from hermes_cli.nous_account import get_nous_portal_account_info
    except Exception as exc:  # noqa: BLE001 - report anything, fail-open
        _emit_error(f"hermes import failed: {exc}")
        return

    try:
        info = get_nous_portal_account_info(force_fresh=True)
    except Exception as exc:  # noqa: BLE001
        _emit_error(f"account fetch failed: {exc}")
        return

    if not getattr(info, "logged_in", False):
        _emit_error("not logged in to Nous Portal (run `hermes portal`)")
        return

    out: dict = {"ok": True, "source": getattr(info, "source", None)}

    sub = getattr(info, "subscription", None)
    if sub is not None:
        out["plan"] = getattr(sub, "plan", None)
        out["monthly_credits"] = getattr(sub, "monthly_credits", None)
        out["subscription_remaining"] = getattr(sub, "credits_remaining", None)
        out["period_end"] = getattr(sub, "current_period_end", None)

    acc = getattr(info, "paid_service_access_info", None)
    if acc is not None:
        out["purchased_remaining"] = getattr(acc, "purchased_credits_remaining", None)
        out["total_usable"] = getattr(acc, "total_usable_credits", None)

    # Best-effort org identity (no secrets - names/slugs only).
    for key in ("org_name", "org_slug", "email"):
        val = getattr(info, key, None)
        if val:
            out[key] = val

    print(json.dumps(out, allow_nan=False))
    sys.exit(0)


def _emit_error(message: str) -> None:
    print(json.dumps({"ok": False, "error": message}))
    sys.exit(0)


if __name__ == "__main__":
    main()
