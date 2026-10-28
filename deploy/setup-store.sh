#!/bin/bash
# Sets up the Game Store server on the homelab:
#   1. SeaweedFS (S3) in the `switch-store` namespace (data on the TrueNAS NFS class), LAN port 30900
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

# 2. S3 server
echo "▸ SeaweedFS"
S3_JSON=$(cat <<JSON
{"identities":[
  {"name":"$STORE_ADMIN_USER","credentials":[{"accessKey":"$STORE_ADMIN_USER","secretKey":"$STORE_ADMIN_PASSWORD"}],
   "actions":["Admin","Read","List","Tagging","Write"]},
  {"name":"$STORE_USER","credentials":[{"accessKey":"$STORE_USER","secretKey":"$STORE_PASSWORD"}],
   "actions":["Read:$BUCKET","List:$BUCKET"]}
]}
JSON
)
# Replaced by SeaweedFS (MinIO no longer publishes images); frees NodePort 30900.
$SSH "$K8S" "kubectl get ns switch-store >/dev/null 2>&1 && kubectl -n switch-store delete deploy/minio svc/minio secret/minio-root --ignore-not-found || true"
kubectl apply -f - < k8s/store.yaml
printf '%s' "$S3_JSON" | $SSH "$K8S" "kubectl -n switch-store create secret generic store-s3-config --from-file=s3.json=/dev/stdin --dry-run=client -o yaml | kubectl apply -f -"
kubectl -n switch-store rollout restart deploy/seaweedfs
kubectl -n switch-store rollout status deploy/seaweedfs --timeout=300s

echo "▸ Bucket"
for _ in $(seq 1 30); do
    if kubectl -n switch-store exec deploy/seaweedfs -- sh -c "echo 's3.bucket.create -name $BUCKET' | weed shell -master=localhost:9333" 2>&1 | grep -qiE "created|exist"; then
        break
    fi
    sleep 5
done
kubectl -n switch-store exec deploy/seaweedfs -- sh -c "echo 's3.bucket.list' | weed shell -master=localhost:9333"

# 3. Cloudflare tunnel
echo "▸ Cloudflare tunnel → https://$HOSTNAME_PUBLIC"
CF="pct exec $TUNNEL_CT -- /usr/local/bin/cloudflared"
has_tunnel() { $SSH "$PROXMOX" "$CF tunnel list -o json" | python3 -c 'import json,sys; sys.exit(0 if any(t["name"]=="switch-store" for t in json.load(sys.stdin)) else 1)'; }
if ! has_tunnel; then
    $SSH "$PROXMOX" "$CF tunnel create switch-store" >/dev/null
fi
TUNNEL_ID=$($SSH "$PROXMOX" "$CF tunnel list -o json" | python3 -c 'import json,sys; print(next(t["id"] for t in json.load(sys.stdin) if t["name"]=="switch-store"))')
# Pass the tunnel ID with an empty config: the container's own config.yml names another tunnel,
# and cloudflared would otherwise route the hostname there.
$SSH "$PROXMOX" "pct exec $TUNNEL_CT -- sh -c 'printf {} > /tmp/empty-cloudflared.yml && /usr/local/bin/cloudflared tunnel --config /tmp/empty-cloudflared.yml route dns --overwrite-dns $TUNNEL_ID $HOSTNAME_PUBLIC; rm -f /tmp/empty-cloudflared.yml'"
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
