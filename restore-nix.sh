#!/usr/bin/env bash
# restore-nix.sh — restore Nix on iuhlwolfap1122 after an IT root-filesystem rebuild.
#
# Background (see logs/debugging/find-nix-0.report, 2026-07-31):
#   The Nix store lives on the persistent /app disk at /app/nix and is exposed
#   at /nix via a BIND MOUNT (a symlink does NOT work — the nix-daemon refuses:
#   "the path '/nix' is a symlink; this is not allowed for the Nix store").
#   IT rebuilds wipe the root FS but preserve /home and /app, destroying:
#     1. the /nix bind mount + its /etc/fstab line
#     2. the nix-daemon systemd units in /etc/systemd/system
#     3. /etc/nix/nix.conf (flakes + build-users-group)
#     4. /etc/profile.d/nix.sh (PATH hook)
#   Everything needed to restore lives in /app/nix — this script relinks it.
#
# Usage: sudo bash restore-nix.sh
set -euo pipefail

STORE_ROOT=/app/nix
SYS_PROFILE=/nix/var/nix/profiles/default

[ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
[ -d "$STORE_ROOT/store" ] || { echo "no Nix store at $STORE_ROOT — wrong box or store lost" >&2; exit 1; }

# 1. /nix bind mount (replace any symlink or stale empty dir)
if [ -L /nix ]; then rm /nix; fi
mkdir -p /nix
if ! mountpoint -q /nix; then
    mount --bind "$STORE_ROOT" /nix
    echo "mounted $STORE_ROOT on /nix"
fi
grep -qE '^\S+\s+/nix\s' /etc/fstab || {
    echo "$STORE_ROOT /nix none bind 0 0" >> /etc/fstab
    echo "added /nix bind mount to /etc/fstab"
}

# 2. nix-daemon systemd units — copy (not symlink) so systemd can read them
#    before the bind mount is up at boot
cp -L "$SYS_PROFILE"/lib/systemd/system/nix-daemon.service /etc/systemd/system/
cp -L "$SYS_PROFILE"/lib/systemd/system/nix-daemon.socket /etc/systemd/system/
systemctl daemon-reload
systemctl enable nix-daemon.socket nix-daemon.service >/dev/null

# 3. nixbld build users (usually survive in /etc/passwd; recreate if not)
if ! getent group nixbld >/dev/null; then
    groupadd -r nixbld
    for i in $(seq 1 32); do
        useradd -r -g nixbld -G nixbld -d /var/empty -s /usr/sbin/nologin "nixbld$i"
    done
    echo "recreated nixbld group + 32 build users"
fi

# 4. /etc/nix/nix.conf
mkdir -p /etc/nix
if [ ! -f /etc/nix/nix.conf ]; then
    printf 'experimental-features = nix-command flakes\nbuild-users-group = nixbld\n' > /etc/nix/nix.conf
    echo "recreated /etc/nix/nix.conf"
fi

# 5. PATH hook
if [ ! -f /etc/profile.d/nix.sh ]; then
    echo 'export PATH=/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin:$PATH' > /etc/profile.d/nix.sh
    echo "recreated /etc/profile.d/nix.sh"
fi

# 6. (Re)start the daemon fresh so it sees the bind-mounted /nix.
#    Restart the service only — starting the socket while the service is
#    active fails with "Socket service already active, refusing".
systemctl restart nix-daemon.service

# 7. Verify
export PATH="$SYS_PROFILE/bin:$PATH"
nix --version
nix store ping
echo "OK — open a new shell (for PATH), then: cd ~/projects/edw && nix develop"
