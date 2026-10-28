# Game Store

The launcher's **Game Store** (the eShop button on the HOME Menu) lists games from your own
S3-compatible bucket and installs them on this Mac.

```
store-publish ──(LAN)──▶ SeaweedFS bucket `switch-games` ◀──(LAN or Cloudflare tunnel)── Game Store
  aa archive | multipart       catalog.json                         download → SHA-256 → aa extract
                               games/<slug>/<slug>-<version>.aar
                               games/<slug>/icon.png
```

## Server (homelab)

```bash
./deploy/setup-store.sh
```

It deploys SeaweedFS, an S3-compatible server, to Kubernetes (`deploy/k8s/store.yaml`, data on the
`nfs-client` TrueNAS class, LAN port `30900`). It creates the `switch-games` bucket, an admin login
for publishing and a read-only `launcher` login, plus a dedicated Cloudflare tunnel
(`deploy/k8s/tunnel.yaml`) for `https://games.parseit.net`, served by two `cloudflared` connectors on different nodes. The generated logins are kept in
`~/.config/switch-store/store.env`.

MinIO was the first choice, but it no longer publishes container images.

## Publishing games

```bash
source ~/.config/switch-store/store.env
STORE_PASSWORD=$STORE_ADMIN_PASSWORD swift run -c release store-publish \
    --endpoint http://192.168.1.10:30900 --user "$STORE_ADMIN_USER" \
    --scan "$HOME/Documents/Switch/apps" --scan /Applications/Games --jobs 2
```

`--scan` publishes every game the launcher would recognise in a folder; apps can also be listed
directly. Games already in the store at the same version are skipped (use `--force` to re-upload),
so an interrupted run can simply be started again. `--jobs` uploads several games at once; their
catalog updates are written one after another, so none are lost.

Each app is archived with Apple Archive (LZFSE) and streamed into a multipart upload in 64 MB
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
