#! /bin/bash
# build-steadystate-solvers.sh
# Trial build of the steady-state solvers.

if make DMD=ldmd2  WITH_COMPLEX_NUMBERS=1 WITH_SSC=1 WITH_SSS=1 FLAVOUR=fast install
then
    echo "Build and install successful for FLAVOUR=fast."
else
    echo "Build and install failed for FLAVOUR=fast."
fi
