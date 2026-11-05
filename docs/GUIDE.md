# Switch Launcher guide

How the launcher works, and how to turn a NAS into your own Game Store.

- [How the launcher works](#how-the-launcher-works)
- [Setting up a NAS as your Game Store](#setting-up-a-nas-as-your-game-store)
- [Troubleshooting](#troubleshooting)

## How the launcher works

### Your library

Switch Launcher doesn't run games itself. It finds Mac apps built from your own game dumps by
[nxnative](https://github.com/seedds/nxnative) or MacNativeGames and starts them.

- **Where it looks:** `~/Documents/Switch/apps`, `/Applications` and `~/Applications` by default.
  Change the list in System Settings › Data Management › Library Folders, or press A on the
  **Add Software** tile at the end of All Software to add a game app or a folder of them.
- **What counts as a game:** an app whose `Info.plist` has a `DMTitleID`, whose bundle id starts
  with `org.nxnative.` or `org.macnativegames.`, or that carries a port's runtime
  (`Contents/MacOS/dmhost`, `Contents/Resources/romfs` or `Contents/Resources/game`).
- **Rescanning:** the library is read at startup and after anything is added, installed, moved or
  deleted. System Settings › Data Management › Rescan Library does it by hand.

### Playing

Pressing A on a game opens it full screen on top of the launcher and hands it keyboard and
controller focus. While it runs:

- **HOME on a controller** (the Guide/Xbox button) brings you back to the launcher. The game keeps
  running and shows **Playing** on the HOME Menu; press A on it to go back in.
- **Starting another game** asks to close the running one first.
- **X** on the running game closes it (unsaved progress is lost, as on the console).
- **Play time** is counted per game and per day (My Page › Play Activity, Parental Controls).

Each game keeps its own log at `~/Library/Logs/nxnative/<title ID>.log`.

### The HOME Menu

- **Top row:** your 12 most recently played games, then All Software.
- **All Software:** every game, with four sort orders (Y), and a **Groups** tab (R / L) for your own
  groups: create one, then tick the games in it.
- **Bottom bar:** News, Game Store, Album, Controllers, Virtual Game Cards (choose what shows on
  HOME; + opens a game's options), System Settings and **Power** (lock the Mac, put it to sleep or
  close the launcher).
- **+ on a game:** its options: information, play activity, size, save data, move to another drive,
  delete.
- **Hold HOME** (⇧H): Quick Settings.

### Save data

Games keep their saves in `~/Library/Application Support/nxnative/<title ID>/`, outside the app.
So:

- **Deleting a game keeps its save data.** Reinstall it, from the Game Store or anywhere else, and
  you carry on where you left off.
- **Save data belongs to the Mac user.** Each person signed in to the Mac has their own.
- **Back up one save** by pressing + on a game and opening **Save Data Backups**, or by selecting
  the title in System Settings › Users. **Back Up All Save Data** creates a snapshot for every title.
- **Restore Latest Backup** first snapshots the current save, so restoring never removes the version
  you were playing. The backup folder can be changed to an external drive in System Settings › Users.
- **Deleting save data** is only in System Settings › Users, and asks twice. It goes to the Trash.

### Storage and drives

System Settings › Data Management shows a bar for the Mac's disk (system memory) and for each
external drive: software, save data, other files and free space. Below it is every game by size.
Press + on a game, or use Move Software in its options, to move it to another drive such as an
external SSD: it's copied, checked byte for byte, then removed from the old drive, and the new
folder joins the library.

### Settings worth knowing

| Page | What it does |
|---|---|
| Airplane Mode, Bluetooth, Internet | Turn Wi-Fi and Bluetooth on and off, see paired controllers, test the connection, set up the Game Store server |
| Screen Brightness, Audio | The Mac's display brightness and output volume, and the HOME Menu sounds |
| Parental Controls | A 4-digit PIN and a daily play time limit; past the limit, starting a game needs the PIN |
| Display | Full screen, keep the game in front, hide the launcher while playing, HOME returns to the launcher |
| Notifications | Which messages appear: updates, downloads, play time |
| Sleep Mode | Auto-Sleep on the HOME Menu, turn off the display, put the Mac to sleep |
| System | Version, Software Update (checks GitHub for new releases), data folder |

The interface follows the language selected in macOS. English, Brazilian Portuguese and Spanish
are included; unsupported languages fall back to English.

### Where things are kept

| What | Where |
|---|---|
| Settings (including the store password) | `~/Library/Application Support/SwitchLauncher/settings.json` (readable only by you) |
| Play history | `~/Library/Application Support/SwitchLauncher/play-history.json` and `play-days.json` |
| Cached game sizes | `~/Library/Application Support/SwitchLauncher/app-sizes.json` |
| Save backups | `~/Documents/Switch/Save Backups/<title ID>/` by default; configurable in System Settings › Users |
| Downloads in progress | `<install folder>/.switch-store/` |
| Launcher logs | `log stream --predicate 'subsystem == "dev.vinicius.switchlauncher"'` |

## Setting up a NAS as your Game Store

The Game Store reads from an S3-compatible "bucket". The simplest way to get one is a small S3
gateway on your NAS that serves a plain folder. You copy games into that folder over a normal
network share, and the gateway hands them to the launcher.

```
Mac ──(SMB share)──▶ NAS folder "switch-games" ◀──(S3 gateway, read-only)── Game Store on any Mac
     store-publish        catalog.json + games/                          home network or internet
```

This works on any NAS that runs Docker containers: TrueNAS SCALE (Apps › Custom App), Synology
(Container Manager), Unraid, QNAP (Container Station), or any Linux machine.

### 1. Make a folder and share it

1. Create a dataset or shared folder, for example `switch-store`, and inside it a folder named
   `switch-games`. That inner folder is the bucket: its name is what you'll enter as **Bucket** in
   the launcher.
2. Share `switch-store` over **SMB** with write access for your user. That's how games get onto
   the NAS.
3. Note the full path of `switch-games` on the NAS, e.g. `/mnt/tank/switch-store/switch-games`
   (TrueNAS) or `/volume1/switch-store/switch-games` (Synology).

Leave plenty of space: games are 1–25 GB each.

### 2. Run the S3 gateway

The gateway is [Versity S3 Gateway](https://github.com/versity/versitygw). Pick a username and a
long password for the launcher's login, then run (compose file for Container Manager, Portainer or
`docker compose up -d`):

```yaml
services:
  switch-store:
    image: versity/versitygw:v1.10.0
    restart: unless-stopped
    command: ["--port", ":7070", "posix", "--nometa", "/data"]
    environment:
      ROOT_ACCESS_KEY: launcher            # the launcher's username
      ROOT_SECRET_KEY: change-me-to-a-long-random-password
    ports:
      - "9000:7070"                        # the launcher talks to port 9000 on the NAS
    volumes:
      - gateway-root:/data                 # the gateway's own small working folder
      - /mnt/tank/switch-store/switch-games:/data/switch-games:ro
volumes:
  gateway-root:
```

- Change the last path to your `switch-games` path from step 1.
- The games folder is mounted **read-only** (`:ro`): the launcher's login can download, but can
  never change or delete anything on the NAS.
- The gateway needs its own writable folder for lock files, which is why `/data` is a separate
  volume and the games sit inside it.

Check it answers: `curl http://<nas-ip>:9000` should reply with an XML "Access Denied" (it wants a
login). That means it's running.

### 3. Put games in the store

On the Mac with your game apps:

1. Mount the share in Finder (Go › Connect to Server, `smb://<nas-ip>/switch-store`).
2. From this repository, publish one game, or every game in a folder:

```bash
swift run -c release store-publish --to "/Volumes/switch-store/switch-games" ~/Documents/Switch/apps/"Mario Kart World.app"
```

```bash
swift run -c release store-publish --to "/Volumes/switch-store/switch-games" --scan ~/Documents/Switch/apps
```

Each game is packed into one archive, written next to `catalog.json` with its version, icon, size
and checksum. Publishing a newer version switches the catalog first and then removes the previous
archive, so only the latest release is retained without leaving clients a broken link. Games at the
same version are skipped; increment `CFBundleShortVersionString` for every release (or use `--force`
to republish a corrected build). `--remove <bundle id>` takes a game out. More options:
[STORE.md](STORE.md).

### 4. Connect the launcher

In the launcher: System Settings › Internet › Game Store Server (or open the Game Store and choose
Sign In).

| Setting | Value |
|---|---|
| Home Network Address | `http://<nas-ip>:9000` |
| Remote Address | optional, see step 5 |
| Bucket | `switch-games` |
| Username / Password | the `ROOT_ACCESS_KEY` / `ROOT_SECRET_KEY` from step 2 |

Choose **Test Connection**: it should say how many games it found. Then open the Game Store and
press A on a game. Downloads install into the folder set in **Install Downloads To**
(`~/Documents/Switch/apps` by default), and the game appears on the HOME Menu when it's done.

The launcher checks `catalog.json` at startup and every six hours. When a catalog version is newer
than an installed game's version, the HOME Menu shows a badge on Game Store and sends one update
notification. Open Game Store and press A on the update: it downloads with resume and checksum
verification, replaces the copy on its current drive, and restores the previous app if installation
cannot finish. Save data is outside the app and is not changed.

Give the NAS a fixed IP address (a DHCP reservation on your router), so the address keeps working.

### 5. Download from anywhere (optional)

To use the store away from home, publish the gateway through a
[Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/):
no ports to open on your router, and HTTPS included.

1. In Cloudflare Zero Trust, create a tunnel and add a public hostname, e.g. `games.example.com`,
   pointing to `http://<nas-ip>:9000`.
2. Run its connector on the NAS (another container, `cloudflare/cloudflared`, with the token
   Cloudflare gives you).
3. Enter `https://games.example.com` as the launcher's **Remote Address**.

The launcher tries the home address first and falls back to the remote one. Big downloads through
a tunnel can be cut or answered with a 503 now and then; the launcher shows "Reconnecting…" and
continues from where it stopped, so you don't need to do anything.

## Troubleshooting

| Problem | What to check |
|---|---|
| Test Connection: "Wrong username or password" (403) | The username and password must match `ROOT_ACCESS_KEY` and `ROOT_SECRET_KEY` exactly. |
| Test Connection: the store didn't answer | Is the container running and port 9000 open? Try `curl http://<nas-ip>:9000` from the Mac. |
| "catalog.json couldn't be read" or no games | Publish at least one game; check `catalog.json` is inside `switch-games`, not next to it. |
| Finder can't connect to the share, or "Permission denied" | Give your SMB user write access. On TrueNAS datasets with POSIX ACLs, the ACL **mask** on the share's root must be `rwx`, or named users are refused. |
| A download stops at "Failed" | It gave up after 10 minutes without data. Press A on the game: it continues from the part already downloaded. |
| A game doesn't appear after installing | Check the install folder is one of the Library Folders (Data Management). |
| A game won't start | Read its log in `~/Library/Logs/nxnative/<title ID>.log`. |
