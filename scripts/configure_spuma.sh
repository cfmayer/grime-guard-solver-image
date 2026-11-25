#!/usr/bin/env bash
# Configures the SPUMA checkout for this image: nvc++ + CUDA, system scotch/FFTW (no ThirdParty tree), no CGAL,
# and a portable host-CPU target for nvc/nvc++ (default -tp=native would bake in the CI runner's CPU).
set -euo pipefail
cd /opt/spuma
T=${CPU_TARGET:-x86-64-v3}
sed -i 's/^export WM_COMPILER=.*/export WM_COMPILER=Nvidia/; s/^export FOAM_SIGFPE=.*/export FOAM_SIGFPE=false/' etc/bashrc
sed -i 's/^SCOTCH_VERSION=.*/SCOTCH_VERSION=scotch-system/; s#^export SCOTCH_ARCH_PATH=.*#export SCOTCH_ARCH_PATH=/usr#' etc/config.sh/scotch
sed -i 's/^fftw_version=.*/fftw_version=fftw-system/; s#^export FFTW_ARCH_PATH=.*#export FFTW_ARCH_PATH=/usr#' etc/config.sh/FFTW
sed -i 's/^boost_version=.*/boost_version=boost-system/; s/^cgal_version=.*/cgal_version=cgal-none/' etc/config.sh/CGAL
sed -i "/^CC *:= nvc++/ s/\$/ -tp=$T/" wmake/rules/General/Nvidia/c++
sed -i "/^cc *:= nvc\\\$/ s/\$/ -tp=$T/; /^cc *:= nvc\\\$(COMPILER_VERSION)\$/ s/\$/ -tp=$T/" wmake/rules/General/Nvidia/c
grep -q -- "-tp=$T" wmake/rules/General/Nvidia/c++
grep -q -- "-tp=$T" wmake/rules/General/Nvidia/c
grep -n -E '^(CC|cc) ' wmake/rules/General/Nvidia/c++ wmake/rules/General/Nvidia/c
grep -n -E '^export (WM_COMPILER|FOAM_SIGFPE)=' etc/bashrc
