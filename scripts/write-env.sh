#!/usr/bin/env bash
# Writes /etc/environment with the NVHPC toolchain, the CUDA toolkit and the HPC-X OpenMPI resolved to concrete paths.
# Why: (1) Docker ENV is not inherited by sshd sessions; (2) NVHPC's comm_libs/mpi/bin/mpicc and nvc++ -cuda pick the
# CUDA/MPI flavour from the GPU driver, and with no driver (CI build) they fall back to CUDA 11.8, which this image
# does not ship. Pinning the installed CUDA + HPC-X OpenMPI makes build time and run time use the same stack.
set -euo pipefail
R=$(ls -d /opt/nvidia/hpc_sdk/Linux_x86_64/[0-9]*.[0-9]* | sort -V | tail -1)
CUDA=$(ls -d "$R"/cuda/[0-9]*.[0-9]* | sort -V | tail -1)
H=$(ls -d "$R"/comm_libs/[0-9]*.[0-9]*/hpcx/latest | sort -V | tail -1)
P="$H/ompi/bin:$PATH"
L="$H/ompi/lib:$H/ucx/lib:$H/ucc/lib:$H/hcoll/lib:$H/sharp/lib:${LD_LIBRARY_PATH:-}"
cat > /etc/environment <<EOT
PATH="$P"
LD_LIBRARY_PATH="$L"
CPATH="${CPATH:-}"
NVHPC_ROOT="$R"
NVHPC_CUDA_HOME="$CUDA"
NVHPC_COMM_LIBS_HOME="$(dirname "$(dirname "$H")")"
OPAL_PREFIX="$H/ompi"
HPCX_DIR="$H"
SPUMA_DIR=/opt/spuma
NVARCH=${NVARCH:-90}
have_cuda=true
FOAM_SIGFPE=false
OMPI_ALLOW_RUN_AS_ROOT=1
OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
EOT
cat /etc/environment
