# syntax=docker/dockerfile:1.7
# Grime Guard CFD solver image: SPUMA 0.3-v2512 (GPU port of OpenFOAM v2512, Cineca) built with NVHPC nvc++ for one
# CUDA compute capability (NVARCH=90 -> H200/H100 sm_90; NVARCH=100 + NVHPC 25.x -> B200 sm_100).
# No GPU is needed to build. The compile is time-boxed per CI job and resumed from the previous job's image
# (PREV build-arg), because a full SPUMA compile on a 4-vCPU GitHub runner can exceed the 6-hour job limit.
#
# Stages:  base -> src -> compile (repeatable, FROM ${PREV}) -> prune -> final
ARG NVHPC_TAG=24.3-devel-cuda12.3-ubuntu22.04
ARG PREV=src

############################ base: toolchain + runtime deps + env that also works over SSH
FROM nvcr.io/nvidia/nvhpc:${NVHPC_TAG} AS base
ARG NVARCH=90
LABEL org.opencontainers.image.source="https://github.com/cfmayer/grime-guard-solver-image" \
      org.opencontainers.image.description="SPUMA 0.3-v2512 (GPU OpenFOAM v2512) for Grime Guard LES; pimpleFoam + WALE" \
      org.opencontainers.image.licenses="GPL-3.0-or-later"
ENV DEBIAN_FRONTEND=noninteractive \
    SPUMA_DIR=/opt/spuma NVARCH=${NVARCH} have_cuda=true FOAM_SIGFPE=false \
    OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1
# Pod-side tools are baked in so nothing is apt-installed on a billed GPU pod (on-pod attempts lost time and SSH to
# apt + an sshd that was not up yet). libptscotch-dev is deliberately NOT installed: it pulls Ubuntu's OpenMPI,
# which clashes (libmpi.so.40) with the NVHPC/HPC-X OpenMPI that SPUMA is built against.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      git ca-certificates build-essential flex bison cmake zlib1g-dev libscotch-dev libfftw3-dev \
      libboost-system-dev libboost-thread-dev libreadline-dev \
      python3 python3-pip rsync jq procps openssh-server openssh-client curl less vim-tiny tmux htop \
      libgl1 libx11-6 libxrender1 libxext6 libxcursor1 libxft2 libxinerama1 \
    && rm -rf /var/lib/apt/lists/* \
    && pip3 install --no-cache-dir -q 'numpy<2.6' 'pyvista==0.49.*'
COPY scripts/foam-env.sh /etc/profile.d/00-spuma.sh
# Docker ENV is NOT inherited by sshd sessions (on-pod attempt 4 died with "nvc++ missing" for exactly this reason),
# so persist the NVHPC toolchain PATH for SSH logins (pam_env), login shells and non-interactive `ssh host cmd`.
RUN printf 'PATH="%s"\nLD_LIBRARY_PATH="%s"\nCPATH="%s"\nSPUMA_DIR=/opt/spuma\nNVARCH=%s\nhave_cuda=true\nFOAM_SIGFPE=false\nOMPI_ALLOW_RUN_AS_ROOT=1\nOMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1\n' \
        "$PATH" "$LD_LIBRARY_PATH" "$CPATH" "$NVARCH" > /etc/environment \
 && { echo '# Grime Guard: OpenFOAM/SPUMA + NVHPC env (also for non-interactive ssh)'; echo '[ -f /etc/profile.d/00-spuma.sh ] && . /etc/profile.d/00-spuma.sh'; cat /etc/bash.bashrc; } > /tmp/bb && mv /tmp/bb /etc/bash.bashrc \
 && { echo '[ -f /etc/profile.d/00-spuma.sh ] && . /etc/profile.d/00-spuma.sh'; cat /root/.bashrc 2>/dev/null; } > /tmp/rb && mv /tmp/rb /root/.bashrc \
 && mkdir -p /run/sshd /root/.ssh /work && chmod 700 /root/.ssh \
 && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/; s/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config \
 && rm -f /etc/ssh/ssh_host_*

############################ src: pinned SPUMA source, configured for nvc++ + CUDA, system scotch/fftw, no ThirdParty
FROM base AS src
ARG SPUMA_TAG=0.3-v2512
RUN git -c advice.detachedHead=false clone -q --depth 1 --branch ${SPUMA_TAG} https://gitlab.hpc.cineca.it/exafoam/spuma.git /opt/spuma \
 && cd /opt/spuma && git rev-parse HEAD > SPUMA_COMMIT \
 && sed -i 's/^export WM_COMPILER=.*/export WM_COMPILER=Nvidia/; s/^export FOAM_SIGFPE=.*/export FOAM_SIGFPE=false/' etc/bashrc \
 && sed -i 's/^SCOTCH_VERSION=.*/SCOTCH_VERSION=scotch-system/; s#^export SCOTCH_ARCH_PATH=.*#export SCOTCH_ARCH_PATH=/usr#' etc/config.sh/scotch \
 && sed -i 's/^fftw_version=.*/fftw_version=fftw-system/; s#^export FFTW_ARCH_PATH=.*#export FFTW_ARCH_PATH=/usr#' etc/config.sh/FFTW \
 && sed -i 's/^boost_version=.*/boost_version=boost-system/; s/^cgal_version=.*/cgal_version=cgal-none/' etc/config.sh/CGAL \
 && rm -rf .git doc/Doxygen \
 && mkdir -p build-logs && echo 0 > build-logs/STAGE && echo partial > BUILD_STATUS
COPY scripts/build_spuma.sh /usr/local/bin/build_spuma.sh

############################ compile: time-boxed, resumable Allwmake (wmake is incremental on mtimes, which layers keep)
FROM ${PREV} AS compile
ARG STAGE=1
ARG BUILD_BUDGET_MIN=250
ARG NVARCH=90
COPY scripts/build_spuma.sh /usr/local/bin/build_spuma.sh
RUN STAGE=${STAGE} BUILD_BUDGET_MIN=${BUILD_BUDGET_MIN} NVARCH=${NVARCH} bash /usr/local/bin/build_spuma.sh

# tiny export so CI can read whether the compile finished
FROM scratch AS status
COPY --from=compile /opt/spuma/BUILD_STATUS /opt/spuma/build-logs/ /

############################ prune: drop object files, verify the required binaries link
FROM compile AS prune
COPY scripts/check_install.sh /usr/local/bin/check_install.sh
RUN test "$(cat /opt/spuma/BUILD_STATUS)" = complete && bash /usr/local/bin/check_install.sh && rm -rf /opt/spuma/build

############################ final: base + installed SPUMA, sshd entrypoint, solver env sourced everywhere
FROM base AS final
COPY --from=prune /opt/spuma /opt/spuma
COPY scripts/gg-start.sh /usr/local/bin/gg-start
COPY scripts/check_install.sh /usr/local/bin/check_install.sh
RUN chmod +x /usr/local/bin/gg-start /usr/local/bin/check_install.sh && touch /opt/spuma/platforms/.built-${NVARCH}
WORKDIR /work
EXPOSE 22
ENTRYPOINT ["/usr/local/bin/gg-start"]
CMD ["sleep", "infinity"]
