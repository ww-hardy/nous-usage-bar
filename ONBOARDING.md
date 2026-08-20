# Onboarding — connecting your own Nous credentials

The widget **never touches your credentials**. It doesn't store a token, ask
for a password, or need an API key. Instead it delegates to **Hermes Agent**,
the open-source tool from Nous Research that already manages your Nous Portal
login (OAuth tokens live in `~/.hermes/auth.json`, refreshed automatically).

So "adding your credentials" really means: **log Hermes into Nous Portal once**.
Everything else follows.

---

## Prerequisites

- **macOS 12+** (Apple Silicon or Intel)
- **Hermes Agent** installed (see Step 1)
- A **Nous Portal account** with credits or a subscription (free tier works too)

---

## Step 1 — Install Hermes Agent

Open **Terminal** and run:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

This installs Hermes into `~/.hermes/hermes-agent/` and puts the `hermes`
command on your PATH. (The widget needs this — it uses Hermes' own account
fetch, which lives in this install.)

> No Python, Swift, Xcode or package manager setup needed. The widget ships
> the fetch script bundled inside the app; it just needs Hermes' Python on disk.

## Step 2 — Log into Nous Portal

```bash
hermes portal
```

Follow the one-shot onboarding: pick your model, choose **Nous** as the
provider, and complete the browser login. This creates your OAuth session.

Verify it worked:

```bash
hermes portal info
```

You should see `Auth: ✓ logged in` and `Model: ✓ using Nous as inference provider`.

## Step 3 — Launch the widget

Double-click `NousUsageBar.app` (or drag it to your Applications folder first).

Within a few seconds the menu bar should show a colored dot with your balance:

```
● $128.67        ← green: more than $30 usable
● $28.50         ← orange: between $10 and $30
● $7.10          ← red: less than $10
```

Click it to see the full breakdown: plan, subscription credits, top-up
credits, monthly credits, and renewal date.

## Step 4 — (Optional) Auto-start at login

Add the app under **System Settings → General → Login Items → +**, or install
the bundled LaunchAgent:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.gieldanowski.noususagebar.plist
```

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| Red `● N/A` | Not logged into Nous Portal. Run `hermes portal` (or `hermes model`), then **Refresh now** (⌘R). |
| `hermes import failed` | Hermes isn't on PATH or isn't installed. Re-run the install script, then reopen the widget. |
| Gatekeeper "unidentified developer" | The app is adhoc-signed. Right-click the app → **Open** → **Open**, once. |
| Balance looks stale | Click **Refresh now** (⌘R), or just reopen the menu — it refreshes on open too. |
| Multiple Hermes profiles | The widget uses whichever Hermes is active on PATH (`which hermes`). If you use profiles, make sure the right one is active. |

---

## How the credentials flow works (the short version)

```
Vous            Hermes (~/.hermes/auth.json)        NousUsageBar.app
────            ────────────────────────────        ──────────────
login once  ──▶  stores OAuth tokens        ──▶  shells out to Hermes' python
                       ▲                          running fetch_nous_usage.py
                       └──── refreshes tokens as needed ────┘
```

- Your OAuth token stays in Hermes' auth store, **never** in the widget, its
  logs, or the menu bar.
- The widget only ever runs a local Python script that calls Hermes' own
  account API. No network calls are made by the app itself.
- Deleting the widget changes nothing about your Nous account.

If you ever want to remove access entirely, revoke it in
**portal.nousresearch.com → Account** — that kills the token Hermes uses,
independent of this widget.
