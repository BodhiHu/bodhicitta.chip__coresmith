# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
#
# Source this to use the CoreSmith Sky130 deployment and the local arm64
# toolchain (see coresmith/SETUP-ARM64.md).
#
#   source designs/cdna5-m1/scripts/env.sh
#
# CORESMITH is the coresmith checkout root; override before sourcing if needed.
if [ -z "${CORESMITH:-}" ]; then
  _here=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)
  CORESMITH=$(cd "$_here/../../.." && pwd)
fi
export CORESMITH
export PDK_ROOT=${PDK_ROOT:-$CORESMITH/.pdk}
export PATH="$CORESMITH/bin:/opt/eda/oss-cad-suite/bin:$PATH"

# Pin the backend binaries to the local (non-nix) tools.
export CORESMITH_BACKEND_YOSYS=/opt/eda/oss-cad-suite/bin/yosys
export CORESMITH_BACKEND_MAGIC=/opt/magic-install/bin/magic
export CORESMITH_BACKEND_NETGEN=/usr/local/bin/netgen
export CORESMITH_BACKEND_KLAYOUT=/usr/bin/klayout
if [ -x /opt/install/OpenROAD/bin/openroad ]; then
  export CORESMITH_BACKEND_OPENROAD=/opt/install/OpenROAD/bin/openroad
fi
if [ -x /opt/openroad-src/src/sta/build/sta ]; then
  export CORESMITH_REAL_STA=/opt/openroad-src/src/sta/build/sta
elif [ -x /opt/install/OpenROAD/bin/sta ]; then
  export CORESMITH_REAL_STA=/opt/install/OpenROAD/bin/sta
fi

# Bring-up exemption: the M1 uses flop LDS/I$ and a 1-D TDM, no generated SRAM.
export CORESMITH_ALLOW_NO_OPENRAM=1
