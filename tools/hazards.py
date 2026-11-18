"""Track hazards for the circuits: turns TRACK["hazards"] specs written in track
terms (s = metres along the lap, side = -1 left / +1 right, setback = metres past the
road edge, lat = metres from the centre line) into placed entries for
data["hazards"], and gives the circuit what they need: barrier cuts where a train
runs, reserved corridors that keep set dressing out of the way, rails, tunnel
portals and crossing signals. Used by track_gen.py and build_track.py.

Hazards stand on the main loop: the game advises and targets only the karts there, so a
spec names lap metres, never a branch, and no hazard's span may reach into a branch's shared
stretch (fork to fork nose, merge nose to merge, as data["branches"] gives them). An antlion
zone and an antlion guard's zone are the exceptions: their ground can lie beside a branch too, so
each names in "branches" the branches whose karts count, and its zone may then reach over their
shared stretches.

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
    "train": ("angle", "reach", "clear", "portals", "rails", "along", "line", "lead", "deck", "smooth"),
    "tripmine": ("from", "to", "h"),
    "field_gate": ("lanes", "edge"),
    "houndeyes": ("count",),
    "tentacle": ("out", "depth", "reach"),
    "minefield": ("mines",),
    "apache": ("hover",),
    "strider": ("walk",),
    "controller": ("out", "wide", "h", "rise", "orbit"),
    "bullsquid": ("look",),
    "antlion": ("thumper", "band"),
    "crane": ("along",),
    "antlion_guard": ("gate",),  # ("edges" goes through to the entry: the lint checks it there)
    "column": ("deck", "posts"),
}
# spec keys each type must give (a floor turret its side too, a strider that stands still its side and setback)
NEEDS = {"turret": ("s",), "vortigaunt": ("s", "side"), "strider": ("s", "zone"),
         "apache": ("zone", "hover"), "train": ("s",), "tripmine": ("s", "from", "to"), "strike_zone": ("zone",),
         "field_gate": ("s",), "air_strafe": ("zone",), "houndeyes": ("s", "side"), "tentacle": ("s",),
         "minefield": ("mines",), "controller": ("zone", "side"), "bullsquid": ("s", "side", "zone"),
         "antlion": ("zone",), "crane": ("s", "side"), "antlion_guard": ("zone", "side"),
         "column": ("s", "zone", "deck")}


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
        if kind in ("antlion", "antlion_guard") and not isinstance(spec.get("branches", []), (list, tuple)):
            raise ValueError("hazard %d (%s): branches is a list of branch ids" % (k, kind))
        if kind == "column":
            _check_deck(k, spec["deck"])
            for q in spec.get("posts", []):
                if not isinstance(q, dict) or "s" not in q or "zone" not in q:
                    raise ValueError("hazard %d (column): each of posts is {s, zone[, post]}" % k)
        if kind == "train" and spec.get("mode", "level") not in TRAIN_MODES:
            raise ValueError("hazard %d (train): mode is one of %s" % (k, ", ".join(TRAIN_MODES)))
        if kind == "train" and spec.get("mode") == "pass" and "along" not in spec and "line" not in spec:
            raise ValueError("hazard %d (train, pass) needs its line: along [s0, s1, side, setback] or line [[x, y, z], ...]" % k)
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
        # (a train beside or over the road never crosses it: its fences stand)
        if spec["type"] != "train" or spec.get("mode") == "pass":
            continue
        ang = math.radians(spec.get("angle", 90.0))
        if "line" in spec or "along" in spec:
            ang = _cross_geom(trk, spec)[3]
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
        if kind == "train" and (spec.get("mode") == "pass" or "line" in spec or "along" in spec):
            # the whole line beside or over the road (or across it), and the tunnel mouths it asks for
            P = pass_line(t, spec)
            ctx.reserved.append((P, spec.get("clear", 4.5)))
            for end, back in _pass_portals(P, spec):
                side = np.cross(UP, back)
                ctx.reserved.append((np.array([end - back * 13.0, end]), 7.0))
                ctx.reserved.append((np.array([end - side * 35.0 - back, end + side * 35.0 - back]), 2.5))
        elif kind == "train":
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
        elif kind == "antlion":
            # the sand they dig out of and run over beside the zone: a band from `keep` to `band` metres
            # past the road's edge on the zone's sand side(s), so no prop stands where one comes up;
            # and the thumpers' feet
            keep, band = spec.get("keep", ANTLION_KEEP), spec.get("band", ANTLION_BAND)
            z0, z1 = spec["zone"]
            for sg in _sand_sides(spec):
                pts = [side_point(ctx, idx(t, s), sg, (keep + band) / 2)
                       for s in np.arange(z0, z1 + spec.get("tail", ANTLION_TAIL) + 0.1, 6.0)]
                ctx.reserved.append((np.array(pts), (band - keep) / 2))
            for q in _thumper_spots(ctx, spec):
                ctx.reserved.append((np.array([q, q]), 3.5))
        elif kind == "antlion_guard":
            # the verge it stands on, walks home along and charges from (from the road's edge to a few
            # metres past its home), its home and its gate
            z0, z1 = spec["zone"]
            sg = int(math.copysign(1, spec["side"]))
            sb = spec.get("setback", GUARD_SETBACK)
            if sb > 0.0:
                pts = [side_point(ctx, idx(t, s), sg, (0.5 + sb + 3.0) / 2) for s in np.arange(z0, z1 + 0.1, 6.0)]
                ctx.reserved.append((np.array(pts), (sb + 2.5) / 2))
            for q in [_guard_home(ctx, spec)] + ([_guard_gate(ctx, spec)] if spec.get("gate") else []):
                ctx.reserved.append((np.array([q, q]), 3.5 * spec.get("scale", GUARD_SCALE)))
        elif kind == "crane":
            # the tower and the cab turning on top of it, and the path its magnet swings out over the road on
            q, _legs = crane_base(ctx, spec)
            ctx.reserved.append((np.array([q, q]), CRANE_CAB_R * spec.get("scale", 1.0) + 1.0))
            _cab, _rest, tips, _booms = crane_sweep(ctx, spec, q)
            for a in range(0, len(tips), CRANE_SWEEP_N):
                ctx.reserved.append((np.array(tips[a:a + CRANE_SWEEP_N]), 3.0))
        elif kind == "column":
            # the walkway the column marches on (both files and their rifles), and the lines of fire from
            # its post down to the zone's road from COLUMN_CLEAR metres out (the bridge's own supports by
            # the post stay)
            pts, um = column_deck(ctx, spec)
            ctx.reserved.append((np.array(pts), COLUMN_HALF))
            for u, (z0, z1) in column_posts(ctx, spec, pts, um):
                q = _deck_at(pts, um, u)
                for s in np.linspace(z0, z1, 5):
                    r = t.pos[idx(t, s)]
                    d = np.linalg.norm((r - q)[[0, 2]])
                    if d > COLUMN_CLEAR + 2.0:
                        ctx.reserved.append((np.array([q + (r - q) * (COLUMN_CLEAR / d), r]), 1.0))
        elif kind == "seesaw":
            # the deck, its flaps and railings: no set dressing on them or just beside them
            a, b = seesaw_run(t, spec["s"])
            ctx.reserved.append((np.array([t.pos[a], t.pos[b]]), t.width[a] / 2 + 2.5))
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
    if spec.get("mode") == "pass":
        return _train_pass(ctx, spec, k)
    if "line" in spec or "along" in spec:
        return _train_line_cross(ctx, spec, k)
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
    cross = spec.get("mode") == "cross"
    if spec.get("rails", "ballast" if cross else "decal") == "ballast":
        # the wheel line metre by metre: on its ballast bed off the road, flush with the road on it
        um = np.arange(0.0, 2 * reach + 0.1, 1.0)
        ym = np.maximum(np.interp(um, us, ys), [floor_y(ctx, a + d * u, i) + 0.02 for u in um])
        rail_track(ctx, np.array([a + d * u + UP * (y - a[1]) for u, y in zip(um, ym)]))
    elif spec.get("rails", "decal") == "decal":
        # the track itself hugs the floor metre by metre (between the 4 m samples it would dip into verges)
        rails(ctx, a, d, [[u, floor_y(ctx, a + d * u, i) + 0.02] for u in np.arange(0.0, 2 * reach + 0.1, 1.0)])
    if spec.get("portals", True):
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
    stop = [round(spec["s"] - 16.0, 1), round(spec["s"] + 16.0, 1)]
    more = {}
    if cross:
        # the arms before the line, and the bots' stop line 6 m short of them (the game's lap metres
        # drift up to ~4 m from these late in a lap: they still stop before the arms)
        gd, more["gates"] = _gates(ctx, spec, ang)
        stop[0] = round(spec["s"] - gd - 6.0, 1)
    return [entry(ctx, spec, k, spec["s"], (spec["s"] - 14.0, spec["s"] + 14.0), pos=t.pos[i], yaw=yaw_of(d),
                  a=lst(a), b=lst(b), cross=round(reach, 2), road_half=round(road_half, 2), profile=profile,
                  lamps=lamps, stop=stop, **more)]


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


# ---------------------------------------------------------------- trains of the forest (D6)
# A train entry's "mode": "level" (none given: the CT17 Combine train across the road), "cross" (a
# fair level crossing: barrier arms, a short fast train, long open gaps) or "pass" (a line beside
# or over the road, never across it: scenery the karts race). scripts/hazards/train_hazard.gd.
TRAIN_MODES = ("level", "cross", "pass")
PASS_STEP = 4.0       # metres between the points of a resolved "pass" line (data p["line"])
PASS_LEAD = 60.0      # metres an "along" line runs on straight past each end of its stretch
GATE_SETBACK = 0.5    # metres past the road's edge a crossing arm's post stands
GATE_POST_H = 1.3     # the post's height (the arm's hinge 0.2 m under its top)
GATE_MOVE = 1.5       # seconds an arm takes to come down or go up (TrainHazard.GATE_MOVE)
RAIL_GAUGE = 1.344    # metres between the rails: where woodtrack001a draws them (u 0.26 and 0.74 of its 2.8 m)
RAIL_H = 0.16         # a rail's height over the sleepers
RAIL_W = 0.07         # a rail head's width
TIE_W = 2.8           # the sleepers' length across (the woodtrack texture's width)
BED_TOP = 1.75        # half width of the ballast bed's top
EP2_CROSS = ["props_trainstation/train_engine", "props_trainstation/train_boxcar", "props_trainstation/train_orecar",
             "props_trainstation/train_boxcar_damaged"]
EP2_PASS = ["props_trainstation/train_engine", "props_trainstation/train_boxcar", "props_trainstation/train_orecar",
            "props_trainstation/train_orecar", "props_trainstation/train003", "props_trainstation/train_boxcar",
            "props_trainstation/train_orecar"]
# the runtime's defaults per mode (TrainHazard.defaults()), for the lint's timetable report
TRAIN_DEFAULTS = {
    "level": {"speed": 28.0, "period": 26.0, "warn": 4.5, "gap": 0.8, "jitter": 0.0,
              "cars": ["props_combine/combinetrain01a", "props_combine/combine_train02a", "props_combine/combine_train02b"],
              "car_axis": ["-x", "z", "z"]},
    "cross": {"speed": 30.0, "period": 55.0, "warn": 6.0, "gap": 0.4, "jitter": 12.0, "gate_lead": 3.0,
              "gate_after": 0.5, "guard": True, "cars": EP2_CROSS, "car_axis": ["z"] * 4},
    "pass": {"speed": 25.0, "period": 70.0, "gap": 0.4, "jitter": 0.0, "cars": EP2_PASS, "car_axis": ["z"] * 7},
}
# metres of train TrainHazard's timetable allows for when it cuts a run's jitter (its CONSIST_MAX)
TRAIN_CONSIST_MAX = 80.0
# the end of a car model that is its front, where it is not its long axis' + end (lay_consist):
# the EP2 locomotive's cab stands near its +z end, the Combine engine's nose is at its -x end
CAR_FRONT = {"props_trainstation/train_engine": "z", "props_trainstation/diesel": "x",
             "props_combine/combinetrain01a": "-x"}


def _smooth01(e0, e1, x):
    t = np.clip((np.asarray(x, float) - e0) / np.maximum(np.asarray(e1, float) - e0, 1e-9), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _runs(mask):
    """Contiguous True runs of a boolean array: [(start, end exclusive)]."""
    out, i, n = [], 0, len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j < n and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def _resample(P, step):
    """Points every `step` metres (or a little less) along the polyline P, both its ends kept."""
    P = np.asarray(P, float)
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    us = np.linspace(0.0, cum[-1], max(int(math.ceil(cum[-1] / step)), 1) + 1)
    return np.stack([np.interp(us, cum, P[:, c]) for c in range(3)], 1)


def _smooth_line(P, sigma, step):
    """A polyline resampled every metre, eased into curves a train can take (a gaussian of `sigma`
    metres along it; past its ends it runs on straight, so they stay put), then resampled every
    `step` metres."""
    P = _resample(P, 1.0)
    if sigma > 0.0 and len(P) > 3:
        r = int(sigma * 3)
        k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
        k /= k.sum()
        pre = P[0] - (P[1] - P[0]) * np.arange(r, 0, -1)[:, None]
        post = P[-1] + (P[-1] - P[-2]) * np.arange(1, r + 1)[:, None]
        Q = np.concatenate([pre, P, post])
        P = np.stack([np.convolve(Q[:, c], k, mode="valid") for c in range(3)], 1)
    return _resample(P, step)


def pass_line(trk, spec, step=PASS_STEP):
    """The wheel line (the rail heads' height) of a train beside or over the road, (k, 3), a point
    every `step` metres: from spec["line"], control points [[x, y, z], ...] eased into curves
    (spec["smooth"]: metres, default 6), or from spec["along"] = [s0, s1, side, setback(, h)]:
    `setback` metres past the lap road's edge on `side` (-1 left, +1 right) from lap metres s0 to
    s1, at the height of the road's edge + h (default 0), run on straight and level for spec["lead"]
    metres (default 60) past both ends (smooth default 8). trk: the lap (ctx.trk, or roads.trks[0]
    in a circuit's terrain build, to carve the ground for it with rail_carve)."""
    if "line" in spec:
        return _smooth_line(spec["line"], spec.get("smooth", 6.0), step)
    al = spec["along"]
    s0, s1, side, setback = al[:4]
    h = al[4] if len(al) > 4 else 0.0
    pts = []
    for s in np.arange(s0, s0 + (s1 - s0) % trk.length + 0.01, 2.0):
        i = idx(trk, s)
        edge = trk.pos[i] + trk.right[i] * side * trk.width[i] / 2
        q = trk.pos[i] + trk.flat_right[i] * side * (trk.width[i] / 2 + setback)
        q[1] = edge[1] + h
        pts.append(q)
    P = np.array(pts)
    lead = spec.get("lead", PASS_LEAD)
    if lead > 0.0 and len(P) > 2:
        d0 = flat(P[min(5, len(P) - 1)] - P[0])
        d1 = flat(P[-1] - P[max(len(P) - 6, 0)])
        pre = [P[0] - d0 * u for u in np.arange(lead, 0.0, -2.0)]
        post = [P[-1] + d1 * u for u in np.arange(2.0, lead + 0.01, 2.0)]
        P = np.concatenate([np.array(pre).reshape(-1, 3), P, np.array(post).reshape(-1, 3)])
    return _smooth_line(P, spec.get("smooth", 8.0), step)


def _pass_portals(P, spec):
    """The tunnel mouths a "pass" line asks for (spec["portals"]: true for both ends, or [first end,
    last end]; none by default): [(end point, direction into the line)]."""
    want = spec.get("portals", False)
    want = [want, want] if isinstance(want, bool) else list(want)
    out = []
    if want[0]:
        out.append((P[0], flat(P[1] - P[0])))
    if want[1]:
        out.append((P[-1], flat(P[-2] - P[-1])))
    return out


def _roads_of(ctx):
    """Every road (track_gen's RoadSet; Highway 17's lap alone): positions, half widths, styles."""
    r = getattr(ctx, "roads", None) or ctx.trk
    keep = ~r.hidden if hasattr(r, "hidden") else np.ones(len(r.pos), bool)
    sts = [r.styles[s] for s in r.style] if hasattr(r, "styles") else [{} for _ in r.pos]
    return r.pos[keep], r.width[keep] / 2, [st for st, k in zip(sts, keep) if k]


def _line_vs_roads(ctx, P):
    """Per point of a line: the plan gap to the edge of the nearest road it runs beside (roads more
    than 4 m above or below it left out), and its height over a road it runs over (within 1.5 m of
    that road's edge in plan; nan where none)."""
    R, W, _sts = _roads_of(ctx)
    gap, over = [], []
    for q in np.asarray(P, float):
        d = np.hypot(R[:, 0] - q[0], R[:, 2] - q[2]) - W
        dy = q[1] - R[:, 1]
        level = np.abs(dy) < 4.0
        gap.append(float(d[level].min()) if level.any() else 1e9)
        under = (d < 1.5) & (dy >= 4.0)
        over.append(float(dy[under].min()) if under.any() else float("nan"))
    return np.array(gap), np.array(over)


def _on_road(ctx, P):
    """Which points of a line lie on a road's surface or its verge or pavement (a level crossing):
    within the road's half width, its side's width and a metre and a half in plan, 1.5 m of its height."""
    R, W, sts = _roads_of(ctx)
    side = np.array([st.get("verge_w", 4.5) if st.get("kind") == "open" else
                     (st.get("walk", 4.0) if st.get("kind") == "street" else 0.0) for st in sts])
    out = []
    for q in np.asarray(P, float):
        d = np.hypot(R[:, 0] - q[0], R[:, 2] - q[2]) - W - side
        out.append(bool(((d < 1.5) & (np.abs(q[1] - R[:, 1]) < 1.5)).any()))
    return np.array(out, bool)


def _pass_span(t, P, near=60.0):
    """The lap stretch a line runs beside (its points within `near` metres of the lap road's edge),
    as (s0, s1) with s1 past s0 (it may run past the lap length); None when it runs beside none."""
    ss = []
    for q in np.asarray(P, float)[::2]:
        d = np.hypot(t.pos[:, 0] - q[0], t.pos[:, 2] - q[2]) - t.width / 2
        i = int(d.argmin())
        if d[i] < near:
            ss.append(float(t.s[i]) % t.length)
    if not ss:
        return None
    ss = np.sort(np.array(ss))
    gaps = np.diff(np.concatenate([ss, [ss[0] + t.length]]))
    j = int(gaps.argmax())
    s0, s1 = float(ss[(j + 1) % len(ss)]), float(ss[j])
    return s0, s1 + (t.length if s1 < s0 else 0.0)


def _train_pass(ctx, spec, k):
    """A train on its own line beside the road or over it ("pass"): the line (pass_line) with its
    track (spec["rails"]: "ballast" by default, "decal" or "none" when the circuit lays its own), the
    tunnel mouths and the bridge deck it asks for ("portals", "deck"), the line metres where it runs
    over a road (its wheels heard overhead there) and the lap stretch it runs beside (its span: the
    game wakes it for karts there). Its own group: it never hits, so it never shares a pass's hit."""
    t = ctx.trk
    P = pass_line(t, spec)
    if spec.get("deck"):
        rail_deck(ctx, P)
    kind = spec.get("rails", "ballast")
    if kind != "none":
        rail_track(ctx, pass_line(t, spec, 1.0), bed=kind == "ballast")
    for end, d in _pass_portals(P, spec):
        portal(ctx, end, d)
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    _gap, over = _line_vs_roads(ctx, P)
    runs = [[round(float(cum[a]) - 2.0, 1), round(float(cum[b - 1]) + 2.0, 1)] for a, b in _runs(~np.isnan(over))]
    span = _pass_span(t, P) or (spec["s"] - 20.0, spec["s"] + 20.0)
    m = len(P) // 2
    return [entry(ctx, spec, k, spec["s"], span, pos=P[m], yaw=yaw_of(flat(P[min(m + 1, len(P) - 1)] - P[m - 1])),
                  line=[lst(q) for q in P], over=runs, group=spec.get("group", "train%d" % k))]


def _gates(ctx, spec, ang):
    """A level crossing's barrier arms on the karts' side of the line: a post GATE_SETBACK metres past
    each edge of the road, its arm reaching to the middle. Returns (metres before the line they
    stand, [[x, y, z, yaw, arm length, post height], ...]) for TrainHazard._build_gates."""
    t = ctx.trk
    gd = (spec.get("half_w", 1.8) + 1.5) / max(math.sin(ang), 0.3) + 2.0
    i = idx(t, spec["s"] - gd)
    out = []
    for sgn in (-1, 1):
        q = side_point(ctx, i, sgn, GATE_SETBACK)
        arm = -t.flat_right[i] * sgn
        out.append(lst(q) + [round(math.atan2(-float(arm[2]), float(arm[0])), 4),
                             round(float(t.width[i] / 2 + GATE_SETBACK - 0.15), 2), GATE_POST_H])
    return round(gd, 2), out


def _strip_along(mesh, mat, A, B, U, va, vb, nrm):
    """A quad strip between polylines A and B whose texture runs along them (u = U, v from va on A to
    vb on B): a rail's faces, its steel texture lengthwise. Front: cross(B - A, along)."""
    n = len(A)
    p = np.concatenate([A, B])
    uv = np.concatenate([np.stack([U, np.full(n, va)], 1), np.stack([U, np.full(n, vb)], 1)])
    k = np.arange(n - 1)
    tri = np.stack([k, k + n, k + 1, k + 1, k + n, k + 1 + n], 1).reshape(-1)
    mesh.add(mat, p, np.concatenate([nrm, nrm]), uv, tri)


def _cap(mesh, mat, pts, nrm):
    """A flat polygon (a fan of pts) facing nrm, its texture in metres / 4."""
    pts = np.asarray(pts, float)
    ax = pts[1] - pts[0]
    ax /= max(np.linalg.norm(ax), 1e-9)
    ay = np.cross(nrm, ax)
    uv = [[float(np.dot(q - pts[0], ax)) / 4.0, float(np.dot(q - pts[0], ay)) / 4.0] for q in pts]
    tri = []
    for j in range(1, len(pts) - 1):
        f = [0, j, j + 1]
        if np.dot(np.cross(pts[j] - pts[0], pts[j + 1] - pts[0]), nrm) < 0:
            f = [0, j + 1, j]
        tri += f
    mesh.add(mat, pts, [nrm] * len(pts), uv, tri)


def rail_track(ctx, P, bed=True, flush=None, gravel="nature/gravelfloor002a", ties="wood/woodtrack001a",
               steel="metal/metaltrack001a"):
    """Railway track along the polyline P (k, 3: where the wheels roll, the rail heads' height, a
    point every metre or so): the sleepers (woodtrack001a, cut out between them: a decal, no
    collision), two steel rails on them (no collision) and, with `bed`, a ballast bed under them
    whose shoulders run down to the ground (it collides as rough ground: a kart that ends up on it
    drives over it). Where `flush` is true (a mask per point; default: where P lies on a road, its
    verge or its pavement: a level crossing) only the sleepers are laid, a hair over the road, so
    karts drive over them. A circuit's decorate() can lay sidings with it and park trains on them
    with lay_consist (the same P)."""
    P = np.asarray(P, float)
    if len(P) < 2:
        return
    d = np.gradient(P, axis=0)
    d[:, 1] = 0.0
    d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-9)
    side = np.cross(UP, d)
    v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    flush = _on_road(ctx, P) if flush is None else np.asarray(flush, bool)
    up = np.repeat(UP[None], len(P), 0)
    # the sleepers: on a road a hair over it (like the Combine line's decal), elsewhere on the bed
    S = P + UP * np.where(flush, 0.06, 0.01 - RAIL_H)[:, None]
    # (wound to face up, like its normals)
    ctx.meshes["decal"].strip(ctx.mats.hl2(ties), S + side * TIE_W / 2, S - side * TIE_W / 2, 1.0, 0.0, v / TIE_W, up, up)
    for a, b in _runs(~flush):
        if b - a < 2:
            continue
        Q, sd = P[a:b], side[a:b]
        mat = ctx.mats.hl2(steel)
        U = v[a:b] / 4.0
        for sgn in (-1, 1):
            c = Q + sd * sgn * RAIL_GAUGE / 2
            low = c - UP * RAIL_H
            _strip_along(ctx.meshes["deco"], mat, c + sd * RAIL_W / 2, c - sd * RAIL_W / 2, U, 0.0, 0.15, up[a:b])
            _strip_along(ctx.meshes["deco"], mat, low + sd * RAIL_W / 2, c + sd * RAIL_W / 2, U, 1.0, 0.15, sd)
            _strip_along(ctx.meshes["deco"], mat, c - sd * RAIL_W / 2, low - sd * RAIL_W / 2, U, 0.15, 1.0, -sd)
        if bed:
            _bed(ctx, ctx.mats.hl2(gravel), Q, sd, v[a:b], d[a:b])


def _bed(ctx, mat, Q, sd, v, d):
    """The ballast under a run of track: its top under the sleepers, each shoulder sloping down to a
    little under the ground (a deep fill spreads wider; over a deck it is only a slab), the ends
    closed."""
    top = Q - UP * (RAIL_H + 0.02)
    sides = {}
    for sgn in (-1, 1):
        edge = top + sd * sgn * BED_TOP
        drop = []
        for e, s_ in zip(edge, sd):
            g = ctx.ground(*(e + s_ * sgn * 0.8)[[0, 2]])
            dy = e[1] - g + 0.25 if g is not None else 0.45
            # (more than 3 m over the ground: a bridge's deck carries it)
            drop.append(0.3 if dy > 3.0 else float(np.clip(dy, 0.45, 3.0)))
        drop = np.array(drop)
        out = edge + sd * sgn * (0.5 + 1.2 * drop)[:, None] - UP * drop[:, None]
        sides[sgn] = (edge, out, drop)
    mesh = ctx.meshes["verge"]
    nrm = np.repeat(UP[None], len(Q), 0)
    mesh.strip(mat, sides[1][0], sides[-1][0], 0.0, BED_TOP * 2 / 4.0, v / 4.0, nrm, nrm)
    for sgn in (-1, 1):
        edge, out, drop = sides[sgn]
        w = (0.5 + 1.2 * drop) / 4.0
        n_ = sd * sgn + UP
        n_ /= np.linalg.norm(n_, axis=1, keepdims=True)
        if sgn > 0:
            mesh.strip(mat, out, edge, w, 0.0, v / 4.0, n_, n_)
        else:
            mesh.strip(mat, edge, out, 0.0, w, v / 4.0, n_, n_)
    for j, face in ((0, -d[0]), (-1, d[-1])):
        _cap(mesh, mat, [sides[-1][1][j], sides[-1][0][j], sides[1][0][j], sides[1][1][j]], face)


def rail_deck(ctx, P, high=2.5, slab="concrete/concretewall008a", girder="metal/metalwall021a", pier_every=24.0):
    """A plain railway bridge under a line P (the wheel line) where it runs more than `high` metres
    over the ground: a slab under the sleepers, a girder each side standing a little over the rails,
    and a pier every `pier_every` metres on open ground (never on a road, its verge or its pavement:
    the span carries the line over them). It all collides like a wall and keeps props out."""
    P = np.asarray(P, float)
    if len(P) < 2:
        return
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    on_road = _on_road(ctx, P)
    R, W, _sts = _roads_of(ctx)
    last_pier = -1e9
    for j in range(len(P) - 1):
        a, b = P[j], P[j + 1]
        mid = (a + b) / 2
        g = ctx.ground(mid[0], mid[2])
        if g is None or mid[1] - g < high:
            continue
        f = flat(b - a)
        yaw = yaw_of(f)
        ln = float(np.linalg.norm((b - a)[[0, 2]])) + 0.3
        top = mid[1] - RAIL_H - 0.02
        ctx.box(ctx.mats.hl2(slab), np.array([mid[0], top - 0.45, mid[2]]), [4.4, 0.9, ln], yaw)
        for sgn in (-1, 1):
            c = mid + np.cross(UP, f) * sgn * 2.1
            c[1] = top - 0.9 + 0.75
            ctx.box(ctx.mats.hl2(girder), c, [0.3, 1.5, ln], yaw)
        if cum[j] - last_pier >= pier_every and not on_road[j]:
            clear = (np.hypot(R[:, 0] - a[0], R[:, 2] - a[2]) - W).min()
            ga = ctx.ground(a[0], a[2])
            if clear > 4.0 and ga is not None and a[1] - ga > high:
                bottom, roof = ga - 0.5, a[1] - RAIL_H - 0.02 - 0.9
                ctx.box(ctx.mats.hl2(slab), np.array([a[0], (bottom + roof) / 2, a[2]]), [3.2, roof - bottom, 1.6], yaw)
                last_pier = cum[j]


def _line_at(P, cum, x):
    """The point x metres along polyline P (cum: its metres at each point), straight on past either end."""
    if x <= 0.0:
        return P[0] + (P[1] - P[0]) / max(cum[1], 1e-9) * x
    if x >= cum[-1]:
        return P[-1] + (P[-1] - P[-2]) / max(cum[-1] - cum[-2], 1e-9) * (x - cum[-1])
    return np.array([np.interp(x, cum, P[:, c]) for c in range(3)])


def _car_euler(key, f, lean=0.0, dip=0.0, toward=None):
    """Godot's (pitch, yaw, roll) (rotation order YXZ) that turns a car model so its front axis (key
    "x", "-x", "z" or "-z") runs along the plan direction f, tilted over by `lean` radians toward
    `toward` (a plan direction across it) and its front end dipped by `dip` radians."""
    F = flat(f)
    U = UP.copy()
    if lean and toward is not None:
        U = U * math.cos(lean) + flat(toward) * math.sin(lean)
    if dip:
        F, U = F * math.cos(dip) - U * math.sin(dip), U * math.cos(dip) + F * math.sin(dip)
    if key.endswith("z"):
        Z = F if key == "z" else -F
        X = np.cross(U, Z)
    else:
        X = F if key == "x" else -F
        Z = np.cross(X, U)
    M = np.stack([X, U, Z], 1)   # columns: where the model's x, y and z go
    return math.asin(float(np.clip(-M[1][2], -1.0, 1.0))), math.atan2(M[0][2], M[2][2]), math.atan2(M[1][0], M[1][1])


def lay_consist(ctx, P, cars, start=None, gap=0.6, facing=1, derail=None, tag=None):
    """Parks a train of car props on the rails along the polyline P (k, 3: the wheel line, as
    rail_track lays it, a point every few metres): `cars` are model keys, the first at the front.
    The front car's front end is `start` metres along P (default a metre short of the end it faces);
    the rest trail behind it, `gap` metres apart. facing +1: the train faces P's last end, -1 its
    first. Each car has both its bogies on the line (its body along the chord, so the train stays
    coupled round a bend) and its wheels on the rails. derail = {"car": index (default the last),
    "off": metres sideways off the rails (default 3.0, + is the right of the way the train faces),
    "yaw": radians askew (0.3), "lean": radians it lies over, away from the rails (0.35), "dip":
    radians its front end drops (0.05)} stands that car on the ground beside the line, turned and
    tilted. A model not extracted, or one that would pass through something placed before it, is
    left out (its place kept). Returns the number of cars placed."""
    P = np.asarray(P, float)
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    x = (cum[-1] - 1.0 if facing > 0 else 1.0) if start is None else float(start)
    der = dict(derail) if derail else None
    if der is not None:
        der.setdefault("car", len(cars) - 1)
        der["car"] = der["car"] % len(cars)
    placed = 0
    for j, key in enumerate(cars):
        m = ctx.models.get(key)
        if m is None:
            if hasattr(ctx, "missing"):
                ctx.missing.add(key)
            x -= facing * (16.0 + gap)
            continue
        lo, hi = np.array(m["aabb_min"]), np.array(m["aabb_max"])
        size = hi - lo
        front = CAR_FRONT.get(key, "x" if size[0] > size[2] else "z")
        length = float(size[0] if front.endswith("x") else size[2])
        c = x - facing * length / 2
        x -= facing * (length + gap)
        a, b = _line_at(P, cum, c - 0.4 * length), _line_at(P, cum, c + 0.4 * length)
        f = flat(b - a) * facing
        q = (a + b) / 2
        lean = dip = 0.0
        toward = None
        if der is not None and der["car"] == j:
            right = np.array([-f[2], 0.0, f[0]])
            off = der.get("off", 3.0)
            q = q + right * off
            ang = der.get("yaw", 0.3)
            f = flat(f * math.cos(ang) + right * math.sin(ang))
            lean, dip, toward = der.get("lean", 0.35), der.get("dip", 0.05), right * math.copysign(1.0, off)
            g = ctx.ground(q[0], q[2])
            # on the ground beside the bed, its low side dug in a little
            width = size[2] if front.endswith("x") else size[0]
            q[1] = (g if g is not None else q[1] - 0.6) + 0.25 * width * math.sin(lean)
        pitch, yaw, roll = _car_euler(front, f, lean, dip, toward)
        # its middle (Source models are not all centred on their origin) over the spot
        cy, sy = math.cos(yaw), math.sin(yaw)
        mid = (lo + hi) / 2
        q = q - np.array([mid[0] * cy + mid[2] * sy, 0.0, -mid[0] * sy + mid[2] * cy])
        if ctx.add(key, q, yaw, ground=False, tag=tag, pitch=pitch, roll=roll):
            placed += 1
    return placed


def rail_carve(field, H, P, half=3.5, blend=12.0, keep=2.0):
    """Terrain heights under a rail line (a circuit's terrain build, after its own carve; field is
    track_gen's Field, H its heights, flat or (nz, nx); P the wheel line, e.g. pass_line(roads.trks[0],
    spec)): the ground meets the ballast's foot (0.5 m under the rail heads) within `half` metres of
    the line and blends back to the land over `blend` metres, so the line neither floats nor sinks.
    The roads' own carve wins within their half width + `keep` metres. Returns heights shaped like H."""
    shape = np.shape(H)
    h = np.array(H, float).ravel().copy()
    Q = _resample(np.asarray(P, float), 2.0)
    reach = half + blend
    lo, hi = Q[:, [0, 2]].min(0) - reach, Q[:, [0, 2]].max(0) + reach
    cells = np.where((field.P[:, 0] >= lo[0]) & (field.P[:, 0] <= hi[0]) &
                     (field.P[:, 1] >= lo[1]) & (field.P[:, 1] <= hi[1]))[0]
    for a in range(0, len(cells), 2048):
        c = cells[a:a + 2048]
        d2 = ((field.P[c][:, None, :] - Q[None, :, [0, 2]]) ** 2).sum(-1)
        j = d2.argmin(1)
        dist = np.sqrt(d2[np.arange(len(c)), j])
        w = 1.0 - _smooth01(half, reach, dist)
        if hasattr(field, "dist") and hasattr(field, "half"):
            w = w * _smooth01(field.half[c] + keep, field.half[c] + keep + 3.0, field.dist[c])
        h[c] = h[c] * (1.0 - w) + (Q[j, 1] - 0.5) * w
    return h.reshape(shape)



def _cross_geom(trk, spec):
    """Where a railway (pass_line) crosses the lap road at grade near spec["s"]: (the line, a point
    every PASS_STEP metres; the line metres at the crossing; the line's plan direction there; the angle
    between line and road, radians). A line that does not cross the road there is refused."""
    P = pass_line(trk, spec)
    i = idx(trk, spec["s"])
    c = trk.pos[i]
    best = (1e9, 0, 0.0)
    for j in range(len(P) - 1):
        ab = (P[j + 1] - P[j])[[0, 2]]
        u = float(np.clip(np.dot((c - P[j])[[0, 2]], ab) / max(float(ab @ ab), 1e-9), 0.0, 1.0))
        dd = float(np.linalg.norm((P[j] + (P[j + 1] - P[j]) * u - c)[[0, 2]]))
        if dd < best[0]:
            best = (dd, j, u)
    gap, j, u = best
    if gap > trk.width[i] / 2:
        raise ValueError("train at s %.0f: its line passes %.1f m from the road's middle there, it does not cross it"
                         % (spec["s"], gap))
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    cm = float(cum[j] + (cum[j + 1] - cum[j]) * u)
    d = flat(P[j + 1] - P[j])
    ang = math.acos(min(abs(float(np.dot(d, flat(trk.fwd[i])))), 1.0))
    return P, cm, d, ang


def _train_line_cross(ctx, spec, k):
    """A fair level crossing on a whole railway (a "cross" with "line" or "along"): one train runs the
    line from end to end, crossing the lap road at grade at spec["s"] and running beside or over the
    road elsewhere. The line, its track, tunnel mouths and bridge deck as a "pass" asks ("rails",
    "portals", "deck"); where it crosses (line metres "cross", the road's half width along it), the
    signals, arms and stop line as on a straight crossing; the line metres where it runs over a road."""
    t = ctx.trk
    i = idx(t, spec["s"])
    P, cm, d, ang = _cross_geom(t, spec)
    if spec.get("deck"):
        rail_deck(ctx, P)
    kind = spec.get("rails", "ballast")
    if kind != "none":
        rail_track(ctx, pass_line(t, spec, 1.0), bed=kind == "ballast")
    for end, dd in _pass_portals(P, spec):
        portal(ctx, end, dd)
    sig = "props_trainstation/light_signal001a"
    tall = ctx.models[sig]["aabb_max"][1] - ctx.models[sig]["aabb_min"][1] if sig in ctx.models else 4.9
    lamps = []
    for sgn in (-1, 1):
        for setback in (3.5, 5.0, 2.5):
            q = side_point(ctx, idx(t, spec["s"] - 6.0), sgn, setback)
            if ctx.add(sig, q, yaw_of(flat(t.fwd[i])), ground=False, tag="hazard"):
                break
        lamps.append(lst(q + UP * (tall - 0.7) - flat(t.fwd[i]) * 0.3))
    road_half = (t.width[i] / 2 + 6.0) / max(math.sin(ang), 0.3)
    gd, gates = _gates(ctx, spec, ang)
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    _gap, over = _line_vs_roads(ctx, P)
    runs = [[round(float(cum[a]) - 2.0, 1), round(float(cum[b - 1]) + 2.0, 1)] for a, b in _runs(~np.isnan(over))]
    # (it stands where its line crosses the road's middle, and wakes for the whole stretch its line runs beside)
    at = _line_at(P, cum, cm)
    wake = _pass_span(t, P) or (spec["s"] - 14.0, spec["s"] + 14.0)
    return [entry(ctx, spec, k, spec["s"], (spec["s"] - 14.0, spec["s"] + 14.0), pos=at, yaw=yaw_of(d),
                  a=lst(P[0]), b=lst(P[-1]), cross=round(cm, 2), road_half=round(road_half, 2), lamps=lamps,
                  stop=[round(spec["s"] - gd - 6.0, 1), round(spec["s"] + 16.0, 1)], gates=gates,
                  line=[lst(q) for q in P], over=runs, wake=[round(wake[0], 2), round(wake[1], 2)])]


def _line_cross_checks(ctx, e, data=None):
    """A crossing on a whole railway: away from its crossing the line keeps clear of every road beside
    it and well over one it crosses, its bends and grade are ones a train takes, one run (portal to
    portal) is over before the next begins, and the crossing's own timetable (_cross_checks)."""
    p = e["p"]
    D = dict(TRAIN_DEFAULTS["cross"])
    D.update(p)
    P = np.array(p["line"], float)
    cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    away = np.abs(cum - p["cross"]) > p["road_half"] + 25.0
    msgs = []
    gap, over = _line_vs_roads(ctx, P)
    half = p.get("half_w", 1.8)
    if (gap[away] < half + 1.5).any():
        k = int(np.where(away, gap, 1e9).argmin())
        msgs.append("the line runs %.1f m from a road's edge at line m %.0f (its cars reach %.1f m)" % (gap[k], cum[k], half))
    if not np.isnan(over).all():
        lo = float(np.nanmin(over))
        msgs.append("over a road %.1f m up" % lo)
        if lo < 6.5:
            msgs.append("too low over the road (under 6.5 m)")
    seg = np.diff(P, axis=0)
    flat_len = np.maximum(np.linalg.norm(seg[:, [0, 2]], axis=1), 1e-6)
    if len(seg) and float(np.abs(seg[:, 1] / flat_len).max()) > 0.06:
        msgs.append("rails climb %.0f%%" % (float(np.abs(seg[:, 1] / flat_len).max()) * 100))
    tl = _consist_length(ctx, D["cars"], D["car_axis"], D["gap"])
    run = (float(flat_len.sum()) + tl) / D["speed"]
    msgs.append("line %.0f m, crossing at line m %.0f, a run %.0f s every %.0f s" % (flat_len.sum(), p["cross"], run, D["period"]))
    # the train must come out of its end and run a while before the crossing warns (EASY's longer warning too)
    dirs = {"ab": [True], "ba": [False]}.get(D.get("dirs", "both"), [True, False])
    for fwd in dirs:
        lead = (p["cross"] if fwd else float(flat_len.sum()) - p["cross"]) - p["road_half"]
        if lead < D["speed"] * D["warn"] * 1.25 + 10.0:
            msgs.append("from its %s end the train reaches the road %.0f m out: under the %.0f m its warning needs" % (
                "first" if fwd else "last", lead, D["speed"] * D["warn"] * 1.25 + 10.0))
    # at every difficulty (EASY, NORMAL, HARD periods): TrainHazard._jitter cuts the jitter so the next
    # run never starts before a train of TRAIN_CONSIST_MAX metres has left the line
    for name, sc in (("EASY", 1.25), ("NORMAL", 1.0), ("HARD", 0.85)):
        per = D["period"] * sc
        jit = min(D["jitter"], per * 0.5)
        if jit > 0.0:
            jit = min(jit, max(per - (float(flat_len.sum()) + TRAIN_CONSIST_MAX) / D["speed"] - 2.0, 0.0))
            if jit < min(D["jitter"], per * 0.5):
                msgs.append("%s: its jitter cut to %.1f s (a run takes %.0f s)" % (name, jit, run))
        if per - jit < run + 2.0:
            msgs.append("%s: the next train starts before this one has left (period less jitter under %.0f s)"
                        % (name, run + 2.0))
    return msgs + _cross_checks(ctx, e, data)


def _consist_length(ctx, cars, axes, gap, fallback="props_trainstation/train001"):
    """A train's length from its cars' models (as TrainHazard.build measures it)."""
    total = 0.0
    for j, key in enumerate(cars):
        m = ctx.models.get(key) or ctx.models.get(fallback)
        ax = (axes[j] if j < len(axes) else "z") if key in ctx.models else "z"
        size = np.array(m["aabb_max"]) - np.array(m["aabb_min"]) if m else np.array([3.2, 6.0, 16.0])
        total += float(size[0] if ax.endswith("x") else size[2]) + (gap if j else 0.0)
    return total


def _cross_checks(ctx, e, data=None):
    """A fair level crossing's timetable (NORMAL): how long its arms shut the road per train and the
    shortest open spell between two trains (a pack held at the arms must get across before the next);
    and no boost pad in the 250 m before it (a boosted kart can not stop for the arms)."""
    D = dict(TRAIN_DEFAULTS["cross"])
    D.update(e["p"])
    tl = _consist_length(ctx, D["cars"], D["car_axis"], D["gap"])
    across = (2.0 * D["road_half"] + tl) / D["speed"]
    shut = D["gate_lead"] - GATE_MOVE + across + D["gate_after"]
    gap = D["period"] - min(D["jitter"], D["period"] * 0.5) - (D["gate_lead"] + across + D["gate_after"] + GATE_MOVE)
    msgs = ["a %.0f m train, the road shut %.1f s per train, open %.0f s or more between%s" % (
        tl, shut, gap, "" if D["guard"] else ", no guard (a kart it held may meet the next train next lap)")]
    if shut > 6.5:
        msgs.append("shut too long (over 6.5 s)")
    if gap < 25.0:
        msgs.append("open too short (under 25 s: a pack held at the arms may meet the next train)")
    if D["warn"] - D["gate_lead"] < 2.0:
        msgs.append("the lamps warn only %.1f s before the arms come down" % (D["warn"] - D["gate_lead"]))
    t = ctx.trk
    for b in (data or {}).get("boost_pads", []):
        before = (e["s"] - _s_of(t, b["pos"])) % t.length
        if before < 250.0:
            msgs.append("a boost pad %.0f m before it (a boosted kart can not stop for the arms)" % before)
    return msgs


def _pass_checks(ctx, e):
    """A train beside or over the road: its line keeps clear of every road beside it (its cars' side
    1.5 m or more past the edge) and well over one it crosses, its bends and grade are ones a train
    takes, and one run is over before the next begins."""
    p = e["p"]
    D = dict(TRAIN_DEFAULTS["pass"])
    D.update(p)
    P = np.array(p["line"], float)
    msgs = []
    gap, over = _line_vs_roads(ctx, P)
    half = p.get("half_w", 1.8)
    if gap.min() < half + 1.5:
        k = int(gap.argmin())
        msgs.append("the line runs %.1f m from a road's edge at line m %.0f (its cars reach %.1f m)" % (
            gap[k], k * PASS_STEP, half))
    if not np.isnan(over).all():
        lo = float(np.nanmin(over))
        msgs.append("over a road %.1f m up" % lo)
        if lo < 6.5:
            msgs.append("too low over the road (under 6.5 m)")
    seg = np.diff(P, axis=0)
    flat_len = np.maximum(np.linalg.norm(seg[:, [0, 2]], axis=1), 1e-6)
    grade = float(np.abs(seg[:, 1] / flat_len).max()) if len(seg) else 0.0
    if grade > 0.06:
        msgs.append("rails climb %.0f%%" % (grade * 100))
    h = [math.atan2(float(s_[2]), float(s_[0])) for s_ in seg]
    turn = [abs((b - a + math.pi) % (2 * math.pi) - math.pi) for a, b in zip(h[:-1], h[1:])]
    if turn and max(turn) > 1e-6:
        r = PASS_STEP / max(turn)
        if r < 60.0:
            msgs.append("a bend of %.0f m radius (the cars overhang it)" % r)
    tl = _consist_length(ctx, D["cars"], D["car_axis"], D["gap"])
    length = float(flat_len.sum())
    run = (length + tl) / D["speed"]
    msgs.append("line %.0f m, a %.0f m train runs it in %.0f s every %.0f s" % (length, tl, run, D["period"]))
    if D["period"] < run + 2.0:
        msgs.append("the next train starts before this one has left (period under %.0f s)" % (run + 2.0))
    return msgs


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


ANTLION_KEEP = 2.0          # metres their spots and runs keep off a road's edge (AntlionHazard p["keep"])
ANTLION_BAND = 16.0         # metres past the road's edge the sand they come up out of reaches (kept clear)
ANTLION_TAIL = 30.0         # metres past the zone's end their pounces may still land (its span)
ANTLION_SAND = 0.6          # share of the zone with open sand beside the road below which lint warns


def _sand_sides(spec):
    """The sides of the road an antlion zone has its sand on: its "side", or both for 0."""
    sd = spec.get("side", 0)
    return (int(math.copysign(1, sd)),) if sd else (-1, 1)


def _thumper_spots(ctx, spec):
    """Where an antlion zone's thumpers stand: spec "thumper" is {"s", "side", "setback"} (or a list of
    them), on whatever floor is there."""
    th = spec.get("thumper")
    if not th:
        return []
    out = []
    for w in (th if isinstance(th, (list, tuple)) else [th]):
        out.append(side_point(ctx, idx(ctx.trk, w["s"]), w.get("side", 1), w.get("setback", 6.0)))
    return out


def _antlion(ctx, spec, k):
    """A beach of antlions: lap metres `zone` (and the branches it names in "branches"), its sand on
    `side` (0: both). The game picks every dig-out spot itself from where the kart on the sand is, so
    here only the zone's middle (where its hill ambience plays, out on the sand), its span (the zone
    and the `tail` its pounces can land past it) and the thumpers' places."""
    t = ctx.trk
    z0, z1 = spec["zone"]
    mid = (z0 + z1) / 2
    sd = spec.get("side", 0)
    q = side_point(ctx, idx(t, mid), _sand_sides(spec)[-1], 8.0)
    thumpers = [lst(p) for p in _thumper_spots(ctx, spec)]
    return [entry(ctx, spec, k, mid, (z0, z1 + spec.get("tail", ANTLION_TAIL)), pos=q, side=sd,
                  thumpers=thumpers or None)]


def _sand_weight(ctx, x, z):
    """How much of the terrain's sand layer (vertex colour alpha, the terrain shader's sand) is painted
    at plan point x, z; None where the circuit has no painted terrain."""
    f = getattr(ctx, "field", None)
    col = getattr(f, "col", None) if f is not None else None
    if col is None:
        return None
    i = int(round((x - f.xs[0]) / f.cell))
    j = int(round((z - f.zs[0]) / f.cell))
    if not (0 <= i < f.nx and 0 <= j < f.nz):
        return None
    c = np.asarray(col, float).reshape(f.nz * f.nx, -1)
    if c.shape[1] < 4:
        return None
    a = float(c[j * f.nx + i][3])
    return a / 255.0 if c[:, 3].max() > 1.5 else a


def _sand_checks(ctx, e, data):
    """An antlion zone: open ground beside the road on its sand side(s) (ground near the road's height,
    off every other road) along most of it, painted sand where the terrain is painted; the branches it
    names exist."""
    t = ctx.trk
    p = e["p"]
    keep = p.get("keep", ANTLION_KEEP)
    z0, z1 = p["zone"]
    msgs = []
    names = [b["id"] for b in data.get("branches", [])]
    for b in p.get("branches", []):
        if b not in names:
            msgs.append("names no branch %r" % b)
    best = (0.0, 0, None)
    for sg in _sand_sides(p):
        ok = sand = known = n = 0
        for s in np.arange(z0, z1 + 0.1, 6.0):
            i = idx(t, s)
            edge_y = float(t.pos[i][1])
            for sb in (keep + 2.0, 7.0, 11.0):
                q = side_point(ctx, i, sg, sb)
                n += 1
                g = ctx.ground(q[0], q[2])
                if g is None or abs(float(g) - edge_y) > 4.0 or _off_road(ctx, q, s, 25.0) < keep:
                    continue
                ok += 1
                w = _sand_weight(ctx, q[0], q[2])
                if w is not None:
                    known += 1
                    sand += w >= 0.5
        share = ok / max(n, 1)
        if share > best[0]:
            best = (share, sg, (sand / known) if known else None)
    if best[0] < ANTLION_SAND:
        msgs.append("open ground beside the road at only %.0f%% of the zone" % (best[0] * 100))
    elif best[2] is not None and best[2] < 0.5:
        msgs.append("the ground beside the zone (side %+d) is only %.0f%% painted sand" % (best[1], best[2] * 100))
    return msgs


# the magnet crane (CraneHazard): crane_docks turning on its tower, its magnet swung over the road
CRANE_HINGE = (2.5908, 1.8011)          # the boom's hinge in the cab (x out along the boom, y up)
CRANE_TIP = (17.842, 30.2675, 0.2398)   # the boom head the magnet's cable leaves from (cable_tip)
CRANE_LUFF = (0.70, 1.31)               # the boom's luff range, radians over the level
CRANE_FRAME_H = 12.707                  # the tower's height: the cab turns on its top
CRANE_FRAME_W = 6.4                     # the tower's footprint (its collision box)
CRANE_CAB_R = 7.4                       # plan metres from the pivot to the turning cab's far corner
CRANE_SETBACK = 10.0                    # metres from the road's edge to the pivot when the spec gives none
CRANE_SWEEP_N = 10                      # points per swing in crane_sweep
# the CraneHazard defaults the generator reads (the spec may override any of them)
CRANE_DEFAULTS = {"jitter": 4.0, "carry": 10.0, "radius": 3.0, "lat_max": -1.0, "high": 9.0, "low": 3.9,
                  "rest_turn": 1.75, "rest_luff": 1.2, "rest_h": 11.0, "scale": 1.0, "cycle": 14.0}


def _crane_p(spec):
    return {k: spec.get(k, v) for k, v in CRANE_DEFAULTS.items()}


def _crane_len():
    return math.hypot(CRANE_TIP[0] - CRANE_HINGE[0], CRANE_TIP[1] - CRANE_HINGE[1])


def crane_reach(scale=1.0):
    """Plan metres from the cab's pivot the boom reaches at its highest and at its lowest luff."""
    L = _crane_len()
    return ((CRANE_HINGE[0] + L * math.cos(CRANE_LUFF[1])) * scale,
            (CRANE_HINGE[0] + L * math.cos(CRANE_LUFF[0])) * scale)


def crane_aim(cab, q, scale=1.0):
    """The boom's yaw and luff that hang the magnet over plan point q, as the game swings it
    (CraneHazard.aim; Godot yaw)."""
    dx, dz = q[0] - cab[0], q[2] - cab[2]
    b = CRANE_TIP[2] * scale
    a = math.sqrt(max(dx * dx + dz * dz - b * b, 0.0))
    L = _crane_len()
    c = min(max((a / scale - CRANE_HINGE[0]) / L, math.cos(CRANE_LUFF[1])), math.cos(CRANE_LUFF[0]))
    luff = math.acos(c)
    a = (CRANE_HINGE[0] + L * math.cos(luff)) * scale
    return math.atan2(b, a) - math.atan2(dz, dx), luff


def crane_point(cab, yaw, luff, u=1.0, scale=1.0):
    """The point `u` of the way along the boom from its hinge to its head (1: the head, where the
    magnet hangs from) at yaw and luff (CraneHazard.tip)."""
    L = _crane_len() * u
    x = (CRANE_HINGE[0] + L * math.cos(luff)) * scale
    y = (CRANE_HINGE[1] + L * math.sin(luff)) * scale
    z = CRANE_TIP[2] * scale * u
    c, s_ = math.cos(yaw), math.sin(yaw)
    return np.array([cab[0] + x * c + z * s_, cab[1] + y, cab[2] - x * s_ + z * c])


def _crane_lat(t, s, p):
    """How far off the centre line the magnet comes down at lap metres s: never nearer the road's
    edge than 2.5 m (CraneHazard._lat_max)."""
    room = max(t.width[idx(t, s)] / 2 - 2.5, 0.0)
    return room if p["lat_max"] < 0 else min(p["lat_max"], room)


def _crane_spots(t, spec, p):
    """The extremes of where the magnet comes down (s give or take `jitter`, either edge or the
    middle) and where it lets go (`carry` metres on): (lap metres, lateral) each."""
    s, j, cr = spec["s"], p["jitter"], p["carry"]
    out = []
    for a in (s - j, s, s + j):
        for sg in (-1.0, 0.0, 1.0):
            lat = sg * _crane_lat(t, a, p)
            m = _crane_lat(t, a + cr, p)
            out += [(a, lat), (a + cr, max(-m, min(m, lat)))]
    return out


def crane_base(ctx, spec):
    """A crane's base `setback` metres past the road's edge on `side`, abeam of s + `along` (by default
    halfway to where it lets go: its reach then covers both), on the lowest ground under its tower's
    four legs (none floats), and those legs' grounds."""
    t = ctx.trk
    sc = spec.get("scale", 1.0)
    along = spec.get("along", _crane_p(spec)["carry"] / 2)
    q = side_point(ctx, idx(t, spec["s"] + along), spec["side"], spec.get("setback", CRANE_SETBACK))
    h = CRANE_FRAME_W * sc / 2
    legs = [ctx.ground(q[0] + dx, q[2] + dz) for dx in (-h, h) for dz in (-h, h)]
    legs = [float(g) for g in legs if g is not None]
    if legs:
        q[1] = min(legs + [float(q[1])])
    return q, legs


def crane_sweep(ctx, spec, q):
    """The cab's pivot of a crane based at q, its rest (yaw, luff), and the magnet's swing from its
    rest out to every extreme spot: the boom head's points and the (yaw, luff) at each, CRANE_SWEEP_N
    per swing (the game turns the short way, lerp_angle)."""
    t = ctx.trk
    p = _crane_p(spec)
    sc = p["scale"]
    cab = np.asarray(q, float) + UP * CRANE_FRAME_H * sc
    to = t.pos[idx(t, spec["s"])] - cab
    rest = (math.atan2(-to[2], to[0]) + p["rest_turn"], min(max(p["rest_luff"], CRANE_LUFF[0]), CRANE_LUFF[1]))
    tips, booms = [], []
    for s, lat in _crane_spots(t, spec, p):
        i = idx(t, s)
        yaw, luff = crane_aim(cab, t.pos[i] + t.right[i] * lat, sc)
        dy = (yaw - rest[0] + math.pi) % (2 * math.pi) - math.pi
        for e in np.linspace(0.0, 1.0, CRANE_SWEEP_N):
            ye, le = rest[0] + dy * e, rest[1] + (luff - rest[1]) * e
            tips.append(crane_point(cab, ye, le, 1.0, sc))
            booms.append((ye, le))
    return cab, rest, tips, booms


def _crane(ctx, spec, k):
    """A magnet crane (CraneHazard) on its tower beside the road (crane_base). Its magnet works over
    the road round s: it comes down within `jitter` metres of s and carries a kart it catches `carry`
    metres on; the game swings it by the clock from the cab's pivot over the tower."""
    t = ctx.trk
    p = _crane_p(spec)
    q, legs = crane_base(ctx, spec)
    s = spec["s"]
    j = p["jitter"] + p["radius"] + 6.0
    zone = spec.get("zone", (s - j, s + p["carry"] + j))
    return [entry(ctx, spec, k, s, zone, pos=q, yaw=yaw_of(flat(t.pos[idx(t, s)] - q)),
                  zone=[round(float(z), 2) for z in zone],
                  phase=round((seed_of(ctx.track_id, k) % 1000) / 1000.0 * p["cycle"], 2),
                  legs=[round(g - float(q[1]), 2) for g in legs])]


# the antlion guard (AntlionGuardHazard): Nova Prospekt's boss, beside the road on its own verge
GUARD_SETBACK = 4.0     # metres past the road's edge its home is when the spec gives none
GUARD_SCALE = 1.2       # its size (p["scale"]): 3.7 m tall, 5.5 m long as it charges
GUARD_TAIL = 20.0       # metres past the zone's end a charge may still meet a kart (p["tail"])
GUARD_ZONE_MIN = 60.0   # the shortest zone it has room to come out for a kart in
GUARD_ROOM = 0.7        # share of the zone with open ground on its side below which lint warns
GUARD_DROP = 4.0        # metres below the road's edge the ground past an open edge lies


def _guard_home(ctx, spec):
    """Where an antlion guard stands between charges: `setback` metres past the road's edge on its
    `side` at s (the zone's middle by default), on whatever floor is there; a negative setback puts it
    that far inside the edge, on the road's own surface (a deck wider than its racing line)."""
    t = ctx.trk
    z0, z1 = spec["zone"]
    s = spec.get("s", (z0 + z1) / 2.0)
    i = idx(t, s)
    sg = int(math.copysign(1, spec["side"]))
    sb = spec.get("setback", GUARD_SETBACK)
    if sb < 0.0:
        return np.asarray(t.surface(i, sg * (t.width[i] / 2 + sb)), float)
    return side_point(ctx, i, sg, sb)


def _guard_gate(ctx, spec):
    """Where it comes out the first time with emerge "gate": spec "gate" is {"s", "side", "setback"}."""
    g = spec["gate"]
    return side_point(ctx, idx(ctx.trk, g["s"]), g.get("side", spec["side"]), g.get("setback", 6.0))


def _antlion_guard(ctx, spec, k):
    """An antlion guard on its verge beside zone (lap metres; its "branches" count too): its home, the
    way it faces (the road), its side and its gate. The game picks every charge itself from where the
    karts are; its span is the zone and the tail a charge may still reach past it."""
    t = ctx.trk
    z0, z1 = spec["zone"]
    s = spec.get("s", (z0 + z1) / 2.0)
    q = _guard_home(ctx, spec)
    gate = lst(_guard_gate(ctx, spec)) if spec.get("gate") else None
    face = t.pos[idx(t, s)] - q
    # a home inside the road's edge (a deck): it stands, steps aside and walks home as far inside it
    sb = spec.get("setback", GUARD_SETBACK)
    deck = sb if sb < 0.0 else None
    return [entry(ctx, spec, k, s, (z0, z1 + spec.get("tail", GUARD_TAIL)), pos=q, yaw=yaw_of(flat(face)),
                  zone=[round(float(z0), 2), round(float(z1), 2)], side=int(math.copysign(1, spec["side"])), gate=gate,
                  keep=spec.get("keep", deck), aside=spec.get("aside", deck))]


# ---------------------------------------------------------------- the marching Combine column (D6)
COLUMN_HEADROOM = 4.5   # metres a deck must clear a road it passes over (a kart, a hop, a kart thrown up)
COLUMN_EDGE = 1.0       # plan metres a deck beside a road keeps from its edge
COLUMN_HALF = 1.4       # metres either side of the deck's line the two files and their rifles take
COLUMN_CLEAR = 10.0     # plan metres from the post its lines of fire are kept clear from (reserve)
COLUMN_RANGE = 110.0    # metres from the post a strip may lie (CombineColumnHazard p["range"])
COLUMN_PITCH = 1.5      # metres between its rows (p["pitch"])


def _check_deck(k, deck):
    if not isinstance(deck, (list, tuple)) or len(deck) < 2:
        raise ValueError("hazard %d (column): deck needs two points or more" % k)
    for q in deck:
        ok = (isinstance(q, dict) and "s" in q) or (isinstance(q, (list, tuple)) and len(q) == 3)
        if not ok:
            raise ValueError("hazard %d (column): deck point %r is [x, y, z] or {s, lat, h}" % (k, q))


def _column_point(ctx, q):
    """A deck point in world space: [x, y, z] is one already, {"s", "lat", "h"} is the point `lat` metres
    right of the lap's centre line at s and `h` metres over the road there."""
    if isinstance(q, dict):
        t = ctx.trk
        i = idx(t, q["s"])
        return t.pos[i] + t.right[i] * q.get("lat", 0.0) + UP * q.get("h", 0.0)
    return np.array([float(q[0]), float(q[1]), float(q[2])])


def column_deck(ctx, spec):
    """The deck's points (world) and the metres along it at each."""
    pts = [_column_point(ctx, q) for q in spec["deck"]]
    um = np.concatenate([[0.0], np.cumsum([np.linalg.norm(b - a) for a, b in zip(pts[:-1], pts[1:])])])
    return pts, um


def _deck_at(pts, um, u):
    j = int(np.clip(np.searchsorted(um, u, side="right") - 1, 0, len(pts) - 2))
    f = float(np.clip((u - um[j]) / max(um[j + 1] - um[j], 1e-6), 0.0, 1.0))
    return pts[j] + (pts[j + 1] - pts[j]) * f


def _column_post(ctx, spec, pts, um):
    """Deck metres where the column stands watch: the spec's "post", or where the deck passes nearest
    (in plan) over the lap's centre line at s."""
    if "post" in spec:
        return float(spec["post"])
    t = ctx.trk
    c = t.pos[idx(t, spec["s"])]
    us = np.linspace(0.0, um[-1], max(2, int(um[-1] / 0.25) + 1))
    d = [math.hypot(q[0] - c[0], q[2] - c[2]) for q in (_deck_at(pts, um, u) for u in us)]
    return float(us[int(np.argmin(d))])


def column_posts(ctx, spec, pts, um):
    """Its watch posts in deck order: (deck metres, (zone start, zone end)), the one over the lap at s and its
    zone, then any more in spec["posts"] (where the lap passes under the deck again)."""
    out = [(_column_post(ctx, spec, pts, um), tuple(spec["zone"]))]
    for q in spec.get("posts", []):
        out.append((_column_post(ctx, q, pts, um), tuple(q["zone"])))
    return sorted(out)


def _column(ctx, spec, k):
    """A column of soldiers on a deck over the lap at s: the deck's points in world space and its watch posts
    (where it halts over the road, the deck metres of the column's middle, and the zone it watches from
    there: the strips land in it). Its span covers every zone (they lie on the same lap, in its order)."""
    pts, um = column_deck(ctx, spec)
    posts = column_posts(ctx, spec, pts, um)
    z0, z1 = spec["zone"]
    main = _column_post(ctx, spec, pts, um)
    lo = min(z for _u, (z, _e) in posts)
    hi = max(e for _u, (_z, e) in posts)
    return [entry(ctx, spec, k, spec["s"], (lo, hi), pos=_deck_at(pts, um, main), deck=[lst(q) for q in pts],
                  post=round(main, 2), zone=[round(float(z0), 2), round(float(z1), 2)],
                  posts=[[round(u, 2), round(float(a), 2), round(float(b), 2)] for u, (a, b) in posts])]


def _column_on_road(ctx, e):
    """Where a column's deck stands on a road (the lap or a branch): its files within COLUMN_EDGE metres of
    the road's edge in plan and less than COLUMN_HEADROOM over or under it. Deck metres, [] for none."""
    roads = getattr(ctx, "roads", None)
    R = roads.pos if roads is not None else ctx.trk.pos
    W = roads.width if roads is not None else ctx.trk.width
    keep = ~roads.hidden if roads is not None and hasattr(roads, "hidden") else np.ones(len(R), bool)
    pts = [np.array(q, float) for q in e["p"]["deck"]]
    um = np.concatenate([[0.0], np.cumsum([np.linalg.norm(b - a) for a, b in zip(pts[:-1], pts[1:])])])
    bad = []
    for u in np.arange(0.0, um[-1] + 0.01, 1.0):
        q = _deck_at(pts, um, u)
        near = keep & (np.hypot(R[:, 0] - q[0], R[:, 2] - q[2]) - W / 2 < COLUMN_EDGE + COLUMN_HALF) &             (np.abs(R[:, 1] - q[1]) < COLUMN_HEADROOM)
        if near.any():
            bad.append(round(float(u), 1))
    return bad


def _column_checks(ctx, e, data, entries):
    """A column: its deck long enough for its soldiers, its post over its zone's road and every strip of
    the zone within its range, no boost pad or crate row in the zone, no other hazard's span over it."""
    t = ctx.trk
    p = e["p"]
    msgs = []
    pts = [np.array(q, float) for q in p["deck"]]
    um = np.concatenate([[0.0], np.cumsum([np.linalg.norm(b - a) for a, b in zip(pts[:-1], pts[1:])])])
    rows = (int(p.get("count", 12)) + 1) // 2
    need = (rows - 1) * p.get("pitch", COLUMN_PITCH) + 2.0 + 6.0
    if um[-1] < need:
        msgs.append("deck %.0f m: too short for %d rows to march (needs %.0f m)" % (um[-1], rows, need))
    crates = sorted({round(_s_of(t, q3[:3])) for q3 in _lap_crates(ctx, data.get("item_boxes", []))})
    for u, z0, z1 in p.get("posts") or [[p["post"], p["zone"][0], p["zone"][1]]]:
        q = _deck_at(pts, um, float(u))
        where = "post at deck m %.0f" % u
        road = [t.pos[idx(t, x)] for x in np.arange(z0, z1 + 0.1, 3.0)]
        gun = q + UP * 1.35
        far = max(float(np.linalg.norm(r - gun)) for r in road)
        if far > p.get("range", COLUMN_RANGE):
            msgs.append("%s: zone reaches %.0f m from it (range %.0f)" % (where, far, p.get("range", COLUMN_RANGE)))
        near = min(math.hypot(r[0] - q[0], r[2] - q[2]) for r in road)
        if near > 30.0:
            msgs.append("%s: zone is %.0f m from it in plan (the strips lie under or beside the bridge)" % (where, near))
        low = min(q[1] - r[1] for r in road)
        if low < 2.0:
            msgs.append("%s: only %.1f m over its zone's road (they fire down at it)" % (where, low))
        for b in data.get("boost_pads", []):
            sb = _s_of(t, b["pos"])
            if _overlap(sb - 4.0, sb + 4.0, z0, z1, t.length):
                msgs.append("a strip could land on the boost pad at s %.0f" % sb)
        for c in crates:
            if _overlap(c - 6.0, c + 6.0, z0, z1, t.length):
                msgs.append("a strip could land on the crate row at s %.0f" % c)
        for o in entries:
            if o is not e and _overlap(o["span"][0], o["span"][1], z0, z1, t.length):
                msgs.append("zone s %.0f-%.0f overlaps the %s at s %.0f-%.0f" % (z0, z1, o["type"], o["span"][0], o["span"][1]))
    return msgs


RESOLVERS = {"turret": _turret, "vortigaunt": _vortigaunt, "strider": _strider, "apache": _apache,
             "train": _train, "tripmine": _tripmine, "strike_zone": _strike_zone, "field_gate": _field_gate,
             "air_strafe": _air_strafe, "houndeyes": _houndeyes, "tentacle": _tentacle, "minefield": _minefield,
             "controller": _controller, "bullsquid": _bullsquid, "antlion": _antlion,
             "crane": _crane, "antlion_guard": _antlion_guard, "column": _column}


# ---------------------------------------------------------------- the see-saw bridge
SEESAW_LEN = 49.1           # the span: Episode Two's seesawbridge/bridgemetalnondynamic is 49.08 m long
SEESAW_APRON_MIN = 12.0     # metres of approach flap each end below which the build stops
SEESAW_APRON_LOW = 14.0     # ... and below which the lint warns (shorter flaps bend more sharply)
SEESAW_FLOOR = 12.0         # metres of ravine under the deck the lint asks for (a kart that goes over falls)
SEESAW_TILT = (2.0, 2.0)    # SeesawHazard's default tilts (entry end down, exit end down), degrees


def seesaw_run(t, s):
    """The see-saw stretch round lap metres s: (its first sample, the first sample after it) of the
    style run with "seesaw": True there, whose road the builder leaves out (SeesawHazard builds the
    span and its flaps between the two). ValueError when the road at s is not one."""
    n = t.n
    i = idx(t, s)
    if not _style(t, i).get("seesaw"):
        raise ValueError("seesaw at s %.0f: the road there is not a see-saw stretch (a style with \"seesaw\": True)" % s)
    a, b, k = i, i, 0
    while _style(t, (a - 1) % n).get("seesaw") and k < n:
        a, k = a - 1, k + 1
    while _style(t, (b + 1) % n).get("seesaw") and k < n:
        b, k = b + 1, k + 1
    return a % n, (b + 1) % n


def _seesaw_ids(t, a, b):
    return np.array([(a + j) % t.n for j in range((b - a) % t.n + 1)])


def _seesaw(ctx, spec, k):
    """The span's pivot in the middle of the stretch and its hinges at the stretch's ends (where the
    roads before and after it end): the flaps take what the span leaves of the stretch."""
    t = ctx.trk
    a, b = seesaw_run(t, spec["s"])
    ids = _seesaw_ids(t, a, b)
    if t.gap[ids[:-1]].any() or t.pit[ids[:-1]].any():
        raise ValueError("seesaw at s %.0f: a jump gap or a pit in its stretch" % spec["s"])
    s0 = float(t.s[a])
    G = float((t.s[b] - t.s[a]) % t.length)
    L = float(spec.get("length", SEESAW_LEN))
    apron = (G - L) / 2
    if apron < SEESAW_APRON_MIN:
        raise ValueError("seesaw at s %.0f: the stretch is %.1f m; the %.1f m span and two flaps of %.0f m need %.1f m"
                         % (spec["s"], G, L, SEESAW_APRON_MIN, L + 2 * SEESAW_APRON_MIN))
    pa, pb = t.pos[a], t.pos[b]
    mid = (pa + pb) / 2
    return [entry(ctx, spec, k, s0 + G / 2, (s0 - 20.0, s0 + G + 5.0), pos=mid, yaw=yaw_of(flat(pb - pa)),
                  a=lst(pa), b=lst(pb), width=round(float(t.width[a]), 2), length=L, apron=round(apron, 2),
                  pier=round(float(ctx.ground(mid[0], mid[2])), 2), **{"from": round(s0, 2), "to": round(s0 + G, 2)})]


def _seesaw_checks(ctx, e, data):
    """A stretch the span can tip on: straight, level, unbanked and one width; flaps long enough; a
    ravine deep enough under it; nothing standing on it (a crate row, a boost pad or a prop would float
    or sink as the deck tips)."""
    t = ctx.trk
    p = e["p"]
    msgs = []
    a, b = seesaw_run(t, e["s"])
    ids = _seesaw_ids(t, a, b)
    pa, pb = np.array(p["a"]), np.array(p["b"])
    d = flat(pb - pa)
    side = np.cross(d, UP)
    off = np.abs((t.pos[ids] - pa) @ side).max()
    if off > 0.1:
        msgs.append("not straight: %.2f m off the line between its hinges" % off)
    rise = np.abs(t.pos[ids][:, 1] - (pa[1] + pb[1]) / 2).max()
    if rise > 0.1:
        msgs.append("not level: %.2f m up or down" % rise)
    bank = float(np.abs(t.right[ids][:, 1]).max())
    if bank > 0.01:
        msgs.append("banked %.1f degrees" % math.degrees(math.asin(min(bank, 1.0))))
    w = t.width[ids]
    if w.max() - w.min() > 0.1:
        msgs.append("its width changes (%.1f-%.1f m)" % (w.min(), w.max()))
    if p["apron"] < SEESAW_APRON_LOW:
        msgs.append("flaps %.1f m (at least %.0f m bend gently)" % (p["apron"], SEESAW_APRON_LOW))
    mid = np.array(e["pos"])
    half = p["length"] / 2 + p["apron"]
    tilt = math.radians(max(abs(p.get("back", SEESAW_TILT[0])), abs(p.get("max", SEESAW_TILT[1]))))
    clear = min(mid[1] - ctx.ground(*(mid + d * u + side * lat)[[0, 2]])
                for u in np.arange(-half + 2.0, half - 1.9, 3.0) for lat in (-p["width"] / 2, 0.0, p["width"] / 2))
    want = max(SEESAW_FLOOR, p["length"] / 2 * math.sin(tilt) + 9.0)
    msgs.append("ravine %.1f m under the deck%s" % (clear, " (want %.0f)" % want if clear < want else ""))
    z0, z1 = p["from"], p["to"]
    for c in sorted({round(_s_of(t, q[:3])) for q in _lap_crates(ctx, data.get("item_boxes", []))}):
        if _overlap(c - 3.0, c + 3.0, z0, z1, t.length):
            msgs.append("a crate row on it at s %.0f" % c)
    for pad in data.get("boost_pads", []):
        sb = _s_of(t, pad["pos"])
        if _overlap(sb - 3.0, sb + 3.0, z0, z1, t.length) and abs(np.dot(np.array(pad["pos"]) - mid, side)) < p["width"] / 2 + 1.0:
            msgs.append("a boost pad on it at s %.0f" % sb)
    on = [q["model"] for q in getattr(ctx, "props", [])
          if abs(np.dot(np.array(q["pos"]) - pa, side)) < p["width"] / 2 + 0.5 and -1.0 < np.dot(np.array(q["pos"]) - pa, d)
          < np.linalg.norm((pb - pa)[[0, 2]]) + 1.0 and abs(q["pos"][1] - mid[1]) < 3.0]
    if on:
        msgs.append("props on it: %s" % ", ".join(sorted(set(on))))
    return msgs


NEEDS["seesaw"] = ("s",)
RESOLVERS["seesaw"] = _seesaw


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
        # (a cave has no fork: its road begins underground)
        if b.get("kind") != "cave":
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
    if e["type"] == "crane":
        return [(e["pos"], CRANE_FRAME_W * p.get("scale", 1.0) / 2 + 1.0)]
    if e["type"] == "strider" and "walk" in p:
        # every few metres of its walk but where it crosses a road
        um = _walk_metres(p["walk"])
        return [(q, 5.0) for q, u in list(zip(p["walk"], um))[::2]
                if not any(a <= u <= b for a, b in p.get("cross", []))]
    if e["type"] == "strider":
        return [(e["pos"], 5.0)]
    if e["type"] == "antlion":
        # its thumpers (the antlions themselves keep off every road on their own)
        return [(q, 2.0) for q in p.get("thumpers", [])]
    if e["type"] == "antlion_guard":
        # its home and its gate (it charges onto its road, but stands and walks off every road)
        return [(e["pos"], 3.0)] + ([(p["gate"], 3.0)] if p.get("gate") else [])
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


def _crane_checks(ctx, e):
    """A crane: its tower on even ground clear of every road; its magnet able to reach every spot it
    comes down at or lets go, with nothing over those spots (a deck, a tunnel's roof); its turning cab
    and its boom clear of the ground and of any road up at their height; its magnet over the ground on
    its swing."""
    t = ctx.trk
    p = _crane_p(e["p"])
    sc = p["scale"]
    spec = dict(e["p"], s=e["s"])
    q = np.array(e["pos"], float)
    msgs = []
    legs = e["p"].get("legs", [])
    if legs and max(legs) - min(legs) > 1.5:
        msgs.append("uneven ground under the tower (its legs %.1f m apart in height)" % (max(legs) - min(legs)))
    roads = getattr(ctx, "roads", None)
    R = roads.pos if roads is not None else t.pos
    W = roads.width if roads is not None else t.width
    plan = np.hypot(R[:, 0] - q[0], R[:, 2] - q[2])
    clear = float((plan - W / 2).min())
    if clear < CRANE_FRAME_W * sc / 2 + 1.0:
        msgs.append("the tower %.1f m from a road's edge" % clear)
    cab, rest, tips, booms = crane_sweep(ctx, spec, q)
    lo, hi = crane_reach(sc)
    for s, lat in _crane_spots(t, spec, p):
        i = idx(t, s)
        a = t.pos[i] + t.right[i] * lat
        d = math.hypot(a[0] - cab[0], a[2] - cab[2])
        if not lo + 0.3 <= d <= hi - 0.3:
            msgs.append("its magnet can not reach s %.0f lat %.1f (%.1f m from the pivot, reach %.1f-%.1f)"
                        % (s, lat, d, lo, hi))
            break
        if _kind(t, i) == "tunnel":
            msgs.append("its spot at s %.0f is in a tunnel" % s)
            break
        over = (np.hypot(R[:, 0] - a[0], R[:, 2] - a[2]) < W / 2 + 3.0) & (R[:, 1] > a[1] + 3.0)
        if over.any():
            msgs.append("a road over its spot at s %.0f" % s)
            break
    # the cab (on the tower, 13.7 m tall) and the boom as they turn: over the ground, and no road up there
    for j in range(16):
        ang = 2 * math.pi * j / 16
        g = ctx.ground(cab[0] + math.cos(ang) * CRANE_CAB_R * sc, cab[2] + math.sin(ang) * CRANE_CAB_R * sc)
        if g is not None and g > cab[1] - 0.5:
            msgs.append("its cab turns into the ground")
            break
    if ((plan < hi + 2.0) & (R[:, 1] > cab[1] - 1.0)).any():
        msgs.append("a road up at its boom's height in its swing")
    worst_boom = worst_mag = None
    road_y = min(t.pos[idx(t, s)][1] for s, _lat in _crane_spots(t, spec, p))
    swing_y = min(t.pos[idx(t, e["s"])][1] + p["rest_h"], road_y + p["high"])
    for (yaw, luff), tip in zip(booms, tips):
        for u in (0.25, 0.5, 0.75, 1.0):
            b = crane_point(cab, yaw, luff, u, sc)
            g = ctx.ground(b[0], b[2])
            if g is not None and g > b[1] - 1.0:
                worst_boom = b
        g = ctx.ground(tip[0], tip[2])
        if g is not None and g > swing_y - 1.0:
            worst_mag = tip
    if worst_boom is not None:
        msgs.append("its boom meets the ground at (%.0f, %.0f, %.0f)" % tuple(worst_boom))
    if worst_mag is not None:
        msgs.append("its magnet swings into the ground at (%.0f, %.0f)" % (worst_mag[0], worst_mag[2]))
    return msgs


def _barrier_on(t, i, sg):
    """Whether the style at sample i has a barrier on side sg (-1 left, +1 right) that stops a kart (or a
    guard): "sides" both, left, right or outside (the outside of the bend). A "broken" railing counts
    as open, and so does a rim under a metre (Xen's ledge: a guard steps over it, a kart thrown at it
    goes over)."""
    bar = _style(t, i).get("barrier")
    if not bar or bar.get("broken") or max(bar.get("h", 1.2), bar.get("col_h", 0.0)) < 1.0:
        return False
    sides = bar.get("sides", "both")
    if sides in ("left", "right"):
        return (sides == "right") == (sg > 0)
    if sides == "outside":
        curv = getattr(t, "curv", None)
        return curv is not None and (-1 if curv[i] > 0 else 1) == sg
    return True


def _guard_checks(ctx, e, data):
    """An antlion guard: a zone long enough to come out in; open ground near the road's height on its
    side along most of it (its home, the verge it charges from, steps aside to and walks home along),
    off every other road, with no barrier between it and the road; its branches exist. And, to say
    where its shove can send a kart over: the stretches of the zone where the far side is open (no
    barrier, the ground more than GUARD_DROP m down or none) and the "edges" its spec names."""
    t = ctx.trk
    p = e["p"]
    z0, z1 = p["zone"]
    sg = int(math.copysign(1, p["side"]))
    keep = p.get("keep", 2.0)
    deck = keep < 0.0
    msgs = []
    if (z1 - z0) % t.length < GUARD_ZONE_MIN:
        msgs.append("zone only %.0f m (want %.0f)" % ((z1 - z0) % t.length, GUARD_ZONE_MIN))
    names = [b["id"] for b in data.get("branches", [])]
    for b in p.get("branches", []):
        if b not in names:
            msgs.append("names no branch %r" % b)
    # where it stands and walks (keep metres past the edge, inside it on a deck) against the racing line
    path = data.get("path", {})
    near_line = 0
    ok = n = barred = 0
    open_runs, run = [], None
    for s in np.arange(z0, z1 + 0.1, 3.0):
        i = idx(t, s)
        edge_y = float(t.pos[i][1])
        good = True
        for sb in ((keep,) if deck else (2.0, 4.0, 6.0)):
            if deck:
                q = np.asarray(t.surface(i, sg * (t.width[i] / 2 + sb)), float)
                gy = q[1]
            else:
                q = side_point(ctx, i, sg, sb)
                g = ctx.ground(q[0], q[2])
                gy = q[1] if g is None else float(g)
            if abs(gy - edge_y) > 2.5 or (not deck and _off_road(ctx, q, s, 25.0) < 1.0):
                good = False
        n += 1
        ok += good
        if not deck:
            barred += _barrier_on(t, i, sg)
        if "line" in path and "step" in path:
            k = int(round(s / path["step"])) % len(path["center"])
            c, r = np.array(path["center"][k]), np.array(path["right"][k])
            line_lat = float(np.dot(np.array(path["line"][k]) - c, r))
            if abs(sg * (t.width[i] / 2 + keep) - line_lat) < GUARD_SCALE * 1.05 + 2.5:
                near_line += 1
        far = side_point(ctx, i, -sg, 2.5)
        g = ctx.ground(far[0], far[2])
        drop = not _barrier_on(t, i, -sg) and (g is None or edge_y - float(g) > GUARD_DROP)
        if drop and run is None:
            run = [s, s]
        elif drop:
            run[1] = s
        elif run is not None:
            open_runs.append(run)
            run = None
    if run is not None:
        open_runs.append(run)
    if ok / max(n, 1) < GUARD_ROOM:
        msgs.append("open ground on its side (%+d) at only %.0f%% of the zone" % (sg, 100.0 * ok / max(n, 1)))
    if barred / max(n, 1) > 0.3:
        msgs.append("a barrier on its side along %.0f%% of the zone: it can not get onto the road there" % (100.0 * barred / max(n, 1)))
    if near_line / max(n, 1) > 0.2:
        msgs.append("where it stands (keep %.1f) within reach of the racing line along %.0f%% of the zone" % (keep, 100.0 * near_line / max(n, 1)))
    for ed in p.get("edges", []) if isinstance(p.get("edges"), list) else []:
        if not _overlap(ed[0], ed[1], z0, z1 + p.get("tail", GUARD_TAIL), t.length):
            msgs.append("edge s %.0f-%.0f is outside its zone" % (ed[0], ed[1]))
    runs = [r for r in open_runs if r[1] - r[0] >= 6.0]
    msgs.append("open edge across from it at %s" % ", ".join("s %.0f-%.0f" % tuple(r) for r in runs) if runs
                else "no open edge across from it (its shove can not send a kart over)")
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
    if e["type"] == "train" and p.get("line"):
        msgs += _line_cross_checks(ctx, e, data)
    elif e["type"] == "train":
        a, b = np.array(p["a"]), np.array(p["b"])
        worst = min(_off_road(ctx, a + (b - a) * u, e["s"], 30.0) for u in np.linspace(0.0, 1.0, 66))
        if worst < 3.0:
            msgs.append("the line runs %.1f m from another stretch" % worst)
        ys = [y for _, y in p["profile"]]
        slope = max(abs(y1 - y0) / 4.0 for y0, y1 in zip(ys[:-1], ys[1:]))
        if slope > 0.12:
            msgs.append("rails climb %.0f%%" % (slope * 100))
        if p.get("mode") == "cross":
            msgs += _cross_checks(ctx, e, data)
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
    if e["type"] == "crane":
        msgs += _crane_checks(ctx, e)
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
    if e["type"] == "antlion":
        msgs += _sand_checks(ctx, e, data)
    if e["type"] == "antlion_guard":
        msgs += _guard_checks(ctx, e, data)
    if e["type"] == "seesaw":
        msgs += _seesaw_checks(ctx, e, data)
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


def _covers(e, where):
    """True for an antlion zone or an antlion guard that names the branch of junction `where` ("the fork
    of <id>"): its karts on that branch count too, so the zone may reach over the stretch the two roads
    share."""
    return e["type"] in ("antlion", "antlion_guard") and any(where.endswith(" of " + b) for b in e["p"].get("branches", []))


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
        if e["type"] == "train" and e["p"].get("mode") == "pass":
            # a train beside or over the road never touches a kart nor advises one: only its line's checks
            print("  hazard %-11s s %6.0f-%6.0f  %s" % (e["type"], a, b, ", ".join(_pass_checks(ctx, e)) or "ok"))
            continue
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
        hard = ["!! at %s (s %.0f-%.0f)" % (w, z0, z1) for w, z0, z1 in zones if _overlap(a, b, z0, z1, L)
                and not _covers(e, w)]
        on = next((o for o in (_on_branch(ctx, q, clear, names) for q, clear in _parts(e)) if o), None)
        if on:
            hard.append("!! stands on " + on)
        if e["type"] == "column":
            # its soldiers never stand on the karts' road
            bad = _column_on_road(ctx, e)
            if bad:
                hard.append("!! deck on a road at deck m %s" % ", ".join("%.0f" % u for u in bad[:6]))
            msgs += _column_checks(ctx, e, data, entries)
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
