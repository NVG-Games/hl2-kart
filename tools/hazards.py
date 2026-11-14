"""Track hazards for the circuits: turns TRACK["hazards"] specs written in track
terms (s = metres along the lap, side = -1 left / +1 right, setback = metres past the
road edge, lat = metres from the centre line) into placed entries for
data["hazards"], and gives the circuit what they need: barrier cuts where a train
runs, reserved corridors that keep set dressing out of the way, rails, tunnel
portals and crossing signals. Used by track_gen.py and build_track.py.

Hazards stand on the main loop: the game advises and targets only the karts there, so a
spec names lap metres, never a branch, and no hazard's span may reach into a branch's shared
stretch (fork to fork nose, merge nose to merge, as data["branches"] gives them).

Order in a build: check() on the specs, barrier_cuts() before the geometry, reserve()
before decorate(), resolve() before the glTF is written (it adds rails, portals and signal
props), and lint() on the finished gameplay data (it prints one line per hazard)."""
import math
import zlib

import numpy as np

UP = np.array([0.0, 1.0, 0.0])
NO_GO_START = 60.0           # metres after the start line kept clear
NO_GO_END = 30.0             # ... and before it
RAMP, LANDING = 18.0, 25.0   # kept clear before / after a jump gap
BLOCKING = ("train", "field_gate", "tentacle", "tripmine", "minefield")
# spec keys only the generator reads; every other key passes through to the entry's "p"
COMMON_KEYS = ("type", "s", "side", "setback", "lat")
GEN_KEYS = {
    "train": ("angle", "reach", "clear"),
    "tripmine": ("from", "to", "h"),
    "field_gate": ("lanes", "edge"),
    "houndeyes": ("count",),
    "tentacle": ("out", "depth", "reach"),
    "minefield": ("mines",),
    "apache": ("hover",),
    "strider": ("walk",),
    "controller": ("out", "wide", "h", "rise", "orbit"),
    "bullsquid": ("look",),
}
# spec keys each type must give (a floor turret its side too, a strider that stands still its side and setback)
NEEDS = {"turret": ("s",), "vortigaunt": ("s", "side"), "strider": ("s", "zone"),
         "apache": ("zone", "hover"), "train": ("s",), "tripmine": ("s", "from", "to"), "strike_zone": ("zone",),
         "field_gate": ("s",), "air_strafe": ("zone",), "houndeyes": ("s", "side"), "tentacle": ("s",),
         "minefield": ("mines",), "controller": ("zone", "side"), "bullsquid": ("s", "side", "zone")}


def check(specs):
    """The circuit's specs, refused (ValueError) when one has an unknown type, lacks a key its type
    needs or names a branch ("route" / "branch"): hazards stand on the main loop."""
    for k, spec in enumerate(specs):
        kind = spec.get("type")
        if kind not in NEEDS:
            raise ValueError("hazard %d: unknown type %r" % (k, kind))
        need = NEEDS[kind] + (("side",) if kind == "turret" and spec.get("mount", "floor") == "floor" else ())
        if kind == "strider" and "walk" not in spec:
            need += ("side", "setback")
        if kind == "strider" and "walk" in spec:
            _check_walk(k, spec["walk"])
        miss = [key for key in need if key not in spec]
        if miss:
            raise ValueError("hazard %d (%s) needs %s" % (k, kind, ", ".join(miss)))
        if "route" in spec or "branch" in spec:
            raise ValueError("hazard %d (%s) names a branch: hazards stand on the main loop, where the game "
                             "advises and targets the karts (put it on the lap, clear of the junctions)" % (k, kind))
    return specs


def idx(trk, s):
    return int(round((s % trk.length) / trk.step)) % trk.n


def seed_of(track_id, k):
    return zlib.crc32(("%s:%d" % (track_id, k)).encode()) & 0x7FFFFFFF


def yaw_of(d):
    """Godot yaw that turns a model's +Z onto direction d (same as Ctx.yaw_facing)."""
    return math.atan2(float(d[0]), float(d[2]))


def flat(v):
    v = np.array([v[0], 0.0, v[2]], float)
    return v / max(np.linalg.norm(v), 1e-9)


def lst(v):
    return [round(float(x), 3) for x in v]


def _style(t, i):
    return t.styles[t.style[i]] if hasattr(t, "styles") else {}


def _kind(t, i):
    return _style(t, i).get("kind") or t.kind(i)


def side_point(ctx, i, side, setback):
    """A spot `setback` metres past the road edge on `side`, on whatever floor is there:
    the pavement, the verge, the floor of a hall beside the road, or the ground."""
    t = ctx.trk
    st = _style(t, i)
    kind = _kind(t, i)
    edge = t.pos[i] + t.right[i] * side * t.width[i] / 2
    q = edge + t.flat_right[i] * side * setback
    if kind == "street" and setback <= st.get("walk", 4.0) + 0.3:
        q[1] = edge[1] + st.get("curb_h", 0.16)
    elif kind == "open" and setback <= st.get("verge_w", 4.5):
        drop = st.get("verge_drop", 0.27) + abs(t.right[i][1]) * 1.5
        q[1] = edge[1] - drop * setback / st.get("verge_w", 4.5)
    elif kind == "tunnel" and setback <= st.get("wall_gap", 0.0):
        pit = st.get("pit")
        q[1] = t.pos[i][1] - (pit["depth"] if isinstance(pit, dict) else 0.01)
    elif kind == "bridge" and setback <= 0.0:
        q[1] = edge[1]
    else:
        q[1] = ctx.ground(q[0], q[2])
    return q


def floor_y(ctx, q, near_i):
    """Height of whatever a kart (or a train) would roll on at q: the road, its pavement or
    verge, or the ground. near_i: a sample of the stretch q belongs to."""
    t = ctx.trk
    ids = np.arange(near_i - 12, near_i + 13) % t.n
    d = np.linalg.norm((t.pos[ids] - q)[:, [0, 2]], axis=1)
    i = int(ids[int(d.argmin())])
    lat = float(np.dot(q - t.pos[i], t.flat_right[i]))
    hw = t.width[i] / 2
    g = ctx.ground(q[0], q[2])
    if abs(lat) <= hw:
        return float(t.pos[i][1] + t.right[i][1] * lat)
    beside = side_point(ctx, i, math.copysign(1.0, lat), abs(lat) - hw)
    return float(max(beside[1], g)) if _kind(t, i) in ("street", "open") else g


def clear_spot(ctx, s, side, setback, r=1.8, tries=8):
    """Nudge s along the lap until no prop stands within r metres of the spot."""
    t = ctx.trk
    for k in range(tries):
        for sgn in (1, -1):
            s2 = s + sgn * k * 1.5
            q = side_point(ctx, idx(t, s2), side, setback)
            if all(math.hypot(p["pos"][0] - q[0], p["pos"][2] - q[2]) > r for p in ctx.props):
                return s2
    return s


def entry(ctx, spec, k, s, span, pos=None, yaw=0.0, **p):
    e = {"id": k, "type": spec["type"], "s": round(float(s % ctx.trk.length), 2),
         "span": [round(float(span[0]), 2), round(float(span[1]), 2)],
         "seed": seed_of(ctx.track_id, k), "yaw": round(float(yaw), 4), "p": {}}
    if pos is not None:
        e["pos"] = lst(pos)
    for key, val in p.items():
        if val is not None:
            e["p"][key] = val
    # author tuning (range, cone, period, model...) passes straight through
    skip = COMMON_KEYS + GEN_KEYS.get(spec["type"], ())
    for key, val in spec.items():
        if key not in skip and key not in e["p"]:
            e["p"][key] = val
    return e


# ---------------------------------------------------------------- before geometry / decoration
def barrier_cuts(trk, specs):
    """Samples where no barrier is drawn: a level crossing needs a gap in the fences, and so does
    a strider stepping over the road (its legs would pass through the wall at the back of the
    pavement)."""
    cut = np.zeros(trk.n, bool)
    for spec in specs:
        if spec["type"] == "strider" and "walk" in spec:
            reach = STRIDER_REACH * spec.get("scale", 1.15) / 1.15
            for c in _walk_crossings(trk, spec):
                d = (trk.s - c + trk.length / 2) % trk.length - trk.length / 2
                cut |= np.abs(d) < reach + 3.0
        if spec["type"] != "train":
            continue
        ang = math.radians(spec.get("angle", 90.0))
        half = (spec.get("half_w", 1.8) + 2.5) / max(math.sin(ang), 0.3) + 4.0
        d = (trk.s - spec["s"] + trk.length / 2) % trk.length - trk.length / 2
        cut |= np.abs(d) < half
    return cut


def _walk_crossings(trk, spec):
    """Lap metres where a strider's walk steps over the lap (its "cross" legs, in plan)."""
    def plan(w):
        if "xz" in w:
            return np.array([w["xz"][0], w["xz"][1]], float)
        i = idx(trk, w["s"])
        q = trk.pos[i] + trk.flat_right[i] * w["side"] * (trk.width[i] / 2 + w["setback"])
        return q[[0, 2]]
    out = []
    wps = [_waypoint(w) for w in spec["walk"]]
    for a, b in zip(wps[:-1], wps[1:]):
        if not b.get("cross"):
            continue
        pa, pb = plan(a), plan(b)
        for u in np.linspace(0.0, 1.0, max(2, int(np.linalg.norm(pb - pa)) + 1)):
            q = pa + (pb - pa) * u
            i = int(np.argmin(((trk.pos[:, [0, 2]] - q) ** 2).sum(1)))
            lat = (q[0] - trk.pos[i][0]) * trk.flat_right[i][0] + (q[1] - trk.pos[i][2]) * trk.flat_right[i][2]
            if abs(lat) < trk.width[i] / 2:
                out.append(float(trk.s[i]))
    return out


def reserve(ctx, specs):
    """Corridors kept clear of set dressing (Ctx.add / Ctx.fits ask blocked()): the line a
    train runs on, the ground a creature stands on and a strider's line of fire."""
    if not hasattr(ctx, "reserved"):
        ctx.reserved = []
    t = ctx.trk
    for spec in specs:
        kind = spec["type"]
        if kind == "train":
            a, b, d = train_line(ctx, spec)
            ctx.reserved.append((np.array([a, b]), spec.get("clear", 7.0)))
            # and the tunnel mouths at both ends, wing walls and all
            side = np.cross(UP, d)
            for end, back in ((a, d), (b, -d)):
                ctx.reserved.append((np.array([end - back * 13.0, end]), 7.0))
                ctx.reserved.append((np.array([end - side * 35.0 - back, end + side * 35.0 - back]), 2.5))
        elif kind == "strider" and "walk" in spec:
            # the ground its feet reach along the whole walk, and sight lines from it to the road
            pts, _cross = walk_route(ctx, spec)
            reach = STRIDER_REACH * spec.get("scale", 1.15) / 1.15
            ctx.reserved.append((np.array(pts), reach + 1.0))
            for q in pts[::8]:
                ctx.reserved.append((np.array([q, t.pos[_near_i(t, q)]]), 3.0))
        elif kind == "strider":
            i = idx(t, spec["s"])
            q = side_point(ctx, i, spec["side"], spec["setback"])
            ctx.reserved.append((np.array([q, q]), 8.0 * spec.get("scale", 1.15)))
            ctx.reserved.append((np.array([q, t.pos[i]]), 6.0))
        elif kind == "houndeyes":
            pts = np.array([m[:3] for m in _pack(ctx, spec)])
            ctx.reserved.append((pts, 3.0))
            # the beat each one paces on the verge and its run out to the road's edge
            walks, spots = _pack_paths(ctx, spec)
            for w, q in zip(walks, spots):
                ctx.reserved.append((np.array([w[0], w[-1]]), 1.5))
                ctx.reserved.append((np.array([w[len(w) // 2], q]), 1.5))
        elif kind == "bullsquid":
            q = side_point(ctx, idx(t, spec["s"]), spec["side"], spec.get("setback", 7.0))
            ctx.reserved.append((np.array([q, q]), 3.5 * spec.get("scale", 1.4)))
        elif kind in ("vortigaunt", "turret") and spec.get("mount", "floor") == "floor":
            q = side_point(ctx, idx(t, spec["s"]), spec["side"], spec.get("setback", 1.6))
            ctx.reserved.append((np.array([q, q]), 2.5 * spec.get("scale", 1.0)))


def blocked(ctx, model, q, yaw, scale=1.0):
    """True when a prop placed at q would stand in a reserved hazard corridor."""
    if not getattr(ctx, "reserved", None) or model not in ctx.models:
        return False
    pts = np.array(ctx.footprint(model, q, yaw, step=2.0, scale=scale) + [(q[0], q[2])])
    for poly, half in ctx.reserved:
        P = poly[:, [0, 2]]
        for a, b in zip(P[:-1], P[1:]):
            ab = b - a
            u = np.clip(((pts - a) @ ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0)
            if (np.linalg.norm(pts - (a + u[:, None] * ab), axis=1) < half).any():
                return True
    return False


# ---------------------------------------------------------------- resolvers
def train_line(ctx, spec):
    """Ends a, b of the rail line (a on the left at 90 degrees) and its direction a -> b."""
    t = ctx.trk
    i = idx(t, spec["s"])
    ang = math.radians(spec.get("angle", 90.0))
    d = t.flat_right[i] * math.sin(ang) + flat(t.fwd[i]) * math.cos(ang)
    reach = spec.get("reach", 130.0)
    return t.pos[i] - d * reach, t.pos[i] + d * reach, d


def _train(ctx, spec, k):
    t = ctx.trk
    i = idx(t, spec["s"])
    a, b, d = train_line(ctx, spec)
    reach = spec.get("reach", 130.0)
    ang = math.radians(spec.get("angle", 90.0))
    us = np.arange(0.0, 2 * reach + 0.1, 4.0)
    raw = np.array([floor_y(ctx, a + d * u, i) + 0.02 for u in us])
    # smoothed so the cars do not jolt, but never under the road or the ground
    ys = np.maximum(np.convolve(np.pad(raw, 1, mode="edge"), [0.25, 0.5, 0.25], mode="valid"), raw)
    profile = [[round(float(u), 1), round(float(y), 3)] for u, y in zip(us, ys)]
    # the track itself hugs the floor metre by metre (between the 4 m samples it would dip into verges)
    rails(ctx, a, d, [[u, floor_y(ctx, a + d * u, i) + 0.02] for u in np.arange(0.0, 2 * reach + 0.1, 1.0)])
    portal(ctx, a, d)
    portal(ctx, b, -d)
    sig = "props_trainstation/light_signal001a"
    tall = ctx.models[sig]["aabb_max"][1] - ctx.models[sig]["aabb_min"][1] if sig in ctx.models else 4.9
    lamps = []
    for sgn in (-1, 1):
        # one signal each side of the road before the line, its lamps (on its -Z face) towards
        # the oncoming karts; the lamps flash where the signal could stand
        for setback in (3.5, 5.0, 2.5):
            q = side_point(ctx, idx(t, spec["s"] - 6.0), sgn, setback)
            if ctx.add(sig, q, yaw_of(flat(t.fwd[i])), ground=False, tag="hazard"):
                break
        lamps.append(lst(q + UP * (tall - 0.7) - flat(t.fwd[i]) * 0.3))
    road_half = (t.width[i] / 2 + 6.0) / max(math.sin(ang), 0.3)
    return [entry(ctx, spec, k, spec["s"], (spec["s"] - 14.0, spec["s"] + 14.0), pos=t.pos[i], yaw=yaw_of(d),
                  a=lst(a), b=lst(b), cross=round(reach, 2), road_half=round(road_half, 2), profile=profile,
                  lamps=lamps, stop=[round(spec["s"] - 16.0, 1), round(spec["s"] + 16.0, 1)])]


def rails(ctx, a, d, profile, mat="wood/woodtrack001a", width=2.8):
    """The track along the line, sleepers and both rails (seen from above, cut out between the
    sleepers): a decal over road, verges and ground (no collision), its texels square."""
    side = np.cross(UP, d)
    P = np.array([a + d * u + UP * (y - a[1] + 0.06) for u, y in profile])
    L, R = P - side * width / 2, P + side * width / 2
    v = np.array([u for u, _ in profile]) / width
    n = np.repeat(UP[None], len(P), 0)
    # wound to face up, like its normals (it is drawn from both sides, lit by the side it faces)
    ctx.meshes["decal"].strip(ctx.mats.hl2(mat), R, L, 1.0, 0.0, v, n, n)


def portal_boxes(end, d, g):
    """The blocks of a tunnel mouth at `end` (ground height g) facing back along d:
    [(centre, size, back wall?)]: two piers, wing walls each side, the lintel, a dark back wall."""
    side = np.cross(UP, d)
    c = np.array([end[0], g, end[2]])
    out = []
    for sgn in (-1, 1):
        out.append((c + side * sgn * 4.5 + UP * 4.5 - d * 6.0, [2.0, 9.0, 12.0], False))      # piers
        out.append((c + side * sgn * 22.0 + UP * 4.0 - d * 1.0, [26.0, 8.0, 2.0], False))     # wing walls
    out.append((c + UP * 8.0 - d * 6.0, [11.0, 2.0, 12.0], False))                            # lintel
    out.append((c + UP * 3.5 - d * 12.5, [7.0, 7.0, 1.0], True))
    return out


def portal(ctx, end, d, mat="concrete/concretewall008a"):
    """A tunnel mouth the train comes out of, so it never pops in or out of view."""
    yaw = yaw_of(d)
    for centre, size, back in portal_boxes(end, d, ctx.ground(end[0], end[2])):
        ctx.box(ctx.mats.hl2("metal/citadel_metalwall072a" if back else mat), centre, size, yaw)
        if hasattr(ctx, "block"):
            ctx.block(centre, size, yaw)


def _turret(ctx, spec, k):
    t = ctx.trk
    if spec.get("mount", "floor") == "ceiling":
        s = spec["s"]
        i = idx(t, s)
        q = t.pos[i] + t.flat_right[i] * spec.get("lat", 0.0)
        q[1] = t.pos[i][1] + t.height[i] - 0.25
        face = -flat(t.fwd[i])
    else:
        s = clear_spot(ctx, spec["s"], spec["side"], spec.get("setback", 1.6))
        i = idx(t, s)
        q = side_point(ctx, i, spec["side"], spec.get("setback", 1.6))
        if s != spec["s"]:
            # moved off its reserved spot: the spectators placed after this keep clear of the new one
            ctx.reserved.append((np.array([q, q]), 2.5 * spec.get("scale", 1.0)))
        # back along the road, turned a little towards it: the oncoming karts
        face = flat(-flat(t.fwd[i]) * 0.85 - t.flat_right[i] * spec["side"] * 0.5)
    zone = spec.get("zone", [s - 45.0, s + 4.0])
    return [entry(ctx, spec, k, s, zone, pos=q, yaw=yaw_of(face))]


_vortigaunt = _turret                          # floor-mounted, same placement rules


STRIDER_FEET = ((2.308, 3.043), (-2.148, 2.994), (0.0, -3.848))   # combine_strider foot attachments (x, z)
# plan metres from a walking strider's centre to its farthest foot at scale 1.15 (the feet stand
# 3.9 m out and step up to 1.5 m further): its walk keeps this far off every road but where it
# crosses one, and off every wall
STRIDER_REACH = 5.5
WALK_STEP = 3.0             # metres between the points of a resolved walk


def _waypoint(w):
    """A walk waypoint as a dict: {"s", "side", "setback"} in track terms, or {"xz": [x, z]} a plan
    point (a square, a yard), with "cross": True when the leg that ends at it may step over a road.
    A list [s, side, setback] or [s, side, setback, "cross"] is the short form."""
    if isinstance(w, dict):
        return w
    d = {"s": w[0], "side": w[1], "setback": w[2]}
    if len(w) > 3 and w[3] == "cross":
        d["cross"] = True
    return d


def _check_walk(k, walk):
    if not isinstance(walk, (list, tuple)) or len(walk) < 2:
        raise ValueError("hazard %d (strider): walk needs two waypoints or more" % k)
    for w in walk:
        d = _waypoint(w)
        if "xz" not in d and not all(key in d for key in ("s", "side", "setback")):
            raise ValueError("hazard %d (strider): walk waypoint %r needs s, side and setback (or xz)" % (k, w))


def _near_i(t, q):
    """The lap sample nearest q in plan."""
    return int(np.argmin(((t.pos[:, [0, 2]] - (q[0], q[2])) ** 2).sum(1)))


def _wp_point(ctx, w):
    t = ctx.trk
    if "xz" in w:
        q = np.array([w["xz"][0], 0.0, w["xz"][1]], float)
        q[1] = floor_y(ctx, q, _near_i(t, q))
        return q
    return side_point(ctx, idx(t, w["s"]), w["side"], w["setback"])


def walk_route(ctx, spec):
    """A walking strider's route: points every WALK_STEP metres on whatever floor is there, and for
    each whether it lies on a leg that may cross a road. A leg between two waypoints on the same
    side follows the road's curve, its setback lerped between theirs; any other leg (a crossing, a
    plan point) runs straight."""
    t = ctx.trk
    wps = [_waypoint(w) for w in spec["walk"]]
    pts, cross = [], []
    for a, b in zip(wps[:-1], wps[1:]):
        if "s" in a and "s" in b and a["side"] == b["side"] and not b.get("cross"):
            ds = (b["s"] - a["s"] + t.length / 2) % t.length - t.length / 2
            # as many points as the walk is long out there (a bend's outside is longer than its lap metres)
            qa, qb = _wp_point(ctx, a), _wp_point(ctx, b)
            n = max(1, int(round(max(abs(ds), np.linalg.norm((qb - qa)[[0, 2]])) / WALK_STEP)))
            for j in range(n):
                u = j / n
                pts.append(side_point(ctx, idx(t, a["s"] + ds * u), a["side"], a["setback"] + (b["setback"] - a["setback"]) * u))
                cross.append(False)
        else:
            qa, qb = _wp_point(ctx, a), _wp_point(ctx, b)
            n = max(1, int(round(np.linalg.norm((qb - qa)[[0, 2]]) / WALK_STEP)))
            for j in range(n):
                q = qa + (qb - qa) * j / n
                if j:
                    q[1] = floor_y(ctx, q, _near_i(t, q))
                pts.append(q)
                cross.append(bool(b.get("cross")) and j > 0)
    pts.append(_wp_point(ctx, wps[-1]))
    cross.append(False)
    return pts, cross


def _walk_metres(pts):
    d = np.linalg.norm(np.diff(np.array(pts)[:, [0, 2]], axis=0), axis=1)
    return np.concatenate([[0.0], np.cumsum(d)])


def _road_clearance(ctx, q):
    """Plan metres from q to the edge of the nearest road (the lap or a branch) that runs from a
    little under q's ground to a strider's height over it (a road deep under a bridge, or high
    on a viaduct, does not count); negative on one."""
    roads = getattr(ctx, "roads", None)
    R = roads.pos if roads is not None else ctx.trk.pos
    W = roads.width if roads is not None else ctx.trk.width
    keep = ~roads.hidden if roads is not None and hasattr(roads, "hidden") else np.ones(len(R), bool)
    near = keep & (R[:, 1] > q[1] - 6.0) & (R[:, 1] < q[1] + 14.0)
    if not near.any():
        return 1e9
    return float((np.hypot(R[near, 0] - q[0], R[near, 2] - q[2]) - W[near] / 2).min())


def _strider(ctx, spec, k):
    t = ctx.trk
    extra = {}
    if "walk" in spec:
        # it walks: it starts at the first point, facing the road
        pts, cross = walk_route(ctx, spec)
        q = np.array(pts[0], float)
        i = _near_i(t, q)
        extra["walk"] = [lst(p) for p in pts]
        # the stretches of the walk (metres along it) where it steps over a road, its feet in reach of
        # one: it never halts there
        um = _walk_metres(pts)
        reach = STRIDER_REACH * spec.get("scale", 1.15) / 1.15
        cross = [c and _road_clearance(ctx, q) < reach + 1.0 for c, q in zip(cross, pts)]
        runs, j = [], 0
        while j < len(cross):
            if cross[j]:
                j0 = j
                while j < len(cross) and cross[j]:
                    j += 1
                runs.append([round(float(um[max(j0 - 1, 0)]), 1), round(float(um[min(j, len(um) - 1)]), 1)])
            j += 1
        extra["cross"] = runs
    else:
        i = idx(t, spec["s"])
        q = side_point(ctx, i, spec["side"], spec["setback"])
    yaw = yaw_of(flat(t.pos[i] - q))
    sc = spec.get("scale", 1.15)
    c, s_ = math.cos(yaw), math.sin(yaw)
    # the ground under each foot: the body stands at the middle one, the legs reach the others
    feet = [ctx.ground(q[0] + (x * c + z * s_) * sc, q[2] + (-x * s_ + z * c) * sc) for x, z in STRIDER_FEET]
    if "walk" not in spec:
        q[1] = sorted(feet)[1]
    return [entry(ctx, spec, k, spec["s"], spec["zone"], pos=q, yaw=yaw,
                  feet=[round(float(y - q[1]), 3) for y in feet], **extra)]


def _apache(ctx, spec, k):
    t = ctx.trk
    hover = [lst(t.pos[idx(t, s)] + t.flat_right[idx(t, s)] * lat + UP * h) for s, lat, h in spec["hover"]]
    z = spec["zone"]
    return [entry(ctx, spec, k, (z[0] + z[1]) / 2, z, pos=hover[0], hover=hover)]


def _tripmine(ctx, spec, k):
    t = ctx.trk
    i = idx(t, spec["s"])
    st = _style(t, i)
    hw = t.width[i] / 2
    a_lat = spec["from"] * (hw + st.get("wall_gap", 0.0))       # on the wall
    b_lat = spec["to"] * hw                                       # at the crate stand in the road
    h = spec.get("h", 0.55)
    a = t.pos[i] + t.right[i] * a_lat + t.up[i] * h
    b = t.pos[i] + t.right[i] * b_lat + t.up[i] * h
    stand = t.pos[i] + t.right[i] * (b_lat + math.copysign(0.7, b_lat - a_lat))
    return [entry(ctx, spec, k, spec["s"], (spec["s"] - 6.0, spec["s"] + 6.0), pos=a, yaw=yaw_of(flat(b - a)),
                  a=lst(a), b=lst(b), stand=lst(stand), stand_yaw=round(yaw_of(flat(t.fwd[i])), 4))]


def _strike_zone(ctx, spec, k):
    z = spec["zone"]
    mid = (z[0] + z[1]) / 2
    extra = {"core": lst(spec["core"])} if "core" in spec else {}
    return [entry(ctx, spec, k, mid, z, pos=ctx.trk.pos[idx(ctx.trk, mid)], **extra)]


def _field_gate(ctx, spec, k):
    t = ctx.trk
    i = idx(t, spec["s"])
    n = spec.get("lanes", 3)
    hw = t.width[i] / 2 + spec.get("edge", 0.4)
    posts = [lst(t.pos[i] + t.right[i] * (-hw + 2 * hw * j / n)) for j in range(n + 1)]
    return [entry(ctx, spec, k, spec["s"], (spec["s"] - 8.0, spec["s"] + 4.0), pos=t.pos[i],
                  yaw=yaw_of(flat(t.fwd[i])), posts=posts, fwd=lst(flat(t.fwd[i])))]


def _air_strafe(ctx, spec, k):
    t = ctx.trk
    z = spec["zone"]
    i = idx(t, (z[0] + z[1]) / 2)
    out = 1.0 if t.curv[i] < 0 else -1.0                         # wait over the outside of the bend
    loiter = t.pos[i] + t.flat_right[i] * out * 260.0 + UP * 70.0
    return [entry(ctx, spec, k, (z[0] + z[1]) / 2, z, pos=loiter, loiter=lst(loiter))]


def _pack(ctx, spec):
    """Houndeye pack members [x, y, z, yaw] beside the road, staggered, facing it."""
    t = ctx.trk
    members = []
    n = spec.get("count", 3)
    for m in range(n):
        j = idx(t, spec["s"] + (m - (n - 1) / 2) * 3.5)
        q = side_point(ctx, j, spec["side"], spec.get("setback", 2.5) + (m % 2) * 1.6)
        members.append(lst(q) + [round(yaw_of(flat(t.pos[j] - q)), 4)])
    return members


HOUNDEYE_BEAT = 4.0          # metres each houndeye paces up and down the verge from its spot
HOUNDEYE_EDGE = (0.25, 1.15)  # metres between the road's edge and the nose of one at its spot (front and back row)
# model metres from a houndeye's origin to the front of its body as it stands at its spot turned to the
# road and charges up (its skinned mesh: at scale 1.5 it reached 1.0-1.1 m in front of the origin)
HOUNDEYE_NOSE = 0.78


def _pack_paths(ctx, spec):
    """Each pack member's beat on the verge (points every 2 m, HOUNDEYE_BEAT either way of its spot,
    on whatever floor is there) and the spot at the road's edge it runs out to when a kart comes:
    3 m up the road towards the karts, just past the edge, its body never over the road."""
    t = ctx.trk
    walks, spots = [], []
    n = spec.get("count", 3)
    nose = HOUNDEYE_NOSE * spec.get("scale", 1.5)
    for m in range(n):
        s = spec["s"] + (m - (n - 1) / 2) * 3.5
        setback = spec.get("setback", 2.5) + (m % 2) * 1.6
        walks.append([lst(side_point(ctx, idx(t, s + d), spec["side"], setback))
                      for d in np.arange(-HOUNDEYE_BEAT, HOUNDEYE_BEAT + 0.1, 2.0)])
        spots.append(lst(side_point(ctx, idx(t, s - 3.0), spec["side"], nose + HOUNDEYE_EDGE[m % 2])))
    return walks, spots


def _houndeyes(ctx, spec, k):
    members = _pack(ctx, spec)
    walks, spots = _pack_paths(ctx, spec)
    c = np.mean([m[:3] for m in members], axis=0)
    return [entry(ctx, spec, k, spec["s"], (spec["s"] - 30.0, spec["s"] + 12.0), pos=c,
                  members=members, side=spec["side"], walks=walks, spots=spots)]


def _tentacle(ctx, spec, k):
    t = ctx.trk
    i = idx(t, spec["s"])
    side = spec.get("side", -1)
    hw = t.width[i] / 2
    base = t.pos[i] + t.flat_right[i] * side * (hw + spec.get("out", 4.0)) - UP * spec.get("depth", 24.0)
    far = -side * hw * spec.get("reach", 0.2)                    # the slam ends 20% past the centre
    cover = sorted([side * hw, far])
    return [entry(ctx, spec, k, spec["s"], (spec["s"] - 4.0, spec["s"] + 4.0), pos=base,
                  yaw=yaw_of(-t.flat_right[i] * side), cover=[round(cover[0], 2), round(cover[1], 2)],
                  phase=round((seed_of(ctx.track_id, k) % 1000) / 1000.0 * spec.get("period", 7.0), 2))]


def _minefield(ctx, spec, k):
    t = ctx.trk
    mines = [lst(t.surface(idx(t, s), lat, 0.02)) + [round(float(s), 1), float(lat)] for s, lat in spec["mines"]]
    ss = [m[3] for m in mines]
    return [entry(ctx, spec, k, (min(ss) + max(ss)) / 2, (min(ss) - 10.0, max(ss) + 6.0), pos=mines[0][:3],
                  mines=mines)]


CONTROLLER_STEP = 3.0       # metres between the points of a controller's flight


def _controller(ctx, spec, k):
    """A controller's flight: a closed oval over the void on `side` of the road, along the lap metres
    of `orbit` (its zone less 10 m at each end), `out` metres past the road's edge give or take `wide`
    (forwards on the near side, back on the far one), `h` metres over the road rising and falling by
    `rise`. Points every CONTROLLER_STEP metres; the game flies it round them by the hazard clock."""
    t = ctx.trk
    z = spec["zone"]
    a, b = spec.get("orbit", (z[0] + 10.0, z[1] - 10.0))
    half = ((b - a) % t.length) / 2
    mid = a + half
    out, wide = spec.get("out", 12.0), spec.get("wide", 5.0)
    h, rise = spec.get("h", 11.0), spec.get("rise", 2.0)
    n = max(24, int(round((4 * half + 2 * math.pi * wide) / CONTROLLER_STEP)))
    pts = []
    for j in range(n):
        u = 2 * math.pi * j / n
        i = idx(t, mid + half * math.cos(u))
        q = t.pos[i] + t.flat_right[i] * spec["side"] * (t.width[i] / 2 + out + wide * math.sin(u))
        q[1] = t.pos[i][1] + h + rise * math.sin(2 * u)
        pts.append(lst(q))
    return [entry(ctx, spec, k, mid % t.length, z, pos=pts[0], path=pts)]


def _bullsquid(ctx, spec, k):
    """A bullsquid on the ground `setback` metres past the road's edge (an island's edge), turned to
    the road point `look` metres before it: the karts coming."""
    t = ctx.trk
    setback = spec.get("setback", 7.0)
    s = clear_spot(ctx, spec["s"], spec["side"], setback, r=3.0)
    i = idx(t, s)
    q = side_point(ctx, i, spec["side"], setback)
    if s != spec["s"]:
        # moved off its reserved spot: the spectators placed after this keep clear of the new one
        ctx.reserved.append((np.array([q, q]), 3.5 * spec.get("scale", 1.4)))
    face = t.pos[idx(t, s - spec.get("look", 25.0))] - q
    return [entry(ctx, spec, k, s, spec["zone"], pos=q, yaw=yaw_of(flat(face)))]


RESOLVERS = {"turret": _turret, "vortigaunt": _vortigaunt, "strider": _strider, "apache": _apache,
             "train": _train, "tripmine": _tripmine, "strike_zone": _strike_zone, "field_gate": _field_gate,
             "air_strafe": _air_strafe, "houndeyes": _houndeyes, "tentacle": _tentacle, "minefield": _minefield,
             "controller": _controller, "bullsquid": _bullsquid}


def resolve(ctx, specs):
    out = []
    for spec in specs:
        out += RESOLVERS[spec["type"]](ctx, spec, len(out))
    return out


# ---------------------------------------------------------------- checks
def _overlap(a, b, c, d, L):
    """Two lap ranges [a,b] and [c,d] (metres, may wrap) intersect."""
    def norm(x0, x1):
        return x0 % L, (x1 - x0) % L
    a0, la = norm(a, b)
    c0, lc = norm(c, d)
    return ((c0 - a0) % L) <= la or ((a0 - c0) % L) <= lc


def _s_of(t, p):
    d = np.linalg.norm(t.pos - np.array(p)[None], axis=1)
    i = int(d.argmin())
    return float((t.s[i] + np.dot(np.array(p) - t.pos[i], t.fwd[i])) % t.length)


def _lap_gap(t, s0, s1):
    return abs((s0 - s1 + t.length / 2) % t.length - t.length / 2)


def _branch_roads(ctx):
    """The branches' roads (track_gen's RoadSet after the lap; Highway 17 has none)."""
    roads = getattr(ctx, "roads", None)
    return list(roads.trks[1:]) if roads is not None else []


def _off_road(ctx, p, s, away):
    """Clearance of point p from every road but the lap's stretch within `away` metres (along the
    lap) of s: < 0 means it is on one (another stretch of the lap, a branch)."""
    t = ctx.trk
    far = np.array([_lap_gap(t, si, s) > away for si in t.s])
    d = np.linalg.norm((t.pos - p)[:, [0, 2]], axis=1) - t.width / 2
    best = float(d[far].min()) if far.any() else 1e9
    for b in _branch_roads(ctx):
        db = np.linalg.norm((b.pos - p)[:, [0, 2]], axis=1) - b.width / 2
        best = min(best, float(db[~b.hidden].min()))
    return best


def _lap_crates(ctx, boxes):
    """The item crates on the lap (a branch's own lie nearer its road than the lap)."""
    roads = getattr(ctx, "roads", None)
    if roads is None:
        return boxes
    return [p for p in boxes if roads.route[int(np.argmin(((roads.pos - np.asarray(p[:3], float)) ** 2).sum(1)))] == 0]


def _junction_zones(data):
    """Every branch's shared stretches on the lap in lap metres, as the game reads them
    (data["branches"]): (where, s0, s1) from the fork to its nose and from the merge's nose on."""
    step = data.get("path", {}).get("step", 0.0)
    out = []
    for b in data.get("branches", []):
        out.append(("the fork of " + b["id"], b["fork_s"], b["fork_nose_i"] * step))
        out.append(("the merge of " + b["id"], b["merge_nose_i"] * step, b["merge_s"]))
    return out


def _inside(p, poly):
    """Plan point p (x, z) inside the plan polygon poly (N, 2)."""
    a, b = poly, np.roll(poly, -1, axis=0)
    cross = (a[:, 1] > p[1]) != (b[:, 1] > p[1])
    with np.errstate(divide="ignore", invalid="ignore"):
        x = a[:, 0] + (p[1] - a[:, 1]) * (b[:, 0] - a[:, 0]) / (b[:, 1] - a[:, 1])
    return bool((cross & (p[0] < x)).sum() % 2)


def _parts(e):
    """The points of a placed hazard that stand beside its road, each with the plan clearance it
    needs from another road."""
    p = e["p"]
    if e["type"] in ("turret", "vortigaunt") and p.get("mount", "floor") == "floor":
        return [(e["pos"], 1.0)]
    if e["type"] == "houndeyes":
        # where they stand, the beats they pace and the spots at the road's edge they run out to
        return [(q[:3], 1.0) for q in p["members"] + [w for ws in p.get("walks", []) for w in ws] + p.get("spots", [])]
    if e["type"] == "bullsquid":
        return [(e["pos"], 1.0)]
    if e["type"] == "strider" and "walk" in p:
        # every few metres of its walk but where it crosses a road
        um = _walk_metres(p["walk"])
        return [(q, 5.0) for q, u in list(zip(p["walk"], um))[::2]
                if not any(a <= u <= b for a, b in p.get("cross", []))]
    if e["type"] == "strider":
        return [(e["pos"], 5.0)]
    return []


def _on_branch(ctx, q, clear, names):
    """The other road a point beside the lap stands on: a branch's (within `clear` metres of its
    edge in plan, about q's height) or a junction (ctx.junctions); None for none."""
    q = np.asarray(q, float)
    for r, b in enumerate(_branch_roads(ctx)):
        d = np.hypot(b.pos[:, 0] - q[0], b.pos[:, 2] - q[2]) - b.width / 2
        if ((d < clear) & (np.abs(b.pos[:, 1] - q[1]) < 6.0) & ~b.gap & ~b.hidden).any():
            return "the road of " + (names[r] if r < len(names) else "a branch")
    for poly, lo, hi in getattr(ctx, "junctions", ()):
        if lo - 1.0 < q[1] < hi + 2.5 and _inside(q[[0, 2]], poly):
            return "a junction"
    return None


def _flight_checks(ctx, e):
    """A controller's flight: 6 m in plan clear of the edge of every road (the lap and the branches)
    that runs from 10 m under it to 4 m over it (a road further down passes under it in the open),
    and 5 m over the ground."""
    roads = getattr(ctx, "roads", None)
    R = roads.pos if roads is not None else ctx.trk.pos
    W = roads.width if roads is not None else ctx.trk.width
    keep = ~roads.hidden if roads is not None and hasattr(roads, "hidden") else np.ones(len(R), bool)
    road, ground = (1e9, None), (1e9, None)
    for q in e["p"]["path"]:
        near = keep & (R[:, 1] > q[1] - 10.0) & (R[:, 1] < q[1] + 4.0)
        if near.any():
            d = float((np.hypot(R[near, 0] - q[0], R[near, 2] - q[2]) - W[near] / 2).min())
            road = min(road, (d, tuple(q)))
        g = ctx.ground(q[0], q[2])
        if g is not None:
            ground = min(ground, (q[1] - float(g), tuple(q)))
    msgs = []
    if road[0] < 6.0:
        msgs.append("flies %.1f m from a road's edge at (%.0f, %.0f, %.0f)" % ((road[0],) + road[1]))
    if ground[0] < 5.0:
        msgs.append("flies %.1f m over the ground at (%.0f, %.0f, %.0f)" % ((ground[0],) + ground[1]))
    return msgs


def _walk_checks(ctx, e):
    """A walking strider's route: off every road (lap and branches, from a little under its ground
    to its own height) by its feet's reach but where its spec lets it cross; its legs clear of
    every wall and building the circuit placed (ctx.boxes); no step steeper than a stair."""
    p = e["p"]
    pts = np.array(p["walk"], float)
    um = _walk_metres(pts)
    crossing = np.array([any(a <= u <= b for a, b in p.get("cross", [])) for u in um])
    reach = STRIDER_REACH * p.get("scale", 1.15) / 1.15
    msgs = []
    worst = min(((_road_clearance(ctx, q), u) for q, u, c in zip(pts, um, crossing) if not c), default=(1e9, 0.0))
    if worst[0] < reach:
        msgs.append("walk %.1f m from a road edge at walk m %.0f (its feet reach %.1f; mark a crossing \"cross\")"
                    % (worst[0], worst[1], reach))
    # a leg runs from the body 12 m up out to a foot `reach` metres off: anything over a kerb's
    # height that close stands in its way
    for q, u in zip(pts, um):
        hit = False
        for cen, half, ax, az, y0, y1 in getattr(ctx, "boxes", []):
            if y1 < q[1] + 1.5 or y0 > q[1] + 15.0:
                continue
            v = np.array([q[0], q[2]]) - cen
            if abs(v @ ax) < half[0] + reach - 0.5 and abs(v @ az) < half[1] + reach - 0.5:
                hit = True
                break
        if hit:
            msgs.append("walks into a wall or building at walk m %.0f (%.0f, %.0f)" % (u, q[0], q[2]))
            break
    if len(pts) > 1:
        slope = np.abs(np.diff(pts[:, 1])) / np.maximum(np.diff(um), 0.1)
        if slope.max() > 0.5:
            j = int(slope.argmax())
            msgs.append("steep ground (%.0f%%) at walk m %.0f" % (slope[j] * 100, um[j]))
    return msgs


def _checks(ctx, e, data):
    """Placement problems a still would show: a creature with no floor, a turret in a
    wall, a rail line crossing another part of the circuit, mines on a boost pad..."""
    t = ctx.trk
    p = e["p"]
    msgs = []
    if e["type"] in ("turret", "vortigaunt", "houndeyes", "strider", "bullsquid") and p.get("mount", "floor") == "floor":
        pts = [m[:3] for m in p["members"]] if e["type"] == "houndeyes" else [e["pos"]]
        i = idx(t, e["s"])
        for q in pts:
            if q[1] < t.pos[i][1] - 4.0 and _kind(t, i) != "tunnel":
                msgs.append("no floor (%.1f m under the road)" % (t.pos[i][1] - q[1]))
                break
        st = _style(t, i)
        if _kind(t, i) == "tunnel" and e["type"] != "strider":
            lat = abs(float(np.dot(np.array(pts[0]) - t.pos[i], t.flat_right[i])))
            if lat > t.width[i] / 2 + st.get("wall_gap", 0.0) - 0.5:
                msgs.append("in the wall")
    if e["type"] == "train":
        a, b = np.array(p["a"]), np.array(p["b"])
        worst = min(_off_road(ctx, a + (b - a) * u, e["s"], 30.0) for u in np.linspace(0.0, 1.0, 66))
        if worst < 3.0:
            msgs.append("the line runs %.1f m from another stretch" % worst)
        ys = [y for _, y in p["profile"]]
        slope = max(abs(y1 - y0) / 4.0 for y0, y1 in zip(ys[:-1], ys[1:]))
        if slope > 0.12:
            msgs.append("rails climb %.0f%%" % (slope * 100))
    if e["type"] == "minefield":
        pads = [np.array(b["pos"]) for b in data.get("boost_pads", [])]
        crates = [np.array(c[:3]) for c in data.get("item_boxes", [])]   # [x, y, z] or + the surface's up
        for m in p["mines"]:
            q = np.array(m[:3])
            if any(np.linalg.norm(q - b) < 6.0 for b in pads):
                msgs.append("mine at s %.0f on a boost pad" % m[3])
            if any(np.linalg.norm(q - c) < 8.0 for c in crates):
                msgs.append("mine at s %.0f on a crate row" % m[3])
    if e["type"] == "strider" and "walk" not in p and max(p["feet"]) - min(p["feet"]) > 1.5:
        msgs.append("uneven ground: feet %.1f m apart in height" % (max(p["feet"]) - min(p["feet"])))
    if e["type"] == "strider" and "walk" in p:
        msgs += _walk_checks(ctx, e)
    if e["type"] == "controller":
        msgs += _flight_checks(ctx, e)
    if e["type"] == "bullsquid":
        # its acid lands on the road of its zone: never on a boost pad or a crate row
        z0, z1 = p["zone"]
        for b in data.get("boost_pads", []):
            sb = _s_of(t, b["pos"])
            if _overlap(sb - 4.0, sb + 4.0, z0 - 3.0, z1 + 3.0, t.length):
                msgs.append("acid on the boost pad at s %.0f" % sb)
        for c in sorted({round(_s_of(t, q[:3])) for q in _lap_crates(ctx, data.get("item_boxes", []))}):
            if _overlap(c - 6.0, c + 6.0, z0 - 3.0, z1 + 3.0, t.length):
                msgs.append("acid on the crate row at s %.0f" % c)
    if e["type"] == "tentacle" and "path" in data:
        # the racing line's offset from the centre there (the gameplay path keeps every 3rd sample)
        path = data["path"]
        k = int(round(e["s"] / path["step"])) % len(path["center"])
        lat = float(np.dot(np.array(path["line"][k]) - np.array(path["center"][k]), np.array(path["right"][k])))
        if not p["cover"][0] <= lat <= p["cover"][1]:
            msgs.append("the racing line (%.1f m) passes clear of its slam" % lat)
    if e["type"] == "field_gate" and "path" in data:
        # a post between two lanes on the racing line stops every kart that holds its line
        path = data["path"]
        k = int(round(e["s"] / path["step"])) % len(path["center"])
        c, r = np.array(path["center"][k]), np.array(path["right"][k])
        lat = float(np.dot(np.array(path["line"][k]) - c, r))
        for q in p["posts"][1:-1]:
            gap = abs(float(np.dot(np.array(q) - c, r)) - lat)
            if gap < 2.5:
                msgs.append("a post %.1f m from the racing line" % gap)
    return msgs


def lint(ctx, entries, data, strict=False):
    """Prints one line per hazard (where it sits and what it collides with) and returns the
    entries for data["hazards"]. One whose span reaches into a branch's shared stretch, or that
    stands on a branch's road or in a junction, breaks the game's rules (marked !!): with strict
    that raises."""
    t = ctx.trk
    L = t.length
    crate_s = sorted({round(_s_of(t, p[:3])) for p in _lap_crates(ctx, data.get("item_boxes", []))})
    zones = _junction_zones(data)
    names = [b["id"] for b in data.get("branches", [])]
    if zones:
        print("  hazards keep out of: %s" % ", ".join("%s s %.0f-%.0f" % z for z in zones))
    broken = 0
    for e in entries:
        a, b = e["span"]
        msgs = []
        if _overlap(a, b, 0.0, NO_GO_START, L) or _overlap(a, b, L - NO_GO_END, L, L):
            msgs.append("near the start line")
        for g0, g1 in getattr(t, "gaps", []):
            if _overlap(a, b, t.s[g0] - RAMP, t.s[g1 % t.n] + LANDING, L):
                msgs.append("on a jump")
        if e["type"] in BLOCKING and e["type"] != "minefield" and any(_overlap(a, b, c - 6.0, c + 6.0, L)
                                                                       for c in crate_s):
            msgs.append("on a crate row")
        if any(getattr(t, "mag", np.zeros(t.n))[idx(t, x)] > 0 for x in np.arange(a, b, 4.0)):
            msgs.append("in a tube")
        msgs += _checks(ctx, e, data)
        hard = ["!! at %s (s %.0f-%.0f)" % (w, z0, z1) for w, z0, z1 in zones if _overlap(a, b, z0, z1, L)]
        on = next((o for o in (_on_branch(ctx, q, clear, names) for q, clear in _parts(e)) if o), None)
        if on:
            hard.append("!! stands on " + on)
        broken += bool(hard)
        print("  hazard %-11s s %6.0f-%6.0f  %s" % (e["type"], a, b, ", ".join(hard + msgs) or "ok"))
    if broken and strict:
        raise ValueError("%d hazard(s) in a branch's shared stretch or on its road, see above" % broken)
    return entries


# ---------------------------------------------------------------- Highway 17 (build_track.py)
class H17Ctx:
    """The bits of track_gen.Ctx the hazard resolvers use, over build_track.Track."""
    STYLES = {"city": {"kind": "street", "walk": 6.0, "curb_h": 0.18},
              "coast": {"kind": "open", "verge_w": 4.5, "verge_drop": 0.27},
              "dirt": {"kind": "open", "verge_w": 4.5, "verge_drop": 0.27},
              "canal": {"kind": "trench"}}

    def __init__(self, trk, props, terrain_h, models, track_id="city17_circuit"):
        f = trk.fwd
        fr = np.stack([-f[:, 2], np.zeros(trk.n), f[:, 0]], 1)
        trk.flat_right = fr / np.linalg.norm(fr, axis=1, keepdims=True)
        trk.gaps = [(trk.gap_start, trk.gap_end)] if trk.gap.any() else []
        trk.styles = self.STYLES
        trk.style = trk.theme
        trk.kind = lambda i: self.STYLES[trk.theme[i]]["kind"]
        trk.surface = lambda i, lat, h=0.0: trk.pos[i] + trk.right[i] * lat + trk.up[i] * h
        self.trk, self.props, self.models = trk, props, models
        self.ground = terrain_h
        self.reserved = []
        self.track_id = track_id

    def add(self, model, pos, yaw=0.0, physics=False, scale=1.0, tag=None, ground=True, pitch=0.0):
        if model not in self.models:
            return False
        self.props.append({"model": model, "pos": [float(x) for x in pos], "yaw": float(yaw), "physics": physics,
                           "scale": scale, "tag": tag, "ground": ground, "pitch": float(pitch)})
        return True
