# Changelog

## 1.4.0 — 2026-10-29

- **Software Update** in System Settings › System: checks GitHub for a newer release at startup and
  every 6 hours (Check for Updates Automatically turns it off), says so once with a message, and
  offers to open the new version's download or its release notes.
- Software sizes are saved between launches (`app-sizes.json`), so Data Management shows them right
  away. An app is measured again only when it's moved, updated or replaced; save data is refreshed
  in the background.

## 1.3.0 — 2026-10-29

- **Save Data** in System Settings: every title's save data on this Mac, installed or not, with its
  size. Deleting save data asks twice. Save data stays when software is deleted and is picked up
  again when the software is reinstalled, from the Game Store too; the store says so before the
  download and once it's installed.
- Software options link to Save Data instead of deleting it directly.

## 1.2.0 — 2026-10-29

- **Delete software**: software options › Data Management has Delete Software (moves the app and its
  `.app.key` to the Trash, keeps save data) and Delete Save Data. Apps added one by one get Remove
  from Library instead, which leaves the app where it is.
- **Storage**: software options show the app's size, its save data and free space on its disk.
  System Settings › Data Management shows free space on each disk that holds software, totals, and
  every title by size.
- **Add Software** tile at the end of All Software: adds game apps or folders that contain them.
- **Store server**: SeaweedFS is replaced by a Versity S3 Gateway that serves a TrueNAS folder
  read-only. Games no longer pass through the cluster's worker disks.
- `store-publish --to DIR`: publishes into a folder (such as the NAS share mounted over SMB) instead
  of uploading over S3. It writes each archive to a `.partial` file first, then moves it into place.

## 1.1.0 — 2026-10-28

- **Game Store** (the eShop button): lists games from your own S3-compatible bucket (SeaweedFS on the
  homelab), downloads with progress and resume, verifies SHA-256, installs with Apple Archive and
  adds them to the library. Tries the home-network address first, then a remote one (Cloudflare
  tunnel). Sign in with username and password; settings in System Settings › Store.
- `store-publish` command-line tool: streams apps as Apple Archives into multipart uploads (no local
  copy) and maintains `catalog.json` with icons, sizes and checksums.
- `deploy/setup-store.sh`: SeaweedFS (S3) on Kubernetes with TrueNAS NFS storage, a read-only launcher login
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
