# Antigravity Quota Menu Bar App

A native macOS menu bar accessory app written in Swift & SwiftUI that tracks Google Antigravity quota and rate limits in real time.

## Features

- **Menu Bar Status:** Displays a live gauge icon and remaining percentage directly in the macOS menu bar.
- **Rich Popover:** Clicking reveals a card with breakdown across:
  - **Google Gemini:** 5-hour rolling window & weekly limit with progress bars and reset countdowns.
  - **Claude / GPT (3P):** 5-hour rolling window & weekly limit.
- **Zero Config:** Automatically reads tokens from macOS Keychain (`service: gemini`, `account: antigravity`) or fallback CLI token file (`~/.gemini/antigravity-cli/antigravity-oauth-token`).
- **Token Auto-Refresh:** Transparently refreshes expired OAuth access tokens with Google's endpoint.
- **Background Accessory:** Configured as `LSUIElement` so it never clutters your Dock.

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

You can also drag `AntigravityQuota.app` into `/Applications` or add it to **System Settings > General > Login Items** to have it start at login.
