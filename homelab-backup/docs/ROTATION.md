# Password & Key Rotation

## Restic repo passwords

There are two restic passwords:
- `/root/.restic/allfather.pwd` (used by allfather, decrypts allfather repos on every target)
- `/root/.restic/heimdall.pwd` (used by heimdall, decrypts heimdall repos on every target)

Each is also stored in your password manager.

### Rotating a restic password

Restic supports adding new passwords without rewriting the repo. Old snapshots remain decryptable by the old key, new snapshots use the new key. To fully rotate:

1. Generate a new password and add it as an additional key:
   ```bash
   export RESTIC_REPOSITORY="rest:http://archy.home:8000/allfather-critical/"
   export RESTIC_PASSWORD_FILE=/root/.restic/allfather.pwd       # current
   restic key add --new-password-file /tmp/new.pwd
   ```
2. Repeat for every repo this password unlocks (4 repos for allfather, 4 for heimdall).
3. Update the source host:
   ```bash
   install -m 600 /tmp/new.pwd /root/.restic/allfather.pwd
   ```
4. Run a full backup cycle to confirm the new password works against every target.
5. Once confirmed, remove the old key from each repo:
   ```bash
   restic key list                                # find old key id
   restic key remove <id>                         # do this for every repo
   ```
6. Update password manager entry.
7. `shred -u /tmp/new.pwd`

If you lose ALL keys for a repo, the data is unrecoverable. Always add the new key BEFORE removing the old.

## SSH keys (rest-server is no-auth, but the password files travel via SSH for setup)

The rest-server itself uses no authentication (auth comes from the restic encryption layer). However, SSH is still used for:
- Running `target-setup/install-rest-server.sh` on each target
- Manual maintenance (offline `restic prune`)

Rotate the root SSH keys whenever:
- A host is decommissioned
- You suspect compromise
- Annually as hygiene

```bash
# on the source host, generate a new key
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_new
# install on every target
for h in archy heimdall allfather; do
  ssh-copy-id -i /root/.ssh/id_ed25519_new.pub root@$h
done
# verify, then swap
mv /root/.ssh/id_ed25519     /root/.ssh/id_ed25519.old
mv /root/.ssh/id_ed25519_new /root/.ssh/id_ed25519
# remove old key from authorized_keys on each target
```

## What to do if a source host is compromised

1. **Treat existing snapshots as still encrypted, but the attacker has the key.** They cannot delete (append-only) but they CAN read.
2. Disable the rest-server's network access for that source's repos immediately (firewall block).
3. Generate a new password OUTSIDE the compromised host.
4. On the targets, run `restic key add` with the new password against each affected repo (this requires the OLD password — recover from your password manager).
5. Run `restic key remove` for the OLD key on each repo.
6. Now the attacker's stolen `allfather.pwd` can no longer decrypt any new snapshots, only old ones.
7. Rebuild the source host. Once clean, install the new password file and resume backups.
8. After confidence is restored: forget+prune snapshots from the compromise window.

## Backing up the password files themselves

Chicken-and-egg: the password files protect the backups, so they must not live ONLY on the source host.

- Primary copy: in your password manager (Vaultwarden / 1Password / Bitwarden).
- Secondary copy: in a sealed envelope in a physical safe. Yes, really.
- The password files are also captured in the `critical` tier under `/root/.restic`, but that's circular — you can't decrypt the backup containing the password without the password.

The point of the password manager + physical copy is that those are **out-of-band** from the homelab.
