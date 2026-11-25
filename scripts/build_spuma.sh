#!/usr/bin/env bash
# Time-boxed, resumable SPUMA compile. Runs Allwmake for at most BUILD_BUDGET_MIN minutes. If the budget runs out,
# the whole build process group is stopped, files written in the last 20 minutes under build/ and platforms/
# (possibly truncated objects/libs) are deleted so the next run rebuilds them, and BUILD_STATUS stays "partial".
# The next CI job continues from this image; wmake skips everything already up to date.
set -uo pipefail
cd /opt/spuma
[ "$(cat BUILD_STATUS 2>/dev/null)" = complete ] && { echo "already complete"; exit 0; }
BUDGET=${BUILD_BUDGET_MIN:-250}; STAGE=${STAGE:-1}
mkdir -p build-logs; LOG=build-logs/allwmake.stage${STAGE}.log
set +eu
# shellcheck source=/dev/null
. /opt/spuma/etc/bashrc
set -u
export have_cuda=true NVARCH=${NVARCH:-90} FOAM_SIGFPE=false FOAM_MODULE_PREFIX=false WM_NCOMPPROCS=$(nproc)
echo "== stage $STAGE: nproc=$(nproc) mem=$(free -g | awk '/Mem/{print $2}')G budget=${BUDGET}min NVARCH=$NVARCH WM_OPTIONS=$WM_OPTIONS"
echo "== nvc++: $(nvc++ --version | sed -n 2p)   nvcc: $(nvcc --version | tail -1)   mpicc: $(command -v mpicc)"
t0=$(date +%s)
setsid bash -c "./Allwmake -j $(nproc) -s -q" > "$LOG" 2>&1 < /dev/null &
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
    cut=$(( $(date +%s) - 1200 ))
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
echo "$STAGE" > build-logs/STAGE; echo complete > BUILD_STATUS
echo "objects=$(find build -name '*.o' | wc -l) libs=$(find platforms -name '*.so' | wc -l) apps=$(find platforms -path '*/bin/*' -type f | wc -l)"
exit 0
