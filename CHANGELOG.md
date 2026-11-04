# Changelog

## 1.10.1 — 2026-11-04

- **Swift 6.0 build compatibility:** use `@preconcurrency` protocol conformances supported by the
  macOS 15 GitHub runner, while preserving main-actor safety on newer Swift toolchains.

## 1.10.0 — 2026-11-04

- **Save backups and restore:** create timestamped snapshots for one title or every save, choose an
  external backup folder, and safely restore the latest snapshot. The current save is backed up
  before replacement, and untrusted title metadata cannot escape the backup folder.
- **Multiple languages:** core navigation and save-management flows now follow macOS in English,
  Brazilian Portuguese or Spanish, with English fallback.
- **Switch-style software controls:** a running title exposes a prominent **Close Software** action
  with confirmation and an unsaved-progress warning.
- **Playable README demo:** a compact preview plays directly on GitHub while the full 720p demo is
  delivered as a release asset instead of inflating the current source tree.
- **Swift 6 and CI:** migrated the package to Swift 6 language mode, resolved strict-concurrency
  issues, and pinned current Node 24-compatible GitHub Actions to immutable commits.

## 1.9.0 — 2026-11-04

- **Product demo:** added a Git-friendly, two-minute 720p H.264 demo with a clickable preview in
  the README.
- **Reliable local data:** settings and play history are written atomically with private file
  permissions. Damaged JSON is preserved for diagnosis, the launcher falls back safely, and read
  or write failures are recorded in unified logging.
- **Safer downloads:** failed file positioning no longer allows a store response to continue into
  a potentially invalid partial download.
- **Production builds:** removed current Swift concurrency warnings; release builds now validate
  semantic versions, release tags, Info.plist, signatures and ZIP integrity.
- **Safer CI releases:** signing credentials are only exposed to tagged GitHub builds, while release
  publishing runs separately with narrowly scoped write permission.

## 1.8.0 — 2026-11-04

- **Controller scrolling & margins:** Fixed issues where rapid stick/d-pad navigation caused tiles
  or settings sections to stop partially off-screen. Replaced overlapping scroll animations with an
  adaptive scroll follower that keeps clean edge margins on both the HOME row and System Settings tabs/lists.
- **Controller HOME / Xbox button return:** Returning to the launcher while playing a game now hides
  the game process so macOS reliably brings the launcher forward even from full-screen. Resuming a
  running game from the HOME menu correctly restores and focuses the game window.

## 1.7.0 — 2026-11-04

- **Faster with a controller.** System Settings built every page's rows on each press, reading
  user accounts, every game's drive and free space (about 350 ms per press); now it builds only the
  page on screen and keeps those answers briefly (under 60 ms). The selection's pulsing glow ran as a
  SwiftUI animation that used about a third of a CPU core even while idle; it's now a Core
  Animation layer that costs the launcher nothing.
- **Controller fixes:** when the launcher isn't the active app, it asks macOS to bring it forward
  once instead of on every press, and the HOME row no longer jumps when that happens.
- **Settings scroll:** the sidebar follows the selection, and lists keep the next row in view
  instead of stopping under the bottom bar.
- **Power button:** the Sleep Mode shortcut is now Power: Lock Mac, Sleep or Close App. The
  launcher's Sleep Mode screen stays in System Settings › Sleep Mode and Auto-Sleep.
- **Guide:** [docs/GUIDE.md](docs/GUIDE.md) explains how the launcher works and how to set up a NAS
  (Docker) as your own Game Store.
- `-benchmarkTo <file>` times menu pages and button presses; `-backgroundInput NO` keeps a copy
  opened in the background from reacting to a controller.

## 1.6.0 — 2026-11-04

- **Game Store downloads continue where they stopped.** A dropped connection or an error from the
  store (such as the 503 a tunnel returns near the end of a big download) no longer fails the
  download: it shows "Reconnecting…" and carries on from the last byte, retrying for up to 10
  minutes without progress. Quitting the launcher or a failed download keeps what was downloaded,
  and starting it again continues from there.
- Store server: the Cloudflare tunnel connectors stay off k8s-worker3, whose network adapter resets.

## 1.5.0 — 2026-10-29

- **Switch 2 look**: the HOME Menu shortcuts sit together on one rounded bar.
- **System Settings** follows the Switch 2's list: Airplane Mode, Screen Brightness, Bluetooth,
  Internet, Parental Controls, Accessibility, Data Management, Users, Controllers and Accessories,
  Audio, Display, Themes, Notifications, Sleep Mode and System.
  - Mac controls work in place: brightness and volume sliders, mute, Wi-Fi and Bluetooth switches,
    paired devices, Airplane Mode (Wi-Fi and Bluetooth off, restored after), connection test.
  - Data Management shows a usage bar for the Mac's disk (system memory) and each external drive,
    and moves software between drives (+ on a title, or Move Software in its options): copied,
    checked byte for byte, then removed from the old drive.
  - Users lists the Mac's accounts and the signed-in person's save data.
  - Parental Controls: a 4-digit PIN and an optional daily play time limit. Past the limit, starting
    software takes the PIN; deleting software or save data always does.
  - Accessibility: Reduce Motion. Notifications: choose which messages appear. Sleep Mode:
    Auto-Sleep on the HOME Menu, turn off the display, put the Mac to sleep.
  - Game Store server settings moved to Internet, library folders to Data Management.
- **Groups** tab in All Software (L/R): create groups, pick their software, rename or delete them.
- **Virtual Game Cards**: + opens a card's software options.
- **User Settings** on My Page, with the profile icon and the Mac account.
- The controller's HOME (Guide/Xbox) button comes back to the launcher during play instead of
  opening macOS's Games app; the running software is selected and marked Playing.

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
