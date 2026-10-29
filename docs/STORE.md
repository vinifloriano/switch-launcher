# Game Store

The launcher's **Game Store** (the eShop button on the HOME Menu) lists games from your own
S3-compatible bucket and installs them on this Mac.

```
store-publish ──(SMB)──▶ NAS folder = bucket `switch-games` ◀──(S3 gateway: LAN or Cloudflare tunnel)── Game Store
  aa archive                   catalog.json                                       download → SHA-256 → aa extract
                               games/<slug>/<slug>-<version>.aar
                               games/<slug>/icon.png
```

## Server (homelab)

```bash
./deploy/setup-store.sh
```

The games live in a plain folder on the TrueNAS,
`/mnt/MAIN/k8s-volumes/switch-store-games/switch-games` (SMB share `k8s-volumes`). The script
deploys Versity S3 Gateway (`deploy/k8s/store.yaml`) to Kubernetes. It serves that folder as the
bucket `switch-games` on LAN port `30900`, with a read-only `launcher` login. It mounts the folder
read-only over NFS and is kept off k8s-worker3 (see the network adapter notes below), so downloads
never touch that node. It also sets up a dedicated Cloudflare tunnel (`deploy/k8s/tunnel.yaml`) for
`https://games.parseit.net`, served by two `cloudflared` connectors on different nodes. The
generated login is kept in `~/.config/switch-store/store.env`.

Earlier versions ran MinIO, then SeaweedFS, which kept the games in its own volume format on an NFS
volume. Every upload then passed through the node running it, and k8s-worker3's network adapter kept
cutting them off.

The `vinicius` SMB user needs access to the `k8s-volumes` share. That dataset uses POSIX ACLs, and
the ACL mask caps every named entry, so the mask on the share's root folder must be `rwx`. With the
mask at `rw-`, the share refuses the connection ("Permission denied").

## Publishing games

Mount the `k8s-volumes` share in Finder (`smb://storage01/k8s-volumes`), then:

```bash
swift run -c release store-publish --to /Volumes/k8s-volumes/switch-store-games/switch-games \
    --scan "$HOME/Documents/Switch/apps" --scan /Applications/Games
```

Archives are written under a temporary `.partial` name and renamed when complete, so the store
never serves a half-written game. Writing to the NAS over SMB ran at 80–110 MB/s.

`--scan` publishes every game the launcher would recognise in a folder; apps can also be listed
directly. Games already in the store at the same version are skipped (use `--force` to re-upload),
so an interrupted run can simply be started again. `--jobs` uploads several games at once; their
catalog updates are written one after another, so none are lost.

`--endpoint URL --user NAME` uploads to any S3 bucket instead (multipart, password from
`STORE_PASSWORD`). `--max-rate MB` caps the upload speed in either mode.

### Node network adapters

The cluster nodes use Realtek RTL8156 USB 2.5 GbE adapters (`r8152` driver). Under sustained
multi-GB transfers they hit `NETDEV WATCHDOG … Tx timeout` and reset, dropping the node off the
network for a while. `deploy/nodes/99-r8156-no-tso.rules` turns off TCP/generic segmentation
offload whenever such an adapter appears; it is installed in `/etc/udev/rules.d/` on every node.
Large uploads ran at 30 MB/s with the rule in place.

That was not enough on k8s-worker3: its adapter still reset at 2.5 Gb/s, even with scatter-gather
and TX checksum offload also off. `deploy/nodes/99-r8156-1g.rules` makes the adapter advertise at
most 1 Gb/s (`ethtool -s <if> advertise 0x02f`). With it, worker3 sent ~78 MB/s for 3 minutes with
no resets. It is installed on k8s-worker3 only. To add it to another node, apply it live first with
a rollback timer, because renegotiating drops the link for a few seconds:

```bash
sudo systemd-run --unit=nic-speed-rollback --on-active=150 /usr/sbin/ethtool -s <if> advertise 0x80000000002f
sudo ethtool -s <if> advertise 0x02f
ping -c3 192.168.1.6 && sudo systemctl stop nic-speed-rollback.timer   # keep it only if the node is reachable
```

Then copy the rule to `/etc/udev/rules.d/` and run `sudo udevadm control --reload`.

Each app is archived with Apple Archive (LZFSE) and streamed straight to its destination in 64 MB
parts, so no local copy is written. The catalog entry records the archive's size and SHA-256;
publishing a new version replaces the old archive.

## Launcher

Open the Game Store and choose **Sign In** (or System Settings › Store): enter the home-network
address, optionally the remote address, and the `launcher` username and password. The password is
saved in the launcher's settings file (`~/Library/Application Support/SwitchLauncher/settings.json`,
readable only by your user).

Downloads resume after network drops, are checked against the catalog's SHA-256, extracted with
`aa extract` and moved into the install folder (System Settings › Store › Install Downloads To). An
older copy of the app goes to the Trash.

## Testing without a server

```bash
python3 -m venv /tmp/moto && /tmp/moto/bin/pip install "moto[server]"
/tmp/moto/bin/moto_server -H 127.0.0.1 -p 9100 &
curl -X PUT http://127.0.0.1:9100/switch-games
STORE_PASSWORD=x swift run store-publish --endpoint http://127.0.0.1:9100 --user x Some.app
STORE_TEST_ENDPOINT=http://127.0.0.1:9100 STORE_TEST_GAME=<bundle id> STORE_TEST_SOURCE=Some.app \
    swift test --filter StoreServiceIntegrationTests
```
