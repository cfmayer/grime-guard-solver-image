# grime-guard-solver-image

Prebuilt container image for the Grime Guard LES runs: **SPUMA 0.3-v2512** (Cineca's GPU port of OpenFOAM v2512;
`pimpleFoam` + WALE run on the GPU) compiled with NVHPC `nvc++` 24.3 / CUDA 12.3 for **sm_90 (H100/H200)**.
Only open-source solver code is in the image (no geometry, no cases).

```
ghcr.io/cfmayer/grime-guard-solver-image:latest      # sm_90 (also :sm90, :<short-sha>, :sm90-<short-sha>)
```

## Why this exists
Five on-pod attempts to install and compile SPUMA on a billed H200 pod failed ($3.11 spent). Causes, and what the image changes:

| attempt | failure | fix in this image |
|---|---|---|
| 13:19 | pod create returned HTTP 400 (request body) | n/a (orchestration); a validated create command is below |
| 13:22 | `rsync` missing on the box | n/a (box side); `rsync` is also baked into the image |
| 13:35 | SSH session timed out while `apt-get`/bootstrap ran in the foreground (27 min) | nothing is apt-installed on the pod; SPUMA is precompiled |
| 14:11 | `nvc++ missing`: Docker `ENV PATH` is not inherited by sshd sessions | NVHPC PATH/LD_LIBRARY_PATH written to `/etc/environment`, `/etc/profile.d`, `/etc/bash.bashrc`, `/root/.bashrc` |
| 14:14 | liveness poll declared failure 1 s after starting the detached compile (race), so the multi-hour compile never ran | compile happens in CI, not on the pod |
| 14:22 | `ssh: Connection refused`: sshd was apt-installed by the start command and was not up yet | `openssh-server` baked in; entrypoint starts sshd immediately from `$PUBLIC_KEY` |

The original `node/Dockerfile.spuma` was never built (no Docker on the box). Building it surfaced five more blockers,
all fixed here (each one was hit in a local test build, then fixed):

| failure in the original Dockerfile | fix |
|---|---|
| `apt-get update` fails: the NVHPC base image's `linux.mellanox.com` apt source returns HTTP 500 | drop that apt source (not needed), apt retries on |
| `nvc++-Error-CUDA version 11.8 is not available`: with no GPU driver (any CI builder) nvc++ falls back to CUDA 11.8 | pin `NVHPC_CUDA_HOME` to the installed CUDA (12.3) |
| `mpicc-Error-MPI matching the current driver version (0)...`, then `mpi.h` not found | use the HPC-X OpenMPI directly (`comm_libs/12.3/hpcx/latest/ompi`), same at build and run time |
| `nvcc fatal: Unknown option '-Wextra'` on the first `.cu` file: `Allwmake -q` (queue mode) drops the quoting of `--compiler-options` | build without `-q` |
| nvc++ defaults to `-tp=native`, so binaries would target whatever CPU the CI runner had (SIGILL risk on the pod) | `-tp=x86-64-v3` (AVX2/FMA) patched into the Nvidia wmake rules |

Other build fixes vs. the original `Dockerfile.spuma`: system scotch (snappyHexMesh decomposition uses `method scotch`;
there is no ThirdParty tree), system FFTW, CGAL disabled, `libptscotch-dev` dropped (it drags in Ubuntu's OpenMPI,
which clashes with the HPC-X OpenMPI SPUMA links against), optional modules skipped, object files removed from the
final image, install verified (`check_install.sh`: required apps present, all shared libs resolve).

## Using it
The entrypoint (`gg-start`) authorizes `$PUBLIC_KEY`, starts sshd on 22, sources the SPUMA + NVHPC environment and
runs the command (default `sleep infinity`). Every shell (SSH login, `ssh host cmd`, `docker exec bash`) has
`pimpleFoam`, `blockMesh`, `snappyHexMesh`, `mpirun`, `nvc++` on PATH. `/opt/spuma/platforms/.built-90` exists, so
`grime-guard/cloud/node/bootstrap.sh` skips the compile. GPU runs need the SPUMA memory pool flags, e.g.
`pimpleFoam -pool fixedSizeMemoryPool -poolSize 60`.

Runpod (spends money; Community H200 SXM; see `runpod/create_pod.sh`):
```
curl -sS -X POST https://api.runpod.io/v2/pods -H "Authorization: Bearer $RUNPOD_API_KEY" -H 'Content-Type: application/json' -d '{"name":"grimeguard-spuma","cloud":"COMMUNITY","gpu":{"id":"NVIDIA H200","count":1,"minCudaVersion":"12.3"},"image":"ghcr.io/cfmayer/grime-guard-solver-image:latest","disk":400,"ports":["22/tcp"],"startSsh":true}'
```

## How the build works
`.github/workflows/build.yml` runs on push to `main` and on manual dispatch. The compile is time-boxed per job
(`budget_min`, default 250 min) and chained over up to 4 jobs: each job resumes the previous job's partial build
image (`:wip-<sha>-sm90-<n>`; wmake is incremental and layer mtimes are preserved) so no job hits the 6-hour limit.
The first job that finishes the compile builds the slim `final` stage and pushes the tags. Dependency layers use the
GitHub Actions cache. B200 (sm_100): dispatch with `nvarch=100` and an NVHPC >= 25.x tag (e.g.
`25.3-devel-cuda12.8-ubuntu22.04`); untested. SPUMA upstream has only tested cc 7.0/8.0.

The `:wip-*` tags are intermediate build trees and can be deleted from the package page after a successful build.
