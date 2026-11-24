# Muninn rest-server hardening

Current unit: `--no-auth --listen 0.0.0.0:8000 --append-only`, path `/Tres/restic-repos`.
Change to per-host auth with private repos. All commands need sudo on muninn.

```bash
# 1. users (one per host); apr1 hashes, no extra packages needed
for u in thor heimdall huginn odin; do
  p=$(openssl rand -base64 24); echo "$u $p"   # save each in Vaultwarden NOW
  printf '%s:%s\n' "$u" "$(openssl passwd -apr1 "$p")" | sudo tee -a /Tres/restic-repos/.htpasswd >/dev/null
done
sudo chown restic-backup: /Tres/restic-repos/.htpasswd; sudo chmod 600 /Tres/restic-repos/.htpasswd

# 2. unit: replace --no-auth line, bind to tailnet + LAN only
#    ExecStart=/usr/local/bin/rest-server --path /Tres/restic-repos \
#      --listen 100.83.19.1:8000 --htpasswd-file /Tres/restic-repos/.htpasswd \
#      --private-repos --append-only
sudo systemctl edit --full rest-server && sudo systemctl restart rest-server
curl -s -o /dev/null -w '%{http_code}\n' http://100.83.19.1:8000/thor/kit/config   # expect 401
```
Old repos (`allfather-*`, `heimdall-*`, `odin-*`) become unreachable over HTTP, which is intended.

Prune is offline on muninn (append-only blocks it from sources), weekly:
`restic -r /Tres/restic-repos/<host>/<tier> forget --keep-daily 7 --keep-weekly 4 --keep-monthly 3 --prune`
needs that repo's password, so run it by hand or from a root-only timer once passwords are stored there.
