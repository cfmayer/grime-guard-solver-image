#!/usr/bin/env bash
# Container entrypoint: authorize $PUBLIC_KEY (RunPod injects it from the account's SSH keys), start sshd, then run
# the given command (default: sleep infinity) with the SPUMA/OpenFOAM + NVHPC environment already sourced.
set -u
mkdir -p /root/.ssh /run/sshd /work && chmod 700 /root/.ssh
for k in "${PUBLIC_KEY:-}" "${SSH_PUBLIC_KEY:-}"; do
  [ -n "$k" ] && ! grep -qxF "$k" /root/.ssh/authorized_keys 2>/dev/null && printf '%s\n' "$k" >> /root/.ssh/authorized_keys
done
[ -f /root/.ssh/authorized_keys ] && chmod 600 /root/.ssh/authorized_keys
ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1 || ssh-keygen -A >/dev/null
/usr/sbin/sshd -e && echo "gg-start: sshd up on :22"
# shellcheck source=/dev/null
. /etc/profile.d/00-spuma.sh
echo "gg-start: SPUMA $(cat /opt/spuma/SPUMA_COMMIT 2>/dev/null | cut -c1-12) NVARCH=${NVARCH:-?} pimpleFoam=$(command -v pimpleFoam || echo MISSING)"
command -v nvidia-smi >/dev/null && nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv,noheader || true
if [ $# -eq 0 ]; then set -- sleep infinity; fi
exec "$@"
