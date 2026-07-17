#!/usr/bin/env python3
"""Generate the stylised plank-built base-piece models (glTF).

Authored to be drop-in visual upgrades for the POLY kit panels the
build system started with — SAME bounds, pivots and facing, so grid
math, snapping, collision and the composite scenes stay untouched:

  wall_wood_planks        x[0,3]  y[0,3]     z[0,0.2]   (kit SM_Wall_3x3 frame)
  foundation_wood_planks  x[0,3]  y[0,0.22]  z[-3,0]    (kit SM_Floor_3x3 frame,
                                                         raised into a platform)

Style: low-poly boxes only — individual planks with per-plank colour
jitter (baked as vertex colours: ONE untextured material, one draw
call, zero texture fetches on mobile), small gaps, support beams and
rails, nail-head quads, slight end-wear insets. Deterministic RNG so
regeneration is reproducible.

Run from the repo root:  python3 tools/gen_base_piece_models.py
"""
import json
import os
import random
import struct

OUT_DIR = "assets/base_pieces"


def srgb_to_linear(c):
    return tuple((v / 255.0) ** 2.2 for v in c)


class MeshBuilder:
    def __init__(self):
        self.pos = []
        self.nrm = []
        self.col = []
        self.idx = []

    def quad(self, a, b, c, d, normal, color):
        base = len(self.pos)
        for p in (a, b, c, d):
            self.pos.append(p)
            self.nrm.append(normal)
            self.col.append(color)
        self.idx += [base, base + 1, base + 2, base, base + 2, base + 3]

    def box(self, x0, x1, y0, y1, z0, z1, color):
        q = self.quad
        q((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1), (0, 0, 1), color)    # +Z
        q((x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (0, 0, -1), color)   # -Z
        q((x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (1, 0, 0), color)    # +X
        q((x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0), (-1, 0, 0), color)   # -X
        q((x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0), (0, 1, 0), color)    # +Y
        q((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (0, -1, 0), color)   # -Y

    def write(self, name):
        pos_b = b"".join(struct.pack("<3f", *p) for p in self.pos)
        nrm_b = b"".join(struct.pack("<3f", *n) for n in self.nrm)
        col_b = b"".join(struct.pack("<3f", *c) for c in self.col)
        idx_b = b"".join(struct.pack("<H", i) for i in self.idx)
        if len(idx_b) % 4:
            idx_b += b"\x00\x00"
        blob = pos_b + nrm_b + col_b + idx_b
        open(os.path.join(OUT_DIR, name + ".bin"), "wb").write(blob)

        xs = [p[0] for p in self.pos]
        ys = [p[1] for p in self.pos]
        zs = [p[2] for p in self.pos]
        n_v = len(self.pos)
        gltf = {
            "asset": {"version": "2.0", "generator": "gen_base_piece_models.py"},
            "scene": 0,
            "scenes": [{"nodes": [0]}],
            "nodes": [{"mesh": 0, "name": name}],
            "meshes": [{"name": name, "primitives": [{
                "attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2},
                "indices": 3, "material": 0}]}],
            "materials": [{"name": "planks", "pbrMetallicRoughness": {
                "baseColorFactor": [1, 1, 1, 1],
                "metallicFactor": 0.0, "roughnessFactor": 0.95}}],
            "buffers": [{"uri": name + ".bin", "byteLength": len(blob)}],
            "bufferViews": [
                {"buffer": 0, "byteOffset": 0, "byteLength": len(pos_b)},
                {"buffer": 0, "byteOffset": len(pos_b), "byteLength": len(nrm_b)},
                {"buffer": 0, "byteOffset": len(pos_b) + len(nrm_b), "byteLength": len(col_b)},
                {"buffer": 0, "byteOffset": len(pos_b) + len(nrm_b) + len(col_b),
                 "byteLength": len(idx_b)},
            ],
            "accessors": [
                {"bufferView": 0, "componentType": 5126, "count": n_v, "type": "VEC3",
                 "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
                {"bufferView": 1, "componentType": 5126, "count": n_v, "type": "VEC3"},
                {"bufferView": 2, "componentType": 5126, "count": n_v, "type": "VEC3"},
                {"bufferView": 3, "componentType": 5123, "count": len(self.idx),
                 "type": "SCALAR"},
            ],
        }
        open(os.path.join(OUT_DIR, name + ".gltf"), "w").write(
            json.dumps(gltf, separators=(",", ":")))
        print(f"{name}: {n_v} verts, {len(self.idx)//3} tris, "
              f"bounds x[{min(xs)},{max(xs)}] y[{min(ys)},{max(ys)}] z[{min(zs)},{max(zs)}]")


# Palette (sRGB picks, stored linear). Warm plank browns + darker frame.
PLANK = (169, 116, 74)
PLANK_DARK = (132, 94, 61)
BEAM = (110, 74, 44)
NAIL = (52, 50, 54)


def jitter(rng, color, amount=0.10):
    f = 1.0 + rng.uniform(-amount, amount)
    return tuple(min(v * f, 1.0) for v in srgb_to_linear(color))


def build_wall():
    rng = random.Random(20260717)
    m = MeshBuilder()
    # Frame: bottom/top rails and two vertical beams, full 0.2 depth so
    # they read as supports on BOTH faces without growing the bounds.
    beam_lin = srgb_to_linear(BEAM)
    m.box(0.0, 3.0, 0.0, 0.10, 0.0, 0.2, beam_lin)      # bottom rail
    m.box(0.0, 3.0, 2.90, 3.0, 0.0, 0.2, beam_lin)      # top rail
    m.box(0.05, 0.23, 0.0, 3.0, 0.0, 0.2, beam_lin)     # left beam
    m.box(2.77, 2.95, 0.0, 3.0, 0.0, 0.2, beam_lin)     # right beam

    # 7 horizontal planks between the rails, small gaps, worn ends.
    n, gap = 7, 0.02
    y0, y1 = 0.11, 2.89
    h = (y1 - y0 - gap * (n - 1)) / n
    nail_rows = []
    for i in range(n):
        py0 = y0 + i * (h + gap) + rng.uniform(-0.004, 0.004)
        base = PLANK_DARK if i % 3 == 2 else PLANK
        color = jitter(rng, base)
        x0 = 0.02 + rng.uniform(0.0, 0.035)
        x1 = 2.98 - rng.uniform(0.0, 0.035)
        z_j = rng.uniform(-0.004, 0.004)
        m.box(x0, x1, py0, py0 + h, 0.045 + z_j, 0.155 + z_j, color)
        nail_rows.append(py0 + h / 2.0)

    # Nail heads: tiny front-facing quads where planks meet the beams.
    nail_lin = srgb_to_linear(NAIL)
    s = 0.016
    for py in nail_rows:
        for nx in (0.14, 2.86):
            m.quad((nx - s, py - s, 0.162), (nx + s, py - s, 0.162),
                   (nx + s, py + s, 0.162), (nx - s, py + s, 0.162),
                   (0, 0, 1), nail_lin)
    m.write("wall_wood_planks")


def build_foundation():
    rng = random.Random(20260718)
    m = MeshBuilder()
    beam_lin = srgb_to_linear(BEAM)
    # Perimeter skirt beams + corner posts (posts flush with the deck
    # top, so the walkable surface stays a clean plane).
    m.box(0.0, 3.0, 0.0, 0.17, -0.14, 0.0, beam_lin)      # south
    m.box(0.0, 3.0, 0.0, 0.17, -3.0, -2.86, beam_lin)     # north
    m.box(0.0, 0.14, 0.0, 0.17, -3.0, 0.0, beam_lin)      # west
    m.box(2.86, 3.0, 0.0, 0.17, -3.0, 0.0, beam_lin)      # east
    for cx0, cz0 in ((0.0, -0.2), (2.8, -0.2), (0.0, -3.0), (2.8, -3.0)):
        m.box(cx0, cx0 + 0.2, 0.0, 0.22, cz0, cz0 + 0.2, beam_lin)

    # 8 floorboards running along X, gaps between, a few split boards.
    n, gap = 8, 0.012
    w = (2.96 - gap * (n - 1)) / n
    for i in range(n):
        z1 = -0.02 - i * (w + gap)
        z0 = z1 - w
        base = PLANK_DARK if i % 4 == 3 else PLANK
        color = jitter(rng, base, 0.08)
        x0 = 0.02 + rng.uniform(0.0, 0.02)
        x1 = 2.98 - rng.uniform(0.0, 0.02)
        if i in (1, 4, 6):  # split board: two segments, offset seam
            seam = rng.uniform(0.9, 2.1)
            m.box(x0, seam - 0.008, 0.16, 0.22, z0, z1, color)
            m.box(seam + 0.008, x1, 0.16, 0.22, z0, z1, jitter(rng, base, 0.08))
        else:
            m.box(x0, x1, 0.16, 0.22, z0, z1, color)
    m.write("foundation_wood_planks")


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    build_wall()
    build_foundation()
