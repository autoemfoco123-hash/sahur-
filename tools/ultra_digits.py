"""The 6 and the 7 that 6-7 ULTRA carries on its scale (its head), as solid 3D numbers.

Takes the outlines of "6" and "7" from fonts/Inter-Medium.ttf, flattens the curves, makes the
strokes a little bolder, triangulates the faces (the hole of the 6 included), extrudes them,
and writes scripts/ultra_digits.gd: for each digit the vertex, normal, uv and index arrays of a
mesh one unit tall (baseline at y = 0, centred on x, the front face towards -Z, readable from
the front), sides smooth where the outline curves and sharp at its corners.

usage: python3 tools/ultra_digits.py
"""
import math
import os

from fontTools.pens.basePen import BasePen
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FONT = os.path.join(ROOT, "fonts", "Inter-Medium.ttf")
OUT = os.path.join(ROOT, "scripts", "ultra_digits.gd")
DEPTH = 0.42         # extrusion, in digit heights
BOLD = 0.022         # outline pushed out by this much (bolder strokes)
SMOOTH_DEG = 40.0    # sides are smooth across corners gentler than this


class FlatPen(BasePen):
    def __init__(self, gs, steps=10):
        super().__init__(gs)
        self.contours = []
        self.cur = []
        self.steps = steps

    def _moveTo(self, p):
        self.cur = [p]

    def _lineTo(self, p):
        self.cur.append(p)

    def _qCurveToOne(self, p1, p2):
        p0 = self.cur[-1]
        for k in range(1, self.steps + 1):
            t = k / self.steps
            a = (1 - t) ** 2
            b = 2 * (1 - t) * t
            c = t * t
            self.cur.append((a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]))

    def _curveToOne(self, p1, p2, p3):
        p0 = self.cur[-1]
        for k in range(1, self.steps + 1):
            t = k / self.steps
            a = (1 - t) ** 3
            b = 3 * (1 - t) ** 2 * t
            c = 3 * (1 - t) * t * t
            d = t ** 3
            self.cur.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))

    def _closePath(self):
        if len(self.cur) > 2:
            self.contours.append(self.cur)
        self.cur = []

    _endPath = _closePath


def area(poly):
    s = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        s += x0 * y1 - x1 * y0
    return s * 0.5


def clean(poly):
    out = []
    for p in poly:
        if not out or math.dist(out[-1], p) > 1e-4:
            out.append(p)
    if len(out) > 1 and math.dist(out[0], out[-1]) < 1e-4:
        out.pop()
    # drop points on a straight line
    res = []
    n = len(out)
    for i in range(n):
        a, b, c = out[i - 1], out[i], out[(i + 1) % n]
        cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(cr) > 1e-7:
            res.append(b)
    return res


def offset(poly, d):
    """Push every vertex out of the filled region (it lies to the left of each edge)."""
    n = len(poly)
    out = []
    for i in range(n):
        a, b, c = poly[i - 1], poly[i], poly[(i + 1) % n]
        e0 = (b[0] - a[0], b[1] - a[1])
        e1 = (c[0] - b[0], c[1] - b[1])
        l0 = math.hypot(*e0) or 1.0
        l1 = math.hypot(*e1) or 1.0
        n0 = (e0[1] / l0, -e0[0] / l0)
        n1 = (e1[1] / l1, -e1[0] / l1)
        m = (n0[0] + n1[0], n0[1] + n1[1])
        ml = math.hypot(*m) or 1.0
        m = (m[0] / ml, m[1] / ml)
        k = 1.0 / max(0.35, m[0] * n0[0] + m[1] * n0[1])
        out.append((b[0] + m[0] * d * k, b[1] + m[1] * d * k))
    return out


def seg_cross(p, q, r, s):
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    d1, d2 = orient(r, s, p), orient(r, s, q)
    d3, d4 = orient(p, q, r), orient(p, q, s)
    return d1 * d2 < 0 and d3 * d4 < 0


def bridge(outer, hole):
    """Join a hole to the outer ring with a two-way cut, giving one simple polygon."""
    hi = max(range(len(hole)), key=lambda i: hole[i][0])
    h = hole[hi]
    best, bd = None, 1e9
    edges = [(outer[i], outer[(i + 1) % len(outer)]) for i in range(len(outer))]
    edges += [(hole[i], hole[(i + 1) % len(hole)]) for i in range(len(hole))]
    for i, o in enumerate(outer):
        d = math.dist(o, h)
        if d >= bd:
            continue
        ok = True
        for a, b in edges:
            if a in (o, h) or b in (o, h):
                continue
            if seg_cross(o, h, a, b):
                ok = False
                break
        if ok:
            best, bd = i, d
    ring = hole[hi:] + hole[:hi + 1]
    return outer[:best + 1] + ring + [outer[best]] + outer[best + 1:]


def ear_clip(poly):
    """Triangles (index triples) of a simple CCW polygon (bridges allowed)."""
    idx = list(range(len(poly)))
    tris = []

    def inside(p, a, b, c):
        def s(p1, p2, p3):
            return (p1[0] - p3[0]) * (p2[1] - p3[1]) - (p2[0] - p3[0]) * (p1[1] - p3[1])
        d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
        neg = d1 < 0 or d2 < 0 or d3 < 0
        pos = d1 > 0 or d2 > 0 or d3 > 0
        return not (neg and pos)

    guard = 0
    while len(idx) > 3 and guard < 100000:
        guard += 1
        n = len(idx)
        found = False
        for k in range(n):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % n]
            a, b, c = poly[i0], poly[i1], poly[i2]
            cr = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            if cr <= 1e-12:
                continue
            ok = True
            for j in idx:
                if j in (i0, i1, i2) or poly[j] in (a, b, c):
                    continue
                if inside(poly[j], a, b, c):
                    ok = False
                    break
            if ok:
                tris.append((i0, i1, i2))
                idx.pop(k)
                found = True
                break
        if not found:
            # degenerate leftovers (a bridge): clip the flattest corner anyway
            tris.append((idx[-1], idx[0], idx[1]))
            idx.pop(0)
    if len(idx) == 3:
        tris.append(tuple(idx))
    return tris


def digit(font, ch):
    gs = font.getGlyphSet()
    name = font.getBestCmap()[ord(ch)]
    pen = FlatPen(gs, 6)
    gs[name].draw(pen)
    cs = [clean(c) for c in pen.contours]
    cs = [c for c in cs if len(c) > 2]
    ys = [p[1] for c in cs for p in c]
    xs = [p[0] for c in cs for p in c]
    h = max(ys) - min(ys)
    cx = (max(xs) + min(xs)) * 0.5
    y0 = min(ys)
    cs = [[((x - cx) / h, (y - y0) / h) for x, y in c] for c in cs]
    cs.sort(key=lambda c: -abs(area(c)))
    outer = cs[0] if area(cs[0]) > 0 else cs[0][::-1]
    holes = [c if area(c) < 0 else c[::-1] for c in cs[1:]]
    outer = offset(outer, BOLD)
    holes = [offset(c, BOLD) for c in holes]
    poly = outer
    for hl in holes:
        poly = bridge(poly, hl)
    tris = ear_clip(poly)
    V, N, UV, I = [], [], [], []

    def add(p, n, uv):
        V.append(p)
        N.append(n)
        UV.append(uv)
        return len(V) - 1

    def tri(a, b, c, nrm):
        pa, pb, pc = V[a], V[b], V[c]
        u = [pb[i] - pa[i] for i in range(3)]
        v = [pc[i] - pa[i] for i in range(3)]
        cr = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
        # Godot: front faces wind clockwise, so the right-hand normal points away from the viewer
        if cr[0] * nrm[0] + cr[1] * nrm[1] + cr[2] * nrm[2] > 0:
            b, c = c, b
        I.extend([a, b, c])

    # x is mirrored: seen from -Z (the front), the number reads left to right
    def P(p, z):
        return (-p[0], p[1], z)

    zf, zb = -DEPTH * 0.5, DEPTH * 0.5
    for face_z, nz in ((zf, -1.0), (zb, 1.0)):
        base = len(V)
        for p in poly:
            add(P(p, face_z), (0.0, 0.0, nz), (p[0] + 0.5, 1.0 - p[1]))
        for a, b, c in tris:
            I_before = len(I)
            tri(base + a, base + b, base + c, (0.0, 0.0, nz))
    # the sides: smooth across gentle corners, sharp at real ones
    for ring in [outer] + holes:
        n = len(ring)
        en = []
        for i in range(n):
            a, b = ring[i], ring[(i + 1) % n]
            dx, dy = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dy) or 1.0
            en.append((dy / ln, -dx / ln))          # out of the filled region
        cos_lim = math.cos(math.radians(SMOOTH_DEG))

        def vnorm(i, e):
            # normal at vertex i for edge e (e is i-1 or i)
            o = i - 1 if e == i else i
            a, b = en[e % n], en[o % n]
            if a[0] * b[0] + a[1] * b[1] > cos_lim:
                m = (a[0] + b[0], a[1] + b[1])
                l = math.hypot(*m) or 1.0
                return (m[0] / l, m[1] / l)
            return a

        u = 0.0
        for i in range(n):
            j = (i + 1) % n
            a, b = ring[i], ring[j]
            na, nb = vnorm(i, i), vnorm(j, i)
            seg = math.dist(a, b)
            v0 = add(P(a, zf), (-na[0], na[1], 0.0), (u, 0.0))
            v1 = add(P(b, zf), (-nb[0], nb[1], 0.0), (u + seg, 0.0))
            v2 = add(P(b, zb), (-nb[0], nb[1], 0.0), (u + seg, DEPTH))
            v3 = add(P(a, zb), (-na[0], na[1], 0.0), (u, DEPTH))
            fn = (-en[i][0], en[i][1], 0.0)
            tri(v0, v1, v2, fn)
            tri(v0, v2, v3, fn)
            u += seg
    return V, N, UV, I


def fmt(vals, k=4):
    return "[" + ", ".join(("%." + str(k) + "f") % x if isinstance(x, float) else str(x) for x in vals) + "]"


def main():
    font = TTFont(FONT)
    lines = [
        "extends Reference",
        "## GENERATED by tools/ultra_digits.py: do not edit. The 6 and the 7 on 6-7 ULTRA's scale,",
        "## solid: one unit tall, baseline at y = 0, centred on x, the front face towards -Z.",
        "## Each: [vertices (x, y, z...), normals, uvs (u, v...), indices].",
        "",
    ]
    for ch in "67":
        V, N, UV, I = digit(font, ch)
        flat = lambda arr: [float(c) for p in arr for c in p]
        lines.append("const D%s = [" % ch)
        lines.append("\t" + fmt(flat(V)) + ",")
        lines.append("\t" + fmt(flat(N), 3) + ",")
        lines.append("\t" + fmt(flat(UV), 3) + ",")
        lines.append("\t" + fmt(I) + ",")
        lines.append("]")
        lines.append("")
        print(ch, "verts", len(V), "tris", len(I) // 3)
    lines += [
        "",
        "## The digit as a mesh, `height` metres tall.",
        "static func mesh(ch: String, height: float, mat: Material) -> ArrayMesh:",
        "\tvar d = D6 if ch == \"6\" else D7",
        "\tvar v = PoolVector3Array()",
        "\tvar n = PoolVector3Array()",
        "\tvar uv = PoolVector2Array()",
        "\tvar k = 0",
        "\twhile k < d[0].size():",
        "\t\tv.append(Vector3(d[0][k], d[0][k + 1], d[0][k + 2]) * height)",
        "\t\tn.append(Vector3(d[1][k], d[1][k + 1], d[1][k + 2]).normalized())",
        "\t\tk += 3",
        "\tk = 0",
        "\twhile k < d[2].size():",
        "\t\tuv.append(Vector2(d[2][k], d[2][k + 1]))",
        "\t\tk += 2",
        "\tvar arr = []",
        "\tarr.resize(Mesh.ARRAY_MAX)",
        "\tarr[Mesh.ARRAY_VERTEX] = v",
        "\tarr[Mesh.ARRAY_NORMAL] = n",
        "\tarr[Mesh.ARRAY_TEX_UV] = uv",
        "\tarr[Mesh.ARRAY_INDEX] = PoolIntArray(d[3])",
        "\tvar am = ArrayMesh.new()",
        "\tam.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)",
        "\tam.surface_set_material(0, mat)",
        "\treturn am",
        "",
    ]
    open(OUT, "w").write("\n".join(lines))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
