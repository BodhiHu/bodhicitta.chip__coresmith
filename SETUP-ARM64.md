# CoreSmith setup on Ubuntu 24.04 / arm64 (this machine)

`SETUP.md` documents the three upstream install paths.  On this host
(Ubuntu 24.04, **aarch64**, no Nix, no Docker) the x86 Docker image and the
Nix flake are not usable, and the arm64 OSS-CAD-Suite tarball does not ship
OpenROAD/Magic/netgen/KLayout.  This page records the exact local setup that
was used, so it can be repeated.

## What is installed

| Component | Version / path | How |
|---|---|---|
| Python | 3.12.3 | `python3 -m venv coresmith/venv` |
| Python deps | `coresmith/requirements.txt` | `venv/bin/pip install -r requirements.txt` |
| Orchestrator | editable | `venv/bin/pip install -e orchestrator/` |
| OSS-CAD-Suite | 2026-11-06 arm64, `/opt/eda/oss-cad-suite` | GitHub release tarball |
| Yosys | 0.70+344 | OSS-CAD-Suite |
| Verilator | 5.055 | OSS-CAD-Suite |
| Icarus Verilog | 14.0 | OSS-CAD-Suite |
| Magic | 8.3 rev 695 (source build) | Sky130 requires >= 8.3.411; apt's 8.3.105 is too old |
| netgen | 1.5.133 | `apt install netgen-lvs` (`/usr/lib/netgen/bin/netgen`) |
| KLayout | 0.28.16 | `apt install klayout` |
| Sky130 PDK | commit `c6d73a35…` (see `scripts/pdk-version.env`) | volare tarballs, extracted into `.pdk` |
| OpenROAD | built from source, Bazel | `/opt/openroad-src`, install under `/opt/install/OpenROAD` |
| OpenSTA | `src/sta` submodule / OpenROAD build | `CORESMITH_REAL_STA` |

## 1. Python and OSS-CAD-Suite

```bash
cd coresmith
python3 -m venv venv
venv/bin/pip install -r requirements.txt
venv/bin/pip install -e orchestrator/
venv/bin/pip install volare

cd /opt/eda
curl -fL -o oss.tgz \
  https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-11-06/oss-cad-suite-linux-arm64-20261106.tgz
tar --no-same-owner -xzf oss.tgz
export PATH=/opt/eda/oss-cad-suite/bin:$PATH
```

The arm64 tarball has Yosys/Verilator/iverilog but **no OpenROAD, Magic,
netgen or KLayout**.  Install the Debian packages:

```bash
sudo apt-get install -y netgen-lvs klayout zstd libboost-all-dev \
  cmake zlib1g-dev libeigen3-dev libspdlog-dev libfmt-dev swig bison flex \
  tcl-dev tk-dev libx11-dev libcairo2-dev
sudo ln -sf /usr/lib/netgen/bin/netgen /usr/local/bin/netgen

# Magic: Ubuntu 24.04 ships 8.3.105, but the Sky130 tech files require
# 8.3.411+.  Build a current Magic from source:
cd /opt
git clone --depth 1 https://github.com/RTimothyEdwards/magic.git magic-src
cd magic-src
./configure --prefix=/opt/magic-install && make -j4 && make install
/opt/magic-install/bin/magic --version   # 8.3.695 or newer
```

## 2. Sky130 PDK

The volare GitHub API is rate-limited/flaky from this host.  The PDK can be
fetched directly from the release assets at the commit pinned in
`scripts/pdk-version.env`:

```bash
cd coresmith
source scripts/pdk-version.env
C=$SKY130_PDK_COMMIT
V=.pdk/volare/sky130/versions/$C
mkdir -p "$V" /tmp/pdktars
cd /tmp/pdktars
for f in common sky130_fd_io sky130_fd_pr sky130_fd_sc_hd \
         sky130_fd_sc_hvl sky130_ml_xx_hd sky130_sram_macros; do
  curl -fL --retry 5 -o "$f.tar.zst" \
    "https://github.com/efabless/volare/releases/download/sky130-$C/$f.tar.zst"
  tar --zstd -xf "$f.tar.zst" -C "$V"
done
cd coresmith
ln -sfn "volare/sky130/versions/$C/sky130A" .pdk/sky130A
ln -sfn "volare/sky130/versions/$C/sky130B" .pdk/sky130B
echo "$C" > .pdk/volare/sky130/current
```

## 3. OpenROAD

OpenROAD removed its CMake build on 2026-11-01; Bazel is the only supported
build system.  The arm64 build works but needs the `src/sta` submodule:

```bash
cd /opt
git clone --depth 1 https://github.com/The-OpenROAD-Project/OpenROAD.git openroad-src
cd openroad-src
git submodule update --init --recursive
sudo ./etc/DependencyInstaller.sh -bazel -no-gui
bazelisk run --jobs=4 --//:platform=cli //:install
# installs /opt/install/OpenROAD/bin/openroad (path is relative to the repo's parent)
```

If memory is tight, use `--jobs=2`.  The binary is
`/opt/install/OpenROAD/bin/openroad`.

**arm64 source patch (required with the 2026-11-07 HEAD):** the LEF/DEF lexers
declare `char fc` and compare it to `EOF` (-1); clang on aarch64 treats `char`
as unsigned and `-Werror` turns this into a hard build failure.  Change both
to `int fc`:

```bash
sed -i 's/^  char fc;/  int fc;/' \
  src/odb/src/lef/lef/lef_keywords.cpp \
  src/odb/src/def/def/def_keywords.cpp
```

OpenSTA: the `src/sta` submodule can be built standalone if the OpenROAD
install does not ship a `sta` binary.  It needs CUDD; Debian has no CUDD
package, so build it first:

```bash
sudo apt-get install -y libtool automake autoconf libgtest-dev
cd /opt
git clone --depth 1 https://github.com/ivmai/cudd.git cudd-src
cd cudd-src && autoreconf -fi && ./configure --prefix=/opt/cudd && make -j4 && make install

cd /opt/openroad-src/src/sta
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF -DCUDD_DIR=/opt/cudd
cmake --build build -j2
export CORESMITH_REAL_STA=$PWD/build/sta
```

## 4. Environment for CoreSmith

Add to your shell (or a local `.env`):

```bash
export PATH=/workspace/菩提树/coresmith/bin:/opt/eda/oss-cad-suite/bin:$PATH
export PDK_ROOT=/workspace/菩提树/coresmith/.pdk
export CORESMITH_ALLOW_NO_OPENRAM=1        # this design has no SRAM macros yet
export CORESMITH_BACKEND_OPENROAD=/opt/install/OpenROAD/bin/openroad
export CORESMITH_BACKEND_MAGIC=/usr/bin/magic
export CORESMITH_BACKEND_NETGEN=/usr/local/bin/netgen
export CORESMITH_BACKEND_YOSYS=/opt/eda/oss-cad-suite/bin/yosys
export CORESMITH_BACKEND_KLAYOUT=/usr/bin/klayout
export CORESMITH_REAL_STA=/opt/openroad-src/src/sta/build/sta
```

Then:

```bash
cd coresmith
make preflight          # must print {"ok": true, "warnings": [...]}
bin/coresmith daemon start --project-root /workspace/菩提树/coresmith/designs/cdna5-m1/project
bin/coresmith schema --json
```

## Differences from SETUP.md

* **No Docker / Nix**; the OSS-CAD-Suite tarball supplies Yosys/Verilator.
* **OpenROAD built from source** (arm64 prebuilt `.deb`s are amd64-only).
* **Magic/netgen/KLayout from Ubuntu apt** instead of the nix flake.
* **PDK fetched manually** from the pinned volare release assets; `volare enable`
  itself fails here on GitHub API timeouts.
* **Python 3.12** instead of the documented 3.11; the orchestrator and tests are
  compatible.
* **OpenRAM** is not installed; `CORESMITH_ALLOW_NO_OPENRAM=1` is used because
  the M1 bring-up uses flop-based LDS/I$ and a 1-D TDM, not generated macros.
  This is a bring-up exemption, not a production configuration.
