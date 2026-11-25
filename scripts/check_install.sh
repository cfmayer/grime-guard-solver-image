#!/usr/bin/env bash
# Verifies the solver install: required executables exist and every shared library they need resolves
# (libcuda.so.1 / libnvidia-ml come from the host driver at runtime, so they are allowed to be missing here).
set -uo pipefail
# NVHPC/CUDA/HPC-X paths from /etc/environment, then the SPUMA env
export GG_FOAM_ENV_DONE=
# shellcheck source=/dev/null
. /etc/profile.d/00-spuma.sh
REQ="pimpleFoam pisoFoam simpleFoam potentialFoam blockMesh snappyHexMesh surfaceFeatureExtract decomposePar
     reconstructPar reconstructParMesh redistributePar checkMesh foamDictionary postProcess renumberMesh topoSet
     createPatch mapFields setFields foamToVTK foamListTimes"
fail=0
for e in $REQ; do
  p=$(command -v "$e") || { echo "MISSING $e"; fail=1; continue; }
  miss=$(ldd "$p" 2>/dev/null | grep 'not found' | grep -v -E 'libcuda\.so|libnvidia-ml' || true)
  if [ -n "$miss" ]; then echo "UNRESOLVED $e:"; echo "$miss"; fail=1; else echo "ok $e -> $p"; fi
done
for l in libfiniteVolume libturbulenceModels libincompressibleTurbulenceModels liblagrangianIntermediate \
         liblagrangianFunctionObjects libscotchDecomp libdecompose libsnappyHexMesh libfieldFunctionObjects; do
  f=$(ls "$FOAM_LIBBIN/$l.so" 2>/dev/null) && echo "ok $l" || { echo "MISSING lib $l"; fail=1; }
done
[ -d "$FOAM_TUTORIALS/incompressible/pimpleFoam/LES/pitzDaily" ] && echo "ok tutorials" || { echo "MISSING pitzDaily tutorial"; fail=1; }
echo "WM_OPTIONS=$WM_OPTIONS FOAM_MPI=$FOAM_MPI"
exit $fail
