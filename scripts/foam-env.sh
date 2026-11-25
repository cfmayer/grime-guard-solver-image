# Sourced by login shells, /etc/bash.bashrc and /root/.bashrc: NVHPC toolchain + SPUMA (OpenFOAM v2512) environment.
# Safe under `set -u`/`set -e` callers; idempotent.
if [ -z "${GG_FOAM_ENV_DONE:-}" ]; then
  if [ -f /etc/environment ]; then
    while IFS='=' read -r _k _v; do
      case "$_k" in ''|\#*) continue ;; esac
      _v=${_v%\"}; _v=${_v#\"}; export "$_k=$_v"
    done < /etc/environment
    unset _k _v
  fi
  if [ -f /opt/spuma/etc/bashrc ] && [ -n "${BASH_VERSION:-}" ]; then
    _gg_u=$(case $- in *u*) echo 1;; esac); _gg_e=$(case $- in *e*) echo 1;; esac)
    set +eu
    . /opt/spuma/etc/bashrc
    [ -n "$_gg_u" ] && set -u; [ -n "$_gg_e" ] && set -e; unset _gg_u _gg_e
  fi
  export GG_FOAM_ENV_DONE=1
fi
