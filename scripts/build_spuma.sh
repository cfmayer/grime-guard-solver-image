#!/usr/bin/env bash
# Time-boxed, resumable SPUMA compile. Runs Allwmake for at most BUILD_BUDGET_MIN minutes. If the budget runs out,
# the whole build process group is stopped, files written in the last 15 minutes under build/ and platforms/
# (possibly truncated objects/libs) are deleted so the next run rebuilds them, and BUILD_STATUS stays "partial".
# The next CI job continues from this image; wmake skips everything already up to date.
set -uo pipefail
cd /opt/spuma
[ "$(cat BUILD_STATUS 2>/dev/null)" = complete ] && { echo "already complete"; exit 0; }
BUDGET=${BUILD_BUDGET_MIN:-250}; STAGE=${STAGE:-1}; J=${JOBS:-$(nproc)}
mkdir -p build-logs; LOG=build-logs/allwmake.stage${STAGE}.log
# NVHPC/CUDA/HPC-X paths from /etc/environment, then the SPUMA env
export GG_FOAM_ENV_DONE=
# shellcheck source=/dev/null
. /etc/profile.d/00-spuma.sh
# Without a GPU driver nvc++ -cuda falls back to CUDA 11.8, which the image does not ship ("CUDA version 11.8 is not
# available in this installation"). NVHPC_CUDA_HOME / HPC-X paths come from /etc/environment (gg-write-env).
: "${NVHPC_CUDA_HOME:?}"
export have_cuda=true NVARCH=${NVARCH:-90} FOAM_SIGFPE=false FOAM_MODULE_PREFIX=false WM_NCOMPPROCS=$J
echo "== stage $STAGE: nproc=$(nproc) jobs=$J mem=$(free -g | awk '/Mem/{print $2}')G budget=${BUDGET}min NVARCH=$NVARCH WM_OPTIONS=$WM_OPTIONS"
echo "== NVHPC_CUDA_HOME=$NVHPC_CUDA_HOME OPAL_PREFIX=$OPAL_PREFIX FOAM_MPI=${FOAM_MPI:-?}"
echo "== cxxflags: $(wmake -show-cxxflags 2>/dev/null)"
echo "== nvc++: $(nvc++ --version | sed -n 2p)   nvcc: $(nvcc --version | tail -1)   mpicc: $(command -v mpicc)"
t0=$(date +%s)
# No -q (queue mode): it flattens the nvcc rule into one Makefile and drops the quoting of
# --compiler-options '-Wall -Wextra', so nvcc dies with "Unknown option '-Wextra'" on the first .cu file.
setsid bash -c "./Allwmake -j $J -s" > "$LOG" 2>&1 < /dev/null &
pid=$!
while kill -0 "$pid" 2>/dev/null; do
  sleep 60
  el=$(( $(date +%s) - t0 ))
  if (( el % 900 < 60 )); then
    echo "   $(date -u +%H:%M:%SZ) +$((el/60))min  objects=$(find build -name '*.o' 2>/dev/null | wc -l) libs=$(find platforms -name '*.so' 2>/dev/null | wc -l) apps=$(find platforms -path '*/bin/*' -type f 2>/dev/null | wc -l)"
  fi
  if (( el > BUDGET * 60 )); then
    echo "== budget reached after $((el/60)) min: stopping build (resume in next stage)"
    kill -TERM -- -"$pid" 2>/dev/null; sleep 45; kill -KILL -- -"$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    cut=$(( $(date +%s) - 900 ))
    n=$(find build platforms -type f -newermt "@$cut" 2>/dev/null | wc -l)
    find build platforms -type f -newermt "@$cut" -delete 2>/dev/null
    echo "== removed $n recently written (possibly truncated) files"
    echo "$STAGE" > build-logs/STAGE; echo partial > BUILD_STATUS
    tail -5 "$LOG"
    exit 0
  fi
done
wait "$pid"; rc=$?
el=$(( $(date +%s) - t0 ))
echo "== Allwmake exit $rc after $((el/60)) min (stage $STAGE)"
grep -E -i '(^|[^a-z])error|Error [0-9]|\*\*\*' "$LOG" | grep -v -i 'warning' | tail -40 || true
echo "$STAGE" > build-logs/STAGE
if [ ! -f "$FOAM_LIBBIN/libOpenFOAM.so" ] || [ ! -x "$FOAM_APPBIN/pimpleFoam" ]; then
  echo "== FAILED: Allwmake ended without libOpenFOAM.so/pimpleFoam; last 60 log lines:"; tail -60 "$LOG"; exit 1
fi
echo complete > BUILD_STATUS
echo "objects=$(find build -name '*.o' | wc -l) libs=$(find platforms -name '*.so' | wc -l) apps=$(find platforms -path '*/bin/*' -type f | wc -l)"
exit 0
