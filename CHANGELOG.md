# Changelog

## 1.1.0 — 2026-10-28

- **Game Store** (the eShop button): lists games from your own S3-compatible bucket (MinIO on the
  homelab), downloads with progress and resume, verifies SHA-256, installs with Apple Archive and
  adds them to the library. Tries the home-network address first, then a remote one (Cloudflare
  tunnel). Sign in with username and password; settings in System Settings › Store.
- `store-publish` command-line tool: streams apps as Apple Archives into multipart uploads (no local
  copy) and maintains `catalog.json` with icons, sizes and checksums.
- `deploy/setup-store.sh`: MinIO on Kubernetes with TrueNAS NFS storage, a read-only launcher login
  and a dedicated Cloudflare tunnel.
- The settings file is now readable by your user only.

## 1.0.0 — 2026-10-28

First release.

- HOME Menu modelled on the Nintendo Switch 2: software row (12 most recent + All Software), shortcut
  row, status bar with clock, network and battery, button guide, Basic White / Basic Black themes.
- Finds native Switch ports (nxnative / MacNativeGames bundles, `*.native` ids, bundles with port
  runtime files) in configurable folders; any other Mac app can be added by hand.
- Starts games full screen on top of the launcher, hands focus to the game window, keeps it there
  when background apps try to take it, and comes back on HOME or when the game quits.
- All Software grid with four sort orders, per-title options, play activity and Virtual Game Cards.
- Controllers page: player slots, Change Grip/Order (L + R), Find Controllers (vibration),
  Test Input Devices (live buttons, sticks with trails, analog triggers), pairing.
- Quick Settings (hold HOME), Capture to Album, Sleep Mode, in-app pages for Nintendo Switch Online,
  News and Nintendo eShop.
- Keyboard and game controller input with Nintendo/positional face-button layouts.
- Synthesized interface sounds, launch animation, boot animation.
