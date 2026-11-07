"""Mission-scale acceptance stimulus for the CDNA5-M1 accelerator (FRD mandate).

Executed by the Full Model DV gate (uarch stage) and the RTL Acceptance DV
gate.  Deterministic, stdlib-only and self-contained: every input is generated
from ``SEED`` and every expected output from :func:`reference`.

The workload is a COMPLETE unit of the IP's mission -- not one tile:

  * GEMM case: GRID_X = 8 workgroups x WG_SIZE = 32 lanes, K = 256
    (8 K-blocks of 32), 8 output tiles of 16x16 int32 = 2048 outputs,
    64 back-to-back 16x16x32 MFMA operations.
  * VECADD case: GRID_X = 8 workgroups x WG_SIZE = 32 lanes x 16 words/lane
    = 4096 int32 lane-additions, including int32 wrap corners.

Geometry contract (tile-shaped; never transposed):

  * one MFMA computes ``C[16][16] int32 = A[16][32] x B[32][16]``
  * ``a[row][k]`` for k in 0..K_TOTAL-1, row-major
  * ``b[tile][k][col]``, per output tile
  * workgroup ``t`` computes ``C_t = A x B_t``
  * packed form is two E2M1 nibbles per byte, low nibble first
  * K = 256 is accumulated across 8 K-blocks by SOFTWARE (the core computes
    ``C = A*B`` per operation -- SAD AD-8); the per-K-block C image is also
    a trace point, so a hardware accumulate cannot hide an error.

Numeric contract (SAD AD-7 / S5):

  * E2M1 code = {sign, mag[2:0]}; magnitudes decode to the x2 integer
    sequence ``{0,1,2,3,4,6,8,12}`` with the sign applied
  * the hardware product is x4 the nominal FP4 product; software removes the
    x4 and applies the E8M0 block scale ``2**(e-127)`` per 32-element block
  * no scale inside the MAC tree; the C comparison below is byte-exact int32
    in the hardware (x4) domain, exactly as KPI-CORR-001 requires.

Scale metadata is carried for the software-epilogue check (INV-009):
``C_sw = C_hw * 2**(e_a + e_b - 256)``.  It does NOT affect the C comparison.
"""

from __future__ import annotations

import hashlib
import json
import random

__all__ = [
    "SEED",
    "E2M1_MAG_X2",
    "MI",
    "TI",
    "TI_K",
    "K_BLOCKS",
    "K_TOTAL",
    "cases",
    "stimulus",
    "decode_e2m1",
    "reference",
    "case_sha256",
    "content_sha256",
    "CONTENT_SHA256",
    "verify",
]

SEED = 0x5EEDCDA5

# x2 integer representation of the E2M1 magnitudes {0, 0.5, 1, 1.5, 2, 3, 4, 6}
E2M1_MAG_X2 = (0, 1, 2, 3, 4, 6, 8, 12)

MI = 16            # tile rows (M)
TI = 16            # tile columns (N)
TI_K = 32          # K per MFMA
K_BLOCKS = 8       # K-blocks per workgroup (mission K = 256)
K_TOTAL = K_BLOCKS * TI_K


def decode_e2m1(code: int) -> int:
    """E2M1 nibble (bit3 = sign) -> signed x2 integer value."""
    mag = E2M1_MAG_X2[code & 0x7]
    return -mag if (code & 0x8) else mag


# ---------------------------------------------------------------------------
# Case 1 -- full-grid MXFP4 GEMM, 8 workgroups, K = 256
# ---------------------------------------------------------------------------

def _make_gemm_case() -> dict:
    rng = random.Random(SEED)

    # A is shared by every workgroup: 16 rows x 256 K nibbles.
    a = [[rng.randrange(16) for _ in range(K_TOTAL)] for _ in range(MI)]
    # B differs per output tile: 8 tiles x 256 K x 16 columns.
    b = [[[rng.randrange(16) for _ in range(TI)] for _ in range(K_TOTAL)]
         for _ in range(8)]

    # Boundary-exercising content (never flat/synthetic-uniform).
    a[0] = [0x7] * K_TOTAL                 # max positive magnitude, all K
    a[1] = [0x0] * K_TOTAL                 # exact zero row
    a[2] = [0xF] * K_TOTAL                 # max negative magnitude, all K
    a[3][0:16] = [0x8] * 16                # negative zero
    for code in range(16):                 # every E2M1 code appears in A
        a[4][code] = code
    for t in range(8):
        for k in range(K_TOTAL):
            b[t][k][0] = 0x7               # max positive product column
            b[t][k][1] = 0xF               # max negative product column
            b[t][k][2] = 0x0               # zero column
        b[t][3][0] = 0x8                   # negative zero
        for code in range(16):             # every E2M1 code appears in B
            b[t][4][code] = code

    # E8M0 shared block scales: one exponent byte per 32-element block.
    a_scale = [[127 + rng.randint(-3, 3) for _ in range(K_BLOCKS)]
               for _ in range(MI)]
    a_scale[0][0], a_scale[0][1] = 120, 134
    b_scale = [[[127 + rng.randint(-3, 3) for _ in range(TI)]
                for _ in range(K_BLOCKS)] for _ in range(8)]
    b_scale[0][0][0], b_scale[0][0][1] = 120, 134

    return {
        "name": "mxfp4_gemm_16x16x256_grid8",
        "kind": "mxfp4_gemm",
        "seed": SEED,
        "grid_x": 8,
        "grid_y": 1,
        "grid_z": 1,
        "wg_size": 32,
        "tile_m": MI,
        "tile_n": TI,
        "tile_k": TI_K,
        "k_blocks": K_BLOCKS,
        "k_total": K_TOTAL,
        "workgroups": 8,
        "mfma_ops": 8 * K_BLOCKS,
        "packing": "e2m1-nibbles-low-first",
        "a": a,
        "b": b,
        "a_scale_e8m0": a_scale,
        "b_scale_e8m0": b_scale,
        "scale_rule": "C_sw = C_hw * 2**(e_a + e_b - 256); x4 removed by the -2",
        "criterion": ("all 2048 int32 C words byte-exact vs reference(); "
                      "STATUS.DONE=1, BUSY=0, ERROR=0, WAVE_DONE=8, IRQ level when enabled"),
    }


# ---------------------------------------------------------------------------
# Case 2 -- full-grid 32-lane vector add, 8 workgroups x 16 words/lane
# ---------------------------------------------------------------------------

def _make_vecadd_case() -> dict:
    rng = random.Random(SEED ^ 0x9E3779B9)
    n = 8 * 32 * 16
    corners = [0x00000000, 0x00000001, 0x7FFFFFFF, 0x80000000,
               0xFFFFFFFF, 0xFFFFFFFE, 0x40000000, 0xC0000000]
    a = [corners[i % len(corners)] if i < 64 else rng.getrandbits(32)
         for i in range(n)]
    b = [corners[(i + 3) % len(corners)] if i < 64 else rng.getrandbits(32)
         for i in range(n)]
    return {
        "name": "vecadd_32lane_grid8_x16",
        "kind": "vecadd",
        "seed": SEED ^ 0x9E3779B9,
        "grid_x": 8,
        "grid_y": 1,
        "grid_z": 1,
        "wg_size": 32,
        "words_per_lane": 16,
        "words_total": n,
        "a": a,
        "b": b,
        "criterion": ("all 4096 int32 results equal (a+b) mod 2**32; "
                      "STATUS.DONE=1, BUSY=0, WAVE_DONE=8, IRQ when enabled"),
    }


# ---------------------------------------------------------------------------
# Reference model (the acceptance oracle)
# ---------------------------------------------------------------------------

def _reference(data: dict) -> dict:
    kind = data.get("kind")
    if kind == "mxfp4_gemm":
        a, b = data["a"], data["b"]
        dec = [decode_e2m1(c) for c in range(16)]
        tiles = []
        for t in range(len(b)):
            bt = b[t]
            tile = [0] * (MI * TI)
            for i in range(MI):
                ai = [dec[c] for c in a[i]]
                for kb in range(data["k_blocks"]):
                    base = kb * TI_K
                    for j in range(TI):
                        s = 0
                        for k in range(TI_K):
                            s += ai[base + k] * dec[bt[base + k][j]]
                        tile[i * TI + j] += s
            tiles.append(tile)
        return {"c_int32": tiles}
    if kind == "vecadd":
        return {"c_int32": [(x + y) & 0xFFFFFFFF
                            for x, y in zip(data["a"], data["b"])]}
    raise ValueError(f"unknown case kind: {kind!r}")


def reference(case: dict) -> dict:
    """Golden output for one acceptance case."""
    return _reference(case)


# ---------------------------------------------------------------------------
# Pinned content hashes (computed from inputs + reference output only)
# ---------------------------------------------------------------------------

def _canonical(data: dict) -> str:
    return json.dumps(data, sort_keys=True, separators=(",", ":"))


def case_sha256(case: dict) -> str:
    """SHA-256 over the case inputs and the reference output (like-for-like)."""
    payload = {"inputs": case, "reference": reference(case)}
    return hashlib.sha256(_canonical(payload).encode("utf-8")).hexdigest()


def content_sha256(name: str = "") -> str:
    """SHA-256 of a named case (default: all cases, in declared order)."""
    if name:
        for case_name, case in cases:
            if case_name == name:
                return case_sha256(case)
        raise KeyError(name)
    h = hashlib.sha256()
    for case_name, case in cases:
        h.update(case_name.encode("utf-8"))
        h.update(case_sha256(case).encode("ascii"))
    return h.hexdigest()


# Pinned at registration time; ``verify()`` recomputes them.  Any edit to the
# data generation or the reference must be accompanied by a new pin (a new
# acceptance round is a new contract).
CONTENT_SHA256 = {
    "mxfp4_gemm_16x16x256_grid8":
        "4f35ea387349b50962603009537763855901abe3d18e5835be3ffe88747ac65a",
    "vecadd_32lane_grid8_x16":
        "38df5a006c073255d6a1fc7b680af4772e0b13182f8c7d6309d34a9b59729461",
    "all":
        "801a42110ced93beeb65cde86b34be5a7d69e96e5b2b0e803d54783ac0d7adb9",
}


def verify() -> dict:
    """Recompute the pinned hashes; return {name: (pinned, actual, ok)}."""
    out = {}
    for name in ("mxfp4_gemm_16x16x256_grid8", "vecadd_32lane_grid8_x16"):
        actual = content_sha256(name)
        out[name] = (CONTENT_SHA256.get(name, ""), actual,
                     CONTENT_SHA256.get(name, "") == actual)
    actual_all = content_sha256()
    out["all"] = (CONTENT_SHA256.get("all", ""), actual_all,
                  CONTENT_SHA256.get("all", "") == actual_all)
    return out


cases = [
    ("mxfp4_gemm_16x16x256_grid8", _make_gemm_case()),
    ("vecadd_32lane_grid8_x16", _make_vecadd_case()),
]

# Single-stimulus convention: the first (mission) case.
stimulus = cases[0][1]
