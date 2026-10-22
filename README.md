# Antigravity Quota Menu Bar App

A native macOS menu bar accessory app written in Swift & SwiftUI that tracks Google Antigravity quota and rate limits across primary and secondary accounts in real time.

## Features

- **Multi-Account Support:** Seamlessly monitors both **Account 1** and **Account 2** side-by-side.
- **Menu Bar Status:** Displays a live gauge icon and remaining percentages directly in the macOS menu bar (e.g. `A1: 85% · A2: 100%`).
- **Rich Popover & Tab Filtering:** Clicking reveals cards with breakdowns across:
  - **Google Gemini:** 5-hour rolling window & weekly limit with progress bars and reset countdowns.
  - **Claude / GPT (3P):** 5-hour rolling window & weekly limit.
  - Segmented control to toggle between "All Accounts" or single-account inspection.
- **Zero Config Auto-Discovery:** Automatically reads credentials from macOS Keychain or fallback CLI token files:
  - **Account 1 (Primary):**
    - Files: `~/.antigravity-accounts/account-1/antigravity-oauth-token`, `~/.gemini/antigravity-cli/antigravity-oauth-token`, `~/.gemini/oauth_creds.json`
    - Keychain: `service: gemini`, `account: antigravity` (or `antigravity-1`, `antigravity-primary`)
  - **Account 2:**
    - Files: `~/.antigravity-accounts/account-2/antigravity-oauth-token`, `~/.antigravity-accounts/account-2/.gemini/...`, `~/.gemini/antigravity-cli-acct2/...`
    - Keychain: `service: gemini`, `account: antigravity-2` (or `antigravity-account-2`, `service: gemini-2`)
- **Auto User Email Identification:** Automatically extracts the user's Google email from the OAuth `id_token` JWT payload and displays it alongside plan tiers.
- **Token Auto-Refresh:** Transparently refreshes expired OAuth access tokens with Google's OAuth endpoint.
- **Background Accessory:** Configured as `LSUIElement` so it never clutters your Dock.

## Setting Up Account 2 in Keychain (Optional)

If you store credentials in macOS Keychain rather than CLI token files:

```bash
# Store Account 2 refresh token in Keychain
security add-generic-password -U -s "gemini" -a "antigravity-2" -w '{"refresh_token": "YOUR_REFRESH_TOKEN"}'
```

## Quick Start on macOS

### Option A: Run directly from terminal

```bash
cd antigravity-menubar
swift run
```

### Option B: Build standalone `.app` bundle

```bash
cd antigravity-menubar
./build.sh
open AntigravityQuota.app
```

You can also drag `AntigravityQuota.app` into `/Applications` or add it to **System Settings > General > Login Items** to have it start automatically at login.