#!/bin/bash
# Sets up the Game Store server on the homelab:
#   1. MinIO in the `switch-store` namespace (data on the TrueNAS NFS class), LAN port 30900
#   2. bucket `switch-games`, an admin login for publishing and a read-only `launcher` login
#   3. a dedicated Cloudflare tunnel `switch-store` → https://games.parseit.net
# Logins are generated once and kept in ~/.config/switch-store/store.env (owner-only).
# Safe to run again: existing logins, tunnel and DNS route are reused.
set -euo pipefail
cd "$(dirname "$0")"

SSH="ssh -i $HOME/.ssh/homelab -o IdentitiesOnly=yes -o BatchMode=yes"
K8S="${K8S_HOST:-k8s-master01}"
PROXMOX="${PROXMOX_HOST:-hypervisor01}"
TUNNEL_CT="${TUNNEL_CT:-108}"          # LXC that holds the Cloudflare login (cert.pem)
HOSTNAME_PUBLIC="${STORE_HOSTNAME:-games.parseit.net}"
BUCKET="${STORE_BUCKET:-switch-games}"
ENV_FILE="$HOME/.config/switch-store/store.env"

# Runs kubectl on the control plane; arguments are quoted so they survive the remote shell.
kubectl() { $SSH "$K8S" "kubectl $(printf '%q ' "$@")"; }
random() { openssl rand -base64 48 | tr -d '/+=' | cut -c1-32; }

# 1. Logins
mkdir -p "$(dirname "$ENV_FILE")"
chmod 700 "$(dirname "$ENV_FILE")"
if [[ ! -f "$ENV_FILE" ]]; then
    umask 077
    cat > "$ENV_FILE" <<EOF
STORE_ADMIN_USER=switchadmin
STORE_ADMIN_PASSWORD=$(random)
STORE_USER=launcher
STORE_PASSWORD=$(random)
EOF
fi
chmod 600 "$ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

# 2. MinIO
echo "▸ MinIO"
kubectl apply -f - < k8s/minio.yaml
kubectl -n switch-store create secret generic minio-root \
    --from-literal=MINIO_ROOT_USER="$STORE_ADMIN_USER" \
    --from-literal=MINIO_ROOT_PASSWORD="$STORE_ADMIN_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl -n switch-store rollout status deploy/minio --timeout=300s

echo "▸ Bucket and read-only launcher login"
POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject","s3:ListBucket","s3:GetBucketLocation"],"Resource":["arn:aws:s3:::'"$BUCKET"'","arn:aws:s3:::'"$BUCKET"'/*"]}]}'
# The MinIO image ships the `mc` client.
kubectl -n switch-store exec deploy/minio -- sh -c "
    mc alias set store http://127.0.0.1:9000 '$STORE_ADMIN_USER' '$STORE_ADMIN_PASSWORD' >/dev/null &&
    mc mb --ignore-existing store/$BUCKET &&
    echo '$POLICY' > /tmp/launcher-read.json &&
    (mc admin policy create store launcher-read /tmp/launcher-read.json >/dev/null || true) &&
    mc admin user add store '$STORE_USER' '$STORE_PASSWORD' >/dev/null &&
    (mc admin policy attach store launcher-read --user '$STORE_USER' >/dev/null 2>&1 || true) &&
    echo 'bucket and launcher login ready'"

# 3. Cloudflare tunnel
echo "▸ Cloudflare tunnel → https://$HOSTNAME_PUBLIC"
CF="pct exec $TUNNEL_CT -- /usr/local/bin/cloudflared"
has_tunnel() { $SSH "$PROXMOX" "$CF tunnel list -o json" | python3 -c 'import json,sys; sys.exit(0 if any(t["name"]=="switch-store" for t in json.load(sys.stdin)) else 1)'; }
if ! has_tunnel; then
    $SSH "$PROXMOX" "$CF tunnel create switch-store" >/dev/null
fi
TUNNEL_ID=$($SSH "$PROXMOX" "$CF tunnel list -o json" | python3 -c 'import json,sys; print(next(t["id"] for t in json.load(sys.stdin) if t["name"]=="switch-store"))')
$SSH "$PROXMOX" "$CF tunnel route dns switch-store $HOSTNAME_PUBLIC" || true
$SSH "$PROXMOX" "pct exec $TUNNEL_CT -- cat /root/.cloudflared/$TUNNEL_ID.json" \
    | $SSH "$K8S" "kubectl -n switch-store create secret generic tunnel-credentials --from-file=credentials.json=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -"
sed "s/^    tunnel: switch-store/    tunnel: $TUNNEL_ID/" k8s/tunnel.yaml | kubectl apply -f -
kubectl -n switch-store rollout status deploy/cloudflared --timeout=180s

LAN_IP=$($SSH "$K8S" "hostname -I | cut -d' ' -f1")
cat <<EOF

✓ Game Store server is ready.
  Home network address: http://$LAN_IP:30900
  Remote address:       https://$HOSTNAME_PUBLIC
  Bucket:               $BUCKET
  Launcher login:       $STORE_USER  (password in $ENV_FILE)
  Publishing login:     $STORE_ADMIN_USER  (password in $ENV_FILE)
EOF
