"""Highway 17: Half-Life 2's coast road and the antlion beaches of Sandtraps, about 2.6 km.

From the start on the cliff-top highway the road runs west along the coast, crosses the inlet up
the river's valley on the long bay bridge and dives into the headland: a concrete portal, then
the bore where the road rolls all the way round, over the ceiling, and out above the sea. A cliff
road winds down the headland to the docks, along the quay past the rebels' magnet crane and over
the inlet's mouth on a wooden bridge onto the antlion beach. There the only safe road is the
boardwalk: planks a hand over the sand, a wooden bridge over the tidal pool between the dunes; the
sand beside them wakes the antlions. The coast road climbs the east cliff back onto the highway.

Two branches: the old coast bridge straight across the inlet, its middle span fallen into the
water (jump it; short of the far side you swim), and the stepping stones, a row of boards laid
straight along the shore with sand between them (shorter than the boardwalk's swing round the
dunes, but every gap is sand). A Combine gunship strafes the bay bridge; rebels and refugees watch
from the highway, the docks and the beach.

The traps (TRACK["hazards"], lap metres): the gunship over the bay bridge, the rebels' magnet
crane on the quay's apron (CRANE; decorate() puts nothing tall within reach of its boom) and two
antlion zones on the beach, the sand beside the boardwalk (SAND_STYLES) and beside the stepping
stones, with a Combine thumper keeping the sand quiet at the east cliff's foot. RESCUE_SPOTS
are level ground beside the road where a crane could stand.

The set dressing: wrecked cars, a Combine roadblock and its burnt-out APC, rebel barricades and
pylons along the highway; the old bridge's fallen span in the inlet and Highway 17's big bridge far
up its valley; rocks over the headland's portals; a moored trawler, buoys, a jetty, an idle dock
crane and a rebel camp round the docks; antlion hills, rocks, driftwood and wrecks on the beach
and a beached trawler under the east cliff, where a lighthouse stands on the point; sea stacks
offshore and seagulls over the sea.
"""
import math

import numpy as np

from track_gen import UP, carve, face, noise2, plane_uv, smoothstep, wall_strip

SEA_Y = 0.0
# the waterline, west to east: the headland's cliffs, the harbour west of the docks, the quay, the
# river mouth, the antlion beach and the east cliffs
COAST = [(-700.0, 392.0), (-400.0, 392.0), (-250.0, 390.0), (-160.0, 386.0), (-115.0, 372.0), (-80.0, 348.0),
         (-56.0, 322.0), (-44.0, 306.0), (-42.0, 305.0), (150.0, 305.0), (210.0, 308.0), (330.0, 314.0),
         (460.0, 316.0), (600.0, 312.0), (690.0, 304.0), (760.0, 290.0), (820.0, 258.0), (870.0, 200.0),
         (900.0, 120.0), (930.0, 0.0), (960.0, -200.0)]
# the inlet: the sea runs up the river's valley under the bay bridge and the old bridge, between
# cliffs, to its mouth east of the docks
RIVER = [(150.0, -520.0), (160.0, -300.0), (168.0, -120.0), (175.0, 0.0), (180.0, 140.0), (180.0, 240.0),
         (178.0, 300.0), (176.0, 380.0)]
# the quay: from the road down to its edge (QUAY_Z) the docks' apron at the road's height, past it
# the harbour's water
QUAY_Y = 3.8
QUAY_X, QUAY_Z = (-42.0, 150.0), 305.0
# the tidal pool between the dunes under the boardwalk's wooden bridge ("creek"): a lagoon along the
# whole deck, from POOL_IN metres past its start to POOL_OUT before its end (the boardwalk's planks run
# off both ends onto sand), POOL_W metres either side of the deck give or take its ragged shore, its
# floor POOL_Y under the sea's level. A kart that leaves the boards beside the deck drives into it
POOL_IN, POOL_OUT, POOL_W, POOL_Y = 6.0, 10.0, 15.0, -1.4
# the boardwalk's stretches over the antlion sand: everything beside them is sand
SAND_STYLES = ("boards", "creek", "stones")
# the rebels' magnet crane (CraneHazard): its magnet comes down over the quay road round lap metres s
# 1405 and carries a kart it catches 10 m on; its tower stands on the apron to the right, 10 m past
# the road's edge abeam of s 1410 (hazards.crane_base), the sky over the stretch its boom covers
# clear. CRANE_SPOT is about where the tower stands: the set dressing keeps its distance
CRANE = {"type": "crane", "s": 1405.0, "side": 1, "setback": 10.0}
CRANE_SPOT = (45.0, QUAY_Y - 0.35, 290.0)
# seconds a kart's wheels are on the beach sand before the antlions wake (AntlionHazard p["grace"]): by
# then a kart that ran off the boards at speed has slowed to the sand's pace and stopped swinging out,
# so the spot where they land is where it really will be (woken sooner they landed ahead of it and
# wide of it, and never bit)
SAND_GRACE = 1.0
# the rebels' camp behind the quay road's east end (lap metres; on the land side, past the containers)
CAMP_S = 1480.0
# level ground 12 m past the road's edge, 10 m and more from any prop, where a crane could stand
# (x, z): the highway's verges either side of the bay bridge and at the east end, two spots on
# the dunes inland of the boardwalk (none by the tidal pool)
RESCUE_SPOTS = [(456.0, 21.0), (-39.0, -21.0), (674.0, -19.0), (355.0, 251.0), (611.0, 260.0)]

CTRL = [
    # the start on the cliff-top highway, heading west with the sea down on the left
    (600, 25, 0, 16, "start"),
    (520, 25, 0, 16, "highway"),
    (450, 25.6, 1, 16, "highway"),
    (380, 25.6, 1, 16, "highway"),
    # the old coast bridge leaves on the left; the highway bows inland onto the bay bridge
    (310, 25.4, -3, 16, "highway"),
    (250, 25.8, -20, 16, "baybridge"),
    (180, 26.2, -40, 16, "baybridge"),
    (110, 26.2, -40, 16, "baybridge"),
    (45, 25.9, -22, 16, "baybridge"),
    (-15, 25.6, -4, 16, "highway"),
    (-75, 25.4, 2, 16, "highway"),
    # (the old bridge comes back in on the left) and south into the headland
    (-135, 25.2, 6, 16, "highway"),
    (-182, 25.0, 22, 16, "highway"),
    (-212, 24.8, 56, 15, "highway"),
    (-224, 24.6, 92, 14, "portal"),
    (-228, 24.4, 114, 14, "bore"),
    (-230, 24.0, 200, 14, "bore"),
    (-228, 23.6, 286, 14, "bore"),
    (-224, 23.4, 306, 14, "portal"),
    # out over the sea and down the headland's cliff to the docks
    (-212, 23.0, 330, 15, "cliffroad"),
    (-185, 20.5, 350, 15, "cliffroad"),
    (-145, 16.5, 352, 15, "cliffroad"),
    (-105, 12.0, 336, 15, "cliffroad"),
    (-75, 8.0, 310, 15, "cliffroad"),
    (-45, 5.0, 288, 15, "cliffroad"),
    # the quay: the crane's apron on the right, between the road and the harbour
    (-5, 3.8, 276, 15, "quay"),
    (55, 3.8, 272, 15, "quay"),
    (102, 3.8, 272, 15, "quay"),
    # the wooden bridge over the inlet's mouth
    (128, 4.1, 272, 13, "woodbridge"),
    (176, 4.2, 274, 13, "woodbridge"),
    (218, 4.1, 277, 13, "woodbridge"),
    # the antlion beach: the boardwalk, the stepping stones leave on the right
    (244, 3.9, 278, 12, "boards"),
    (322, 3.8, 278, 12, "boards"),
    (372, 4.0, 263, 12, "boards"),
    (403, 4.4, 232, 12, "boards"),
    (440, 4.6, 211, 12, "creek"),
    (482, 4.4, 213, 12, "creek"),
    (520, 4.0, 240, 12, "boards"),
    (554, 3.8, 268, 12, "boards"),
    (600, 3.9, 277, 12, "boards"),
    (650, 4.2, 278, 12, "boards"),
    # up the east cliff with the sea on the right, round onto the highway
    (698, 6.0, 274, 14, "cliffroad"),
    (748, 9.5, 258, 14, "cliffroad"),
    (792, 13.5, 228, 14, "cliffroad"),
    (814, 17.5, 186, 15, "cliffroad"),
    (814, 21.5, 138, 15, "highway"),
    (797, 24.5, 88, 16, "highway"),
    (760, 25.0, 38, 16, "highway"),
    (700, 25.0, 6, 16, "highway"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]

BRANCHES = [
    # the old coast bridge: straight across the valley on the seaward side of the bay bridge, its
    # middle span fallen into the river (a kicker on its broken end; short of the far side you swim)
    {"id": "old_bridge", "name": "Old bridge", "fork": (350, 0), "merge": (-40, 0), "kind": "jump",
     "ctrl": [(318, 25.5, 9, 12, "oldroad"), (296, 25.5, 14, 12, "oldbridge"), (240, 25.6, 18, 12, "oldbridge"),
              (195, 25.6, 19, 12, "oldbridge", {"gap": True, "gap_span": (0.43, 0.81), "ramp_lift": 2.2,
                                                  "ramp_len": 18}),
              (145, 25.6, 19, 12, "oldbridge"), (85, 25.5, 17, 12, "oldbridge"), (40, 25.5, 13, 12, "oldbridge"),
              (14, 25.5, 9, 12, "oldroad")],
     "risk": 0.7, "ai": {"take": 0.5, "min_skill": 0.88}, "retry_back": 60.0},
    # the stepping stones: boards laid straight along the shore, sand between them, instead of the
    # boardwalk's swing round the dunes and over the tidal pool
    {"id": "stepping_stones", "name": "Stepping stones", "fork": (255, 278), "merge": (625, 277), "kind": "trail",
     "side": 1,
     "ctrl": [(292, 3.7, 294, 10, "stones"), (380, 3.6, 298, 10, "stones"), (460, 3.6, 298, 10, "stones"),
              (540, 3.6, 296, 10, "stones"), (588, 3.7, 291, 10, "stones")],
     "risk": 0.3, "ai": {"take": 0.4, "min_skill": 0.8}},
]
# the stepping stones: a board this long, then this much sand (metres along the branch): a gap
# longer than a kart's wheelbase puts three wheels on the sand at once (Kart.offroad)
STONE_BOARD, STONE_GAP = 3.5, 4.0

TRACK = {
    "id": "city17_circuit",
    "name": "Highway 17",
    "ctrl": CTRL,
    "music": ["hl2_song12_long", "hl2_song14", "hl2_song20_submix0", "hl2_song29", "hl2_song31"],
    "items": [0.058, 0.187, 0.296, 0.486, 0.56, 0.67, 0.75, 0.855, 0.94],
    "boosts": [0.08, 0.163, 0.272, 0.443, 0.53, 0.73, 0.836, 0.914],
    "barrels": [0.29, 0.925],
    "vmax": 40.0,
    "offtrack": 60.0,
    # the game's gravity (project.godot): the launch speeds the branches export are the real ones
    "gravity": 15.24,
    "sky": "sky_day01_05",
    # (the start gantry's pillars just past the verges, clear of the rally crowd behind them)
    "gantry_clear": 4.0,
    "water": {"level": SEA_Y},
    "env": {"fog_begin": 320.0, "fog_end": 2800.0},
    # the Citadel far up the coast behind the headland
    "citadel": [-1400, -200, -1700, 9.0],
    # the circles of the seagulls BackgroundLife flies over the sea (decorate() fills it in)
    "seagulls": [],
    # (lap metres: the old bridge's fork s 252 and merge s 648, the bay bridge s 354-626, the quay
    # s 1361-1495, the boardwalk s 1611-1827 and 1917-2107 with the tidal pool's bridge between, the
    # stepping stones' fork s 1621-1663 and merge s 1999-2035)
    "hazards": [
        # the gunship leaves its patrol and strafes the bay bridge head-on, one side at a time (the old
        # bridge, seaward of it, is out of its run)
        {"type": "air_strafe", "zone": [380, 590], "period": 40, "first": 35},
        CRANE,
        # the antlion beach, the sand on both sides of the boardwalk from past the stepping stones' fork
        # (its signs stand on the sand by their mouth); a kart that runs off the stepping stones onto
        # the sand wakes them too
        {"type": "antlion", "zone": [1665.0, 1805.0], "side": 0, "branches": ["stepping_stones"], "grace": SAND_GRACE},
        # ... and on beyond the tidal pool's bridge on the dunes' side (on the other the stepping stones
        # come back in: too little sand between for them to come up out of), where a Combine thumper at
        # the foot of the east cliff keeps the last of the sand quiet
        {"type": "antlion", "zone": [1925.0, 2075.0], "side": -1, "branches": ["stepping_stones"], "grace": SAND_GRACE,
         "thumper": {"s": 2068.0, "side": -1, "setback": 9.0}},
    ],
}


def styles(m):
    asphalt = m.hl2("concrete/concretefloor037b")
    worn = m.hl2("concrete/concretefloor006a")
    planks = m.hl2("wood/woodfloor005a")
    beam = m.hl2("wood/woodbeam001a")
    sand = m.hl2("nature/blendsandsand008a")
    grass = m.hl2("nature/blendsandsand008b")
    pier = m.hl2("concrete/concretewall066a")
    retaining = m.hl2("concrete/concretewall059d")
    # (cliffface002a's limestone tiles evenly: cliffface001a, grass along its top edge and dark at its
    # foot, laid on every slope and lid in rows of the same band like corrugated iron)
    rock = m.hl2("nature/cliffface002a")
    # the highway's guard rail, a little out from the road's edge on the cliff's side; a kart thrown
    # up meets its unseen wall up to 2.5 m
    rail = {"kind": "fence", "mat": m.hl2("metal/metalrail013a"), "h": 1.0, "rep": 2.4, "col_h": 2.5}
    parapet = {"kind": "wall", "mat": m.hl2("concrete/concretewall064a"), "h": 1.0, "thick": 0.5, "rep": 3.0,
               "col_h": 3.0}
    wood_rail = {"kind": "fence", "mat": m.hl2("wood/woodwall009a"), "h": 0.9, "rep": 2.0, "col_h": 2.2}
    highway = {"kind": "open", "road": asphalt, "road_u": "full", "road_len": 1.0, "verge": grass, "verge_w": 4.0,
               "skirt": retaining}
    # the boardwalk: planks a hand over the sand, the sand drifted up to its edges (the verge: sand,
    # an off-road surface like the terrain beside it)
    boards = {"kind": "open", "road": planks, "road_rep": 4.0, "verge": sand, "verge_w": 1.2, "verge_drop": 0.3,
              "skirt": beam, "gore_mat": planks}
    woodbridge = {"kind": "bridge", "road": planks, "road_rep": 4.0, "skirt": beam, "skirt_h": 1.0,
                  "barrier": wood_rail, "pillar": beam, "pillar_every": 8.0, "pillar_size": 0.6,
                  "pillar_offsets": [-0.85, 0.0, 0.85], "ground": "nat"}
    return {
        # the start straight, its grid level and unbanked
        "start": highway,
        "highway": dict(highway, barrier=dict(rail, sides="left", off=1.0)),
        # the bay bridge over the valley: concrete parapets, stained piers down to the valley's floor
        # (the land under it left as it lies)
        "baybridge": {"kind": "bridge", "road": asphalt, "road_u": "full", "skirt": pier, "skirt_h": 2.2,
                      "barrier": parapet, "pillar": pier, "pillar_every": 34.0, "pillar_size": 3.0,
                      "ground": "nat"},
        # the old coast road and its bridge: worn concrete, the seaward parapet broken in places
        "oldroad": {"kind": "open", "road": worn, "road_rep": 6.0, "verge": grass, "verge_w": 3.0, "skirt": retaining,
                    "barrier": dict(rail, off=1.0)},
        "oldbridge": {"kind": "bridge", "road": worn, "road_rep": 6.0, "skirt": pier, "skirt_h": 2.0,
                      "barrier": dict(parapet, broken=[16.0, 6.0], sides="right"), "pillar": pier,
                      "pillar_every": 30.0, "pillar_size": 2.6, "ground": "nat"},
        # the headland tunnel: a concrete portal at each end, the bore between them
        "portal": {"kind": "tunnel", "road": asphalt, "road_u": "full", "height": 7.5, "wall": retaining,
                   "ceil": m.hl2("concrete/concreteceiling004a"), "light": m.hl2("lights/fluorescentcool001a"),
                   "light_every": 8.0, "light_color": [1.0, 0.9, 0.75], "light_energy": 1.6, "wall_gap": 0.6,
                   "cover": 4.0, "lid_w": 10.0, "lid_mat": grass, "portal": m.hl2("concrete/concretewall059a")},
        # the bore: the road rolls once all the way round (over the ceiling), back at the bottom well
        # before the exit ("settle")
        "bore": {"kind": "tube", "road": asphalt, "road_u": "full", "ground": "rest", "settle": 16.0,
                 "wall": m.hl2("concrete/concretewall059e"), "skin": rock,
                 "glow": m.hl2("lights/fluorescent001a"), "radius": 10.0, "roll": 360.0, "ring_every": 14.0,
                 "light_color": [1.0, 0.88, 0.66], "light_energy": 1.6},
        # the cliff roads, the sea on the right: a guard rail over the drop
        "cliffroad": dict(highway, verge_w=3.0, skirt=rock, barrier=dict(rail, sides="right", off=1.0)),
        "quay": {"kind": "open", "road": worn, "road_rep": 6.0, "verge": m.hl2("concrete/concretefloor028c"),
                 "verge_w": 3.0},
        "woodbridge": woodbridge,
        # the boardwalk's wooden bridge over the tidal pool
        "creek": dict(woodbridge),
        "boards": boards,
        # the stepping stones' sand (decorate_branch lays the boards on it and makes it off-road)
        # (its sand's ripples at the terrain's own scale, 5 m: terrain uv / 4 x sand_scale 0.8)
        "stones": {"kind": "open", "road": sand, "road_rep": 5.0, "verge": sand, "verge_w": 2.0},
    }


# ---------------------------------------------------------------- terrain
def _poly_dist(P, poly):
    best = np.full(len(P), 1e9)
    pts = np.asarray(poly, float)
    for a, b in zip(pts[:-1], pts[1:]):
        ab = b - a
        t = np.clip(((P - a) @ ab) / (ab @ ab), 0.0, 1.0)
        q = a + t[:, None] * ab
        best = np.minimum(best, np.linalg.norm(P - q, axis=1))
    return best


def _inland(P):
    """Metres from the waterline (COAST), positive inland (north of it), negative out at sea."""
    c = np.asarray(COAST, float)
    zc = np.interp(P[:, 0], c[:, 0], c[:, 1])
    return _poly_dist(P, COAST) * np.where(P[:, 1] < zc, 1.0, -1.0)


def _nearest(P, Q):
    """For each plan point of P (n, 2): the distance to the nearest of Q (m, 2) and its index."""
    dist = np.zeros(len(P))
    idx = np.zeros(len(P), int)
    for a in range(0, len(P), 4096):
        d2 = ((P[a:a + 4096, None, :] - Q[None, :, :]) ** 2).sum(-1)
        idx[a:a + 4096] = d2.argmin(1)
        dist[a:a + 4096] = np.sqrt(d2[np.arange(len(d2)), idx[a:a + 4096]])
    return dist, idx


def _natural(P):
    """The coast as it lies: the sea floor, the beach and its dunes, the bluffs up to the plateau the
    highway runs on (hills behind it), the headland's high cliffs, the east cliffs, the inlet up the
    river's valley (the tidal pool under the boardwalk's bridge is _lagoon's)."""
    x, z = P[:, 0], P[:, 1]
    d = _inland(P)
    n1 = noise2(x / 140.0, z / 140.0, 3)
    n2 = noise2(x / 38.0, z / 38.0, 9)
    # the beach's width: none under the headland and the east cliffs, the docks' apron, the long
    # antlion beach
    beach_w = np.interp(x, [-140.0, -70.0, 150.0, 210.0, 640.0, 720.0, 800.0],
                        [0.0, 40.0, 40.0, 150.0, 150.0, 40.0, 0.0])
    dunes = 2.4 * smoothstep(8.0, 40.0, d) * (n2 - 0.35)
    beach = 0.8 + 2.6 * smoothstep(0.0, 30.0, d) + dunes
    # the plateau: the highway's cliff top at 24-30 m, hills rising behind it; the headland higher
    plateau = 27.0 + 7.0 * (n1 - 0.5) + 22.0 * smoothstep(-40.0, -260.0, z)
    plateau = np.maximum(plateau, (44.0 + 8.0 * (n1 - 0.5)) * smoothstep(-80.0, -150.0, x))
    bluff = smoothstep(beach_w, beach_w + np.interp(x, [-140.0, 0.0, 700.0, 800.0], [30.0, 90.0, 90.0, 40.0]), d)
    land = beach * (1.0 - bluff) + plateau * bluff
    sea = -2.5 + 0.06 * np.maximum(d, -150.0)
    h = np.where(d > 0.0, land, sea)
    # the inlet up the river's valley: the sea between its cliffs, a narrow beach at their feet
    rd = _poly_dist(P, RIVER)
    valley = smoothstep(105.0, 46.0, rd) * (d > -20.0)
    floor = -3.5 + 5.5 * smoothstep(30.0, 44.0, rd) + 1.2 * n2 * smoothstep(34.0, 44.0, rd)
    h = h * (1.0 - valley) + np.minimum(h, floor) * valley
    return h


def _lagoon(P, lap):
    """The tidal pool under the boardwalk's wooden bridge: per plan point how far to dig it down to
    POOL_Y (0..1), a lagoon along the deck (POOL_*) with a ragged shore sloping up onto the dunes over
    a few metres, tapering off before either end of the deck."""
    m = np.zeros(len(P))
    ids = np.array([i for i in range(lap.n) if lap.style[i] == "creek"])
    if not len(ids):
        return m
    c = lap.pos[ids][:, [0, 2]]
    near = np.all((P > c.min(0) - 60.0) & (P < c.max(0) + 60.0), axis=1)
    if not near.any():
        return m
    Q = P[near]
    d, k = _nearest(Q, c)
    s = lap.s[ids][k]
    a, b = lap.s[ids[0]] + POOL_IN, lap.s[ids[-1]] - POOL_OUT
    w = POOL_W + 5.0 * (noise2(Q[:, 0] / 22.0, Q[:, 1] / 22.0, 33) - 0.5)
    m[near] = smoothstep(w + 4.0, w - 2.0, d) * smoothstep(a, a + 12.0, s) * smoothstep(b, b - 12.0, s)
    return m


def _bore_runs(roads):
    """The main lap's bore: the sample runs of its tube stretches."""
    t = roads.main
    return [ids for ids, _ in t.tube_runs]


# metres past the bore's ends (along the portals) over which the headland beside them comes down
BORE_FADE = 24.0


def _bore_lid(trk, ids, cell):
    """Over the bore a lid of rock covers its top and the terrain's slot beside its skin (the
    heightfield can not close over it): (lid height per sample, half width)."""
    R = trk.mag[ids[0]]
    y = trk.base[ids, 1] + 2.0 * R + 0.6 + 1.2
    return y, R + 0.6 + cell * 1.5 + 2.5


def terrain(roads, m):
    layers = {"base": m.hl2("nature/blendsandsand008b"), "dirt": m.hl2("nature/dirtfloor006a"),
              "rock": m.hl2("nature/cliffface002a"), "pave": m.hl2("concrete/concretefloor006a"),
              "sand": m.hl2("nature/blendsandsand008a")}

    def build(f, roads):
        P = f.P
        x, z = P[:, 0], P[:, 1]
        lap = roads.main
        nat = _natural(P)
        pool = _lagoon(P, lap)
        nat = nat + (np.minimum(nat, POOL_Y) - nat) * pool
        # the docks' apron: level at the quay's height from the hill's foot down to the quay's edge,
        # the harbour's water past it
        docks = (x > QUAY_X[0]) & (x < QUAY_X[1]) & (z > 262.0)
        apron = smoothstep(QUAY_X[0], QUAY_X[0] + 12.0, x) * smoothstep(QUAY_X[1], QUAY_X[1] - 12.0, x)
        nat = np.where(docks & (z < QUAY_Z), nat + (QUAY_Y - 0.35 - nat) * apron, nat)
        nat = np.where(docks & (z >= QUAY_Z), np.minimum(nat, -5.0), nat)
        h = carve(f, nat, roads, flat=7.0, blend=30.0)
        h = np.where(docks & (z >= QUAY_Z), np.minimum(h, -5.0), h)
        # (and over the boardwalk's bed where its legs' carve reached the pool's inland half)
        h = h + (np.minimum(h, POOL_Y) - h) * pool
        # the bore runs under the headland: past the slot beside its skin the ground rises to its lid
        # (which closes over the slot) and on up into the headland
        for ids in _bore_runs(roads):
            lid_y, lid_w = _bore_lid(lap, ids, f.cell)
            d, k = _nearest(P, lap.base[ids][:, [0, 2]])
            along = ((P - lap.base[ids][k][:, [0, 2]]) * lap.fwd[ids][k][:, [0, 2]]).sum(1)
            # metres past either end of the bore along the road (0 beside it)
            past = np.maximum(np.where(k == 0, -along, 0.0) + np.where(k == len(ids) - 1, along, 0.0), 0.0)
            slot = lap.mag[ids[0]] + 0.6 + f.cell + 0.5
            ridge = np.maximum(lid_y[k] - 0.3, nat) * (1.0 - smoothstep(lid_w + 10.0, lid_w + 60.0, d)) + \
                nat * smoothstep(lid_w + 10.0, lid_w + 60.0, d)
            under = (d >= slot) & (d <= lid_w) & (past < lap.step * 0.5)
            h = np.where(under, lid_y[k] - 0.3, h)
            # past the ends the hill comes down over BORE_FADE metres beside the portals (cut off
            # there it stood as a fin of lid height three metres thick reaching far out sideways)
            # (measured across the road there: the plan distance to the end sample counts the metres
            # along too, and would raise the ground right beside the portal's walls)
            fade = smoothstep(BORE_FADE, 0.0, past)
            side = np.sqrt(np.maximum(d * d - past * past, 0.0))
            h = np.where(side > lid_w, h + (np.maximum(h, ridge) - h) * fade, h)
        # beside a deck the ground stays under it for a grid cell past its edge, so no terrain
        # triangle reaches up through its edge
        deck = np.flatnonzero(np.array([roads.kind(i) == "bridge" for i in range(roads.n)]) & ~roads.gap)
        if len(deck):
            d, k = _nearest(P, roads.pos[deck][:, [0, 2]])
            near = d < roads.width[deck][k] / 2 + f.cell + 0.5
            h = np.where(near, np.minimum(h, roads.pos[deck][k, 1] - 0.5), h)
        # no lone spike of ground by a road where the carves of two roads meet
        Hm = h.reshape(f.nz, f.nx)
        by_road = (f.dist < f.half + 40.0).reshape(f.nz, f.nx)
        for _ in range(2):
            pad = np.pad(Hm, 1, mode="edge")
            nb = np.maximum(np.maximum(pad[:-2, 1:-1], pad[2:, 1:-1]), np.maximum(pad[1:-1, :-2], pad[1:-1, 2:]))
            Hm = np.where(by_road & (Hm > nb + 2.5), nb, Hm)
        h = np.minimum(Hm.ravel(), f.cap)
        # the ground's layers: rock on the cliffs, the green cliff tops, the docks' concrete, the
        # antlion sand all over the beach (beside the boardwalk and the stepping stones nothing else)
        Hm = h.reshape(f.nz, f.nx)
        gz, gx = np.gradient(Hm, f.cell)
        slope = np.sqrt(gx ** 2 + gz ** 2)
        for _ in range(2):
            pad = np.pad(slope, 1, mode="edge")
            slope = (pad[:-2, 1:-1] + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:] + 4.0 * slope) / 8.0
        rock = smoothstep(0.55, 0.95, slope.ravel())
        d = _inland(P)
        on_sand = np.isin(f.style, SAND_STYLES)
        near_sand = on_sand & (f.dist < f.half + 40.0)
        beach = smoothstep(2.0, 0.0, np.abs(h - 2.5) - 6.0) * smoothstep(-6.0, 4.0, d) * (h < 12.0)
        sand = np.clip(np.maximum(beach, near_sand.astype(float)), 0.0, 1.0)
        rock = np.where(near_sand, 0.0, rock * (1.0 - 0.6 * sand))
        pave = (docks & (z < QUAY_Z + 1.0) & (h > QUAY_Y - 1.5)).astype(float) * (1.0 - rock)
        sand = sand * (1.0 - pave)
        dirt = smoothstep(16.0, 22.0, h) * (1.0 - rock) * smoothstep(0.35, 0.65, noise2(x / 60.0, z / 60.0, 21))
        col = np.stack([dirt, rock, pave, sand], 1).astype(np.float32)
        return h, col

    return {"margin": 320.0, "cell": 3.0, "build": build, "layers": layers}


# ---------------------------------------------------------------- set dressing
def _by_style(t):
    """A road's sample indices per style name."""
    by = {}
    for i in range(t.n):
        by.setdefault(t.style[i], []).append(i)
    return by


def _runs(ctx, ids):
    """The runs of consecutive samples among ids (none for none)."""
    return ctx.runs_of(ids) if ids else []


def _flare(ctx, i, back, sgn, wide=2.5, bar=None, end=0.0):
    """A rail in the railing that starts at sample i (a deck's, at its edge), on the open road
    before it: from `wide` metres past the verge's outer edge `back` metres before in to the
    railing's line, so a kart out wide is led onto the deck instead of into the railing's end.
    Before a tunnel's portal (bar: the rail to build, end: its wall's metres past the road's edge)
    it leads in to the tunnel's wall instead of into the portal's face. None where it would come
    within 2 m of another road (a branch beside the lap, the lap beside a branch: it would stand
    across it); returns whether it was built."""
    t = ctx.trk
    bar = bar or t.styles[t.style[i]]["barrier"]
    n = int(round(back / t.step))
    j0 = t.wrap(i - n)
    vw = t.styles[t.style[j0]].get("verge_w", 0.0)
    thick = min(bar.get("thick", 0.1), 0.4)
    start = vw + wide
    pts = []
    for k in range(n + 1):
        j = t.wrap(i - n + k)
        out = (start + thick - end) * (1.0 - k / n) + end + thick / 2
        pts.append(t.pos[j] + t.right[j] * sgn * t.width[j] / 2 + t.flat_right[j] * sgn * out)
    r = ctx.roads
    own = next(k for k, tr in enumerate(r.trks) if tr is t)
    other = np.flatnonzero((r.route != own) & ~r.gap)
    if len(other):
        P = np.array(pts)[:, [0, 2]]
        d = np.sqrt(((P[:, None, :] - r.pos[other][None, :, [0, 2]]) ** 2).sum(-1)) - r.width[other][None, :] / 2
        if d.min() < 2.0:
            return False
    for a, b in zip(pts[:-1], pts[1:]):
        foot = min(ctx.ground(a[0], a[2]), ctx.ground(b[0], b[2]), a[1], b[1]) - 0.3
        top = max(a[1], b[1]) + bar.get("h", 1.2)
        along = b - a
        ctx.box(bar["mat"], [(a[0] + b[0]) / 2, (foot + top) / 2, (a[2] + b[2]) / 2],
                [thick, top - foot, math.hypot(along[0], along[2]) + 0.05], ctx.yaw_facing(along),
                rep=bar.get("rep", 3.0))
    # over it, like over the railing it leads into, an unseen wall up to the barrier's col_h on its
    # road side: a kart that hits it hard is stopped instead of hopping over the rail into the water
    h, col_h = bar.get("h", 1.2), bar.get("col_h", 0.0)
    if col_h > h + 0.05:
        P = np.array(pts) - np.array([t.flat_right[t.wrap(i - n + k)] * sgn * thick / 2 for k in range(n + 1)])
        v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
        wall_strip(ctx.meshes["colonly"], "colonly", P + UP * h, P + UP * col_h, v, sgn, bar.get("rep", 3.0))
    return True


def _deck_flares(ctx, by, styles, back=36.0):
    """Rails flaring in from the verges onto every deck an open road runs onto, on each side where
    that road has no rail of its own running up to the deck."""
    t = ctx.trk
    for style in styles:
        for run in _runs(ctx, by.get(style, [])):
            prev = t.wrap(run[0] - 1)
            if t.kind(prev) != "open" or t.gap[run[0]]:
                continue
            bar = t.styles[t.style[prev]].get("barrier")
            for sgn in (-1, 1):
                if bar and (bar.get("sides", "both") == "both" or (bar["sides"] == "right") == (sgn > 0)):
                    continue
                _flare(ctx, run[0], back, sgn)


def _portal_flares(ctx, by, back=40.0):
    """Before each tunnel portal an open road runs into: a guard rail flaring in from past its verge
    to the tunnel's wall, on each side where the road has no rail of its own, so a kart out on the
    verge is led into the tunnel instead of into the portal's face."""
    t = ctx.trk
    for style, st in t.styles.items():
        if st["kind"] != "tunnel":
            continue
        for run in _runs(ctx, by.get(style, [])):
            prev = t.wrap(run[0] - 1)
            if t.kind(prev) != "open":
                continue
            own = t.styles[t.style[prev]].get("barrier")
            rail = own or {"kind": "fence", "mat": ctx.mats.hl2("metal/metalrail013a"), "h": 1.0, "rep": 2.4,
                           "col_h": 2.5}
            for sgn in (-1, 1):
                if own and (own.get("sides", "both") == "both" or (own["sides"] == "right") == (sgn > 0)):
                    continue
                _flare(ctx, run[0], back, sgn, bar=rail, end=st.get("wall_gap", 0.0))


def _pipe_caps(ctx):
    """Where a portal runs into the bore (or out of it), the bore's end ring stands open above the
    portal's roof: from outside you would look into the bore over the portal. A cap of the bore's
    skin closes the ring above the roof, facing out of the bore."""
    t = ctx.trk
    for ids in ctx.runs_of([i for i in range(t.n) if t.kind(i) == "tube"]):
        for end, nb, out in ((ids[0], t.wrap(ids[0] - 1), -1.0), (ids[-1], t.wrap(ids[-1] + 1), 1.0)):
            if t.kind(nb) != "tunnel":
                continue
            st = t.styles[t.style[end]]
            r = st["radius"] + 0.6
            up, right = t.base_up[end], t.base_right[end]
            c = t.base[end] + up * st["radius"] - t.fwd[end] * out * 0.05
            # the chord along the portal's roof, the arc over the top
            a = math.asin(np.clip((t.height[nb] - st["radius"]) / r, -1.0, 1.0))
            pts = [c + (right * math.cos(th) + up * math.sin(th)) * r for th in np.linspace(a, math.pi - a, 25)]
            face(ctx.meshes["walls"], st["skin"], pts, t.fwd[end] * out, [[p @ right / 4.0, p @ up / 4.0] for p in pts],
                 center=True)


def _bore_lids(ctx):
    """The lid over the bore (see _bore_lid), from portal to portal, the headland's grass a hand over
    the ground beside the bore, and its rock ends down to the portals' lids."""
    t = ctx.trk
    rock = ctx.mats.hl2("nature/cliffface002a")
    grass = ctx.mats.hl2("nature/blendsandsand008b")
    cell = ctx.field.cell if ctx.field is not None else 3.0
    for ids, _ in t.tube_runs:
        lid_y, lid_w = _bore_lid(t, ids, cell)
        rf = t.base_right[ids] * np.array([1.0, 0.0, 1.0])
        rf /= np.linalg.norm(rf, axis=1, keepdims=True)
        c = t.base[ids].copy()
        # (just over the ground beside the bore, lid_y - 0.3, and well clear of the pipe's skin)
        c[:, 1] = lid_y - 0.22
        L, R = c - rf * lid_w, c + rf * lid_w
        v = np.arange(len(ids)) * t.step / 4.0
        up = UP[None].repeat(len(ids), 0)
        ctx.meshes["walls"].strip(grass, L, R, -lid_w / 4.0, lid_w / 4.0, v, up, up)
        # each end down to the portal's lid
        for k, sgn in ((0, -1.0), (-1, 1.0)):
            nb = t.wrap(ids[k] + int(sgn))
            st = t.styles[t.style[nb]]
            low = t.pos[nb][1] + t.height[nb] + st.get("cover", 0.0) - 0.3
            a, b = L[k], R[k]
            q = [a, b, np.array([b[0], low, b[2]]), np.array([a[0], low, a[2]])]
            # (plane_uv wants a unit axis: across the whole 35 m face the texture repeated ~300 times
            # and read as a smooth beige band over the portal)
            face(ctx.meshes["walls"], rock, q, t.fwd[ids[k]] * sgn, plane_uv(q, a, (b - a) / np.linalg.norm(b - a), 4.0))


def _quay_wall(ctx):
    """The quay's concrete wall from the apron down into the harbour, and pilings standing in the
    water along its face (their tops a couple of metres under the apron)."""
    wall = ctx.mats.hl2("concrete/concretewall059c")
    x0, x1 = QUAY_X
    top = QUAY_Y - 0.35
    ctx.box(wall, [(x0 + x1) / 2, (top - 6.0) / 2, QUAY_Z + 0.6], [x1 - x0, top + 6.0, 1.2], 0.0, rep=4.0)
    for x in np.arange(x0 + 6.0, x1 - 2.0, 9.0):
        q = np.array([x, 0.0, QUAY_Z + 1.6])
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_docks/dock01_pole01a_256", q, ctx.rng.uniform(0, 6.28))


def _boardwalk(ctx, ids):
    """The boardwalk's edges: a beam along each side of the planks, short posts every 5 m and a rope
    between them (all seen, never hit: a kart that runs off the boards drives on into the sand)."""
    t = ctx.trk
    beam = ctx.mats.hl2("wood/woodbeam001a")
    rope = ctx.mats.hl2("wood/woodbeam002a")
    for run in _runs(ctx, ids):
        for sgn in (-1, 1):
            col = (sgn + 1) // 2
            keep = [i for i in run if not t.side_off[i, col] and not t.junction[i]]
            for sub in _runs(ctx, keep):
                if len(sub) < 3:
                    continue
                e = np.array([t.pos[i] + t.right[i] * sgn * (t.width[i] / 2 + 0.12) for i in sub])
                rf = np.array([t.flat_right[i] * sgn for i in sub])
                v = np.arange(len(sub)) * t.step / 2.0
                # the beam: its top 6 cm over the planks, its outer face down into the sand
                top_in, top_out = e + UP * 0.06 - rf * 0.12, e + UP * 0.06 + rf * 0.12
                ctx.meshes["deco"].strip(beam, top_in, top_out, 0.0, 0.12, v, UP[None].repeat(len(sub), 0),
                                         UP[None].repeat(len(sub), 0))
                low = top_out - UP * 0.5
                if sgn > 0:
                    ctx.meshes["deco"].strip(beam, top_out, low, 0.0, 0.25, v, rf, rf)
                else:
                    ctx.meshes["deco"].strip(beam, low, top_out, 0.25, 0.0, v, rf, rf)
                # posts and rope, on the sand at the verge's foot
                k = max(1, int(round(5.0 / t.step)))
                posts = []
                for q in range(0, len(sub), k):
                    i = sub[q]
                    p = t.pos[i] + t.right[i] * sgn * t.width[i] / 2 + t.flat_right[i] * sgn * 1.0
                    g = ctx.ground(p[0], p[2])
                    p[1] = min(g, t.pos[i][1] - 0.2)
                    ctx.box(beam, p + UP * 0.45, [0.14, 1.1, 0.14], ctx.yaw_facing(t.fwd[i]), kind="deco", rep=1.0)
                    posts.append(p + UP * 0.85)
                for a, b in zip(posts[:-1], posts[1:]):
                    _rod(ctx.meshes["deco"], rope, a, b, 0.025)


def _rod(mesh, mat, a, b, r, rep=2.0):
    """A thin square rod from a to b, r metres from its axis to each face, its texture's v (the
    beams' grain) running along it: a box's faces would lay the grain across a rod this thin."""
    d = b - a
    L = float(np.linalg.norm(d))
    if L < 1e-3:
        return
    f = d / L
    side = np.cross(f, UP)
    side = side / np.linalg.norm(side) if np.linalg.norm(side) > 1e-6 else np.array([1.0, 0.0, 0.0])
    up = np.cross(side, f)
    corners = [side + up, -side + up, -side - up, side - up]
    v = np.array([0.0, L / rep])
    for k in range(4):
        c0, c1 = corners[k] * r, corners[(k + 1) % 4] * r
        n = (c0 + c1) / np.linalg.norm(c0 + c1)
        nn = np.tile(n, (2, 1))
        # (from the next corner to this one: the strip faces out of the rod)
        mesh.strip(mat, np.array([a + c1, b + c1]), np.array([a + c0, b + c0]), 0.0, 0.08, v, nn, nn)


def _docks(ctx, by):
    """Containers and crates stacked on the land side of the quay road (the crane's apron on the
    other side stays free), a few on the apron's far ends."""
    t = ctx.trk
    rng = ctx.rng
    quay = by.get("quay", [])
    boxes = ["props_wasteland/cargo_container01", "props_wasteland/cargo_container01b"]
    for k, i in enumerate(quay[6::9]):
        m = boxes[k % len(boxes)]
        if m not in ctx.models:
            ctx.missing.add(m)
            continue
        yaw = ctx.yaw_along(m, t.fwd[i])
        q = ctx.side(i, -1, t.styles["quay"]["verge_w"] + 6.0 + rng.uniform(0.0, 3.0))
        g = ctx.site(m, q, yaw, tol=0.8)
        if g is None:
            continue
        q[1] = g
        if ctx.add(m, q, yaw) and k % 3 == 1:
            ctx.add(boxes[(k + 1) % len(boxes)], q + UP * ctx.model_size(m)[1], yaw + rng.uniform(-0.1, 0.1),
                    ground=False)
    for k, i in enumerate(quay[4::14]):
        q = ctx.side(i, 1, t.styles["quay"]["verge_w"] + 2.0)
        if math.hypot(q[0] - CRANE_SPOT[0], q[2] - CRANE_SPOT[2]) < 34.0:
            continue
        crate = "props_junk/wood_crate001a"
        g = ctx.site(crate, q, 0.4, tol=0.3)
        if g is not None:
            q[1] = g
            if ctx.add(crate, q, 0.4) and k % 2:
                ctx.add(crate, q + UP * ctx.model_size(crate)[1], 0.7, ground=False)


def _seagulls(ctx, count=10):
    """Circles over open water off the coast for the seagulls BackgroundLife flies: [x, y, z,
    radius] each, clear of the land and the roads (the birds bob 3 m), spread along the whole shore
    from the headland to the east cliffs: each circle 110 m from the others, the samples tried from
    every part of the lap in turn so the first ones found do not crowd one bay."""
    t = ctx.trk
    out = []
    ang = np.linspace(0, 2 * np.pi, 24, endpoint=False)
    order = [i for k in range(9) for i in range(k * 3, t.n, 27)]
    for i in order:
        if len(out) == count:
            break
        rad = 26.0 + (len(out) % 4) * 6.0
        for off in (50.0, 80.0, 120.0, 170.0):
            c = t.pos[i] + t.flat_right[i] * (t.width[i] / 2 + off)
            if t.pos[i][1] > 12.0:
                c = t.pos[i] - t.flat_right[i] * (t.width[i] / 2 + off + 60.0)
            ring = [(c[0] + math.cos(a) * rad, c[2] + math.sin(a) * rad) for a in ang] + [(c[0], c[2])]
            if (ctx.road_gap_to(c) > rad + 25.0 and all(ctx.ground(x, z) < SEA_Y - 1.0 for x, z in ring)
                    and all(math.hypot(c[0] - o[0], c[2] - o[2]) > 110.0 for o in out)):
                out.append([round(float(c[0]), 2), SEA_Y + 9.0 + (len(out) % 4) * 3.0, round(float(c[2]), 2), rad])
                break
    return out


def _lap_i(t, s):
    """The lap's sample at lap metres s."""
    return int(round(s / t.step)) % t.n


def _fire(ctx, q, size=1.0, smoke=1.0, light=False):
    """A fire for scripts/fx/ruin_fires.gd with its flames at q: `size` scales the flames (1: a burning
    car), `smoke` the column of smoke over it (0 none, 1 a car's) and `light` gives it a flickering
    light (seen at dusk under the headland, not much in the desert's sun)."""
    ctx.fires.append({"pos": [round(float(c), 2) for c in q], "size": round(float(size), 2),
                      "smoke": round(float(smoke), 2), "light": bool(light)})


def _stand(ctx, model, q, yaw, tol=0.6, sink=0.0, **kw):
    """A prop standing on the ground at plan point q, on the lowest ground under its footprint and
    `sink` metres into it (rocks, wrecks and hulls half buried in the sand): its placed entry, or None
    where that ground varies by more than tol or the prop is refused (Ctx.add)."""
    if model not in ctx.models:
        ctx.missing.add(model)
        return None
    q = np.array(q, float)
    g = ctx.site(model, q, yaw, kw.get("scale", 1.0), tol=tol)
    if g is None:
        return None
    q[1] = g - sink
    return ctx.props[-1] if ctx.add(model, q, yaw, **kw) else None


def _centred(ctx, model, c, yaw, scale=1.0):
    """The plan origin that puts a model's box centred on plan point c when it is turned by yaw (most
    big HL2 models are not centred on their origin)."""
    m = ctx.models[model]
    lx = (m["aabb_min"][0] + m["aabb_max"][0]) / 2 * scale
    lz = (m["aabb_min"][2] + m["aabb_max"][2]) / 2 * scale
    cy, sy = math.cos(yaw), math.sin(yaw)
    return np.array([c[0] - lx * cy - lz * sy, c[1], c[2] + lx * sy - lz * cy])


# the wrecks left on the highway: rusted cars and a truck's cab
WRECKS = ["props_vehicles/car001b_hatchback", "props_vehicles/car002b", "props_vehicles/car003b",
          "props_vehicles/car004b", "props_vehicles/car005b", "props_vehicles/truck002a_cab"]


def _highway(ctx, by):
    """Highway 17 as the Combine and the rebels left it: rusted wrecks pushed off onto both sides
    every 44 m or so, 5-12 m past the verge (a pile-up of two here and there, one in three still
    smoking: the gunship's work), out of the start's way; the Combine's roadblock before the bay
    bridge shoved onto the inland verge with its burnt-out APC; a rebel barricade of junk and their
    truck at the east end; pylons striding over the hills inland."""
    t = ctx.trk
    rng = ctx.rng
    hw = [i for i in sorted(by.get("highway", [])) if 90.0 < t.s[i] < t.length - 90.0]
    every = int(round(44.0 / t.step))
    for k, i in enumerate(hw[3::every]):
        sgn = -1 if k % 3 == 1 else 1
        for n in range(1 + (k % 4 == 2)):
            m = WRECKS[int(rng.integers(0, len(WRECKS)))]
            j = t.wrap(i + n * 3)
            past = t.styles[t.style[j]].get("verge_w", 4.0) + rng.uniform(5.0, 12.0) + n * 3.0
            yaw = ctx.yaw_along(m, t.fwd[j]) + rng.uniform(-0.8, 0.8)
            p = _stand(ctx, m, ctx.side(j, sgn, past), yaw, tol=0.9, sink=0.05)
            if p is not None and k % 3 == 0 and n == 0:
                _fire(ctx, np.array(p["pos"]) + UP * 0.9, size=0.55, smoke=1.0)
    # the roadblock before the bay bridge: its barriers shoved aside, the APC that held it burnt out
    i = _lap_i(t, 300.0)
    p = _stand(ctx, "combine_apc_destroyed_gib01", ctx.side(i, 1, 17.0), ctx.yaw_facing(t.fwd[i]) + 0.6, tol=1.0)
    if p is not None:
        _fire(ctx, np.array(p["pos"]) + UP * 1.6, size=0.8, smoke=2.0)
    for s, past, m, turn in ((322.0, 9.5, "props_combine/combine_barricade_tall01a", 0.35),
                             (327.0, 10.5, "props_combine/combine_barricade_med01a", -0.25),
                             (332.0, 9.0, "props_combine/combine_barricade_tall01a", 0.6),
                             (338.0, 11.0, "props_combine/combine_barricade_short01a", 1.3),
                             (344.0, 12.0, "props_combine/combine_light001a", 2.2)):
        i = _lap_i(t, s)
        _stand(ctx, m, ctx.side(i, 1, past), ctx.yaw_front(m, -t.flat_right[i]) + turn, tol=0.8)
    # the rebels' barricade at the east end: junk, drums, tyres, their truck
    for s, past, m, turn in ((2392.0, 9.0, "props_vehicles/truck001a", 0.3),
                             (2402.0, 8.0, "props_wasteland/barricade002a", 0.0),
                             (2405.0, 8.5, "props_wasteland/barricade002a", 0.4),
                             (2408.0, 9.0, "props_c17/oildrum001", 0.0),
                             (2409.5, 10.0, "props_borealis/bluebarrel001", 0.0),
                             (2412.0, 8.5, "props_vehicles/tire001a_tractor", 0.9),
                             (2415.0, 9.5, "props_junk/wood_pallet001a", 0.2),
                             (2418.0, 8.0, "props_wasteland/barricade001a", -0.3)):
        i = _lap_i(t, s)
        yaw = (ctx.yaw_along(m, t.fwd[i]) if "truck" in m else ctx.yaw_front(m, -t.flat_right[i])) + turn
        _stand(ctx, m, ctx.side(i, 1, past), yaw, tol=0.6)
    # pylons over the hills inland, far off the road
    for s, past in ((140.0, 70.0), (690.0, 75.0), (2470.0, 72.0)):
        i = _lap_i(t, s)
        _stand(ctx, "props_wasteland/powertower01", ctx.side(i, 1, past), ctx.yaw_facing(t.fwd[i]), tol=3.0,
               sink=1.0)


def _valley(ctx):
    """Highway 17's big bridge far up the inlet's valley, across it from rim to rim (a backdrop seen
    from the bay bridge, never reached)."""
    m = "props_wasteland/bridge_low_res"
    if m not in ctx.models:
        ctx.missing.add(m)
        return
    c = np.array([158.0, -3.5, -300.0])
    q = _centred(ctx, m, c, 0.0)
    q[1] = min(ctx.ground(c[0], c[2]), -3.0)
    ctx.add(m, q, 0.0, tag="far")


def _portal_rocks(ctx):
    """Rocks round the headland's portals: three tall ones on each portal's lid against the step up to
    the bore's higher lid (they break its straight edge), and fallen ones on the slopes either side of
    each portal's mouth."""
    t = ctx.trk
    rng = ctx.rng
    rocks = ["props_wasteland/rockcliff06i", "props_wasteland/rockcliff07b", "props_wasteland/rockcliff06d",
             "props_wasteland/rockcliff01c"]
    for ids, _ in t.tube_runs:
        for end, sgn in ((ids[0], -1.0), (ids[-1], 1.0)):
            nb = t.wrap(end + int(sgn))
            if t.kind(nb) != "tunnel":
                continue
            st = t.styles[t.style[nb]]
            low = t.pos[nb][1] + t.height[nb] + st.get("cover", 0.0) - 0.3
            fr = t.flat_right[nb]
            for lat in (-7.0, 0.0, 7.0):
                q = t.pos[end] + t.fwd[end] * sgn * 2.8 + fr * lat
                q[1] = low
                ctx.add(rocks[0], q, rng.uniform(0, 6.28), ground=False)
            # the portal's mouth: its first sample on the open road side
            j = nb
            while t.kind(t.wrap(j + int(sgn))) == "tunnel":
                j = t.wrap(j + int(sgn))
            for side in (-1, 1):
                for k, past in enumerate((12.0, 18.0)):
                    q = ctx.side(t.wrap(j + int(sgn) * 2), side, past)
                    _stand(ctx, rocks[1 + (k + side) % 3], q, rng.uniform(0, 6.28), tol=8.0, sink=1.2)


def _harbour(ctx):
    """The harbour off the quay: a trawler moored out of the crane's reach, the old jetty's pilings
    off the quay's west end, an idle dock crane on the apron's east end (its boom out over the water,
    90 m from the working one), buoys and the inlet mouth's channel markers."""
    rng = ctx.rng
    # the trawler, east of the crane's reach, its hull's draft 3 m in the water
    m = "props_wasteland/boat_fishing01a"
    if m in ctx.models:
        yaw = ctx.yaw_along(m, np.array([1.0, 0.0, 0.0])) + 0.12
        q = _centred(ctx, m, np.array([118.0, 0.0, 336.0]), yaw)
        q[1] = SEA_Y - 3.0
        ctx.add(m, q, yaw, ground=False)
    # the old jetty's pilings
    for z in (316.0, 324.0, 332.0, 340.0):
        q = np.array([-22.0 + rng.uniform(-0.6, 0.6), 0.0, z])
        if ctx.ground(q[0], q[2]) < SEA_Y - 2.0:
            q[1] = ctx.ground(q[0], q[2])
            ctx.add("props_docks/piling_cluster01a", q, rng.uniform(0, 6.28), ground=False)
    # the idle crane: its tower on the apron's east end, its body turned to the sea
    q = np.array([134.0, 0.0, 297.5])
    p = _stand(ctx, "cranes/crane_frame", q, 0.0, tol=1.0)
    if p is not None and "cranes/crane_body_lod" in ctx.models:
        top = p["pos"][1] + ctx.models["cranes/crane_frame"]["aabb_max"][1]
        ctx.add("cranes/crane_body_lod", [q[0], top, q[2]], math.pi + 0.25, tag="far", base=False, ground=False)
    # buoys bobbing off the coast and the inlet mouth's channel markers
    for x, z in ((25.0, 352.0), (78.0, 372.0), (165.0, 360.0), (300.0, 345.0), (440.0, 342.0), (590.0, 338.0),
                 (-120.0, 410.0), (740.0, 330.0)):
        if ctx.ground(x, z) < SEA_Y - 1.5:
            ctx.add("props_wasteland/buoy01", [x, SEA_Y - 0.4, z], rng.uniform(0, 6.28), tag="float", ground=False)
    for x, z in ((150.0, 318.0), (232.0, 322.0)):
        if ctx.ground(x, z) < SEA_Y - 1.0:
            ctx.add("props_docks/channelmarker01a", [x, ctx.ground(x, z), z], 0.0, ground=False)


def _rebel_camp(ctx):
    """The rebels' camp behind the quay road's east end, out of the crane's way: their truck, a fire in a
    drum, crates, barrels, pallets, a table and benches (the crowd round it: crowds()). Returns its
    centre and the road sample it faces."""
    t = ctx.trk
    i = _lap_i(t, CAMP_S)
    f = t.fwd[i] * np.array([1.0, 0.0, 1.0])
    f /= np.linalg.norm(f)
    out = -t.flat_right[i]
    c = ctx.side(i, -1, 17.0)
    c[1] = ctx.ground(c[0], c[2])

    def at(a, o):
        return c + f * a + out * o

    road = ctx.yaw_facing(-out)
    truck = "props_vehicles/truck001a"
    for m, a, o, yaw in ((truck, -9.0, 3.0, ctx.yaw_along(truck, f) + 0.2),
                         ("props_c17/oildrum001", 0.0, 0.0, 0.0),
                         ("props_junk/wood_crate001a", 4.5, 3.5, 0.3),
                         ("props_junk/wood_crate002a", 5.5, 1.5, 1.1),
                         ("props_junk/wood_crate001a", 4.0, 5.2, 0.8),
                         ("props_borealis/bluebarrel001", 6.5, 4.5, 0.0),
                         ("props_borealis/bluebarrel001", 7.2, 3.6, 0.0),
                         ("props_junk/wood_pallet001a", -3.5, 5.0, 0.4),
                         ("props_vehicles/tire001a_tractor", -4.5, -2.5, 1.2),
                         ("props_wasteland/cafeteria_table001a", 1.5, 4.5, road + 1.57),
                         ("props_c17/bench01a", 1.5, 6.2, road + 1.57),
                         ("props_junk/cardboard_box001a", -1.5, 6.5, 0.6)):
        _stand(ctx, m, at(a, o), yaw, tol=0.6)
    _fire(ctx, c + UP * 1.3, size=0.4, smoke=0.6, light=True)
    return c, i


# antlion hills out on the dunes and the beach (plan x, z, scale): inside the boardwalk's swing, on the
# dunes inland of it and on the beach under the east cliff, all far off the roads and their sand bands
ANTLION_HILLS = [(462.0, 256.0, 1.0), (318.0, 222.0, 0.8), (596.0, 214.0, 0.9), (440.0, 168.0, 0.65),
                 (505.0, 262.0, 0.5), (690.0, 214.0, 0.7)]


def _beach(ctx, by):
    """The antlion beach: antlion hills, rocks and half-buried wrecks out on the dunes (beyond the sand
    the antlions come up out of), a rowing boat or two; under the east cliff a trawler beached on its
    keel at the water's edge."""
    t = ctx.trk
    rng = ctx.rng
    for x, z, sc in ANTLION_HILLS:
        if ctx.ground(x, z) > SEA_Y + 1.5 and ctx.road_gap_to([x, 0.0, z]) > 20.0:
            _stand(ctx, "props_wasteland/antlionhill", [x, 0.0, z], rng.uniform(0, 6.28), tol=2.5, sink=0.4,
                   scale=sc)
    # rocks and wrecks on the dunes inland of the boardwalk, 20-45 m past its edge
    stuff = ["props_wasteland/rockgranite01a", "props_wasteland/rockgranite04a", "props_wasteland/rockgranite02a",
             "props_vehicles/car002b", "props_wasteland/rockgranite01a", "props_vehicles/car004b"]
    ids = sorted(by.get("boards", []))
    for k, i in enumerate(ids[2::int(round(26.0 / t.step))]):
        m = stuff[k % len(stuff)]
        q = ctx.side(i, -1, rng.uniform(20.0, 45.0))
        if ctx.ground(q[0], q[2]) < SEA_Y + 1.0 or ctx.road_gap_to(q) < 18.0:
            continue
        sink = 0.6 if "car0" in m else 0.4
        _stand(ctx, m, q, rng.uniform(0, 6.28), tol=1.2, sink=sink)
    # the beached trawler at the water's edge under the east cliff
    m = "props_wasteland/boat_fishing02a"
    if m in ctx.models:
        yaw = ctx.yaw_along(m, np.array([1.0, 0.0, -0.25])) + math.pi
        q = _centred(ctx, m, np.array([724.0, 0.0, 304.0]), yaw)
        if ctx.road_gap_to(q) > 12.0:
            lo, _hi = ctx.ground_span(m, q, yaw)
            q[1] = lo - 1.0
            ctx.add(m, q, yaw, ground=False)


def _lighthouse(ctx):
    """A lighthouse on the east cliff's point, seen ahead all the way along the beach: a white tower on
    the ridge beyond the cliff road's rail, a gallery with a railing and the lantern on top."""
    t = ctx.trk
    best = None
    for s in (2280.0, 2292.0, 2304.0):
        i = _lap_i(t, s)
        for past in (24.0, 27.0, 30.0, 33.0):
            q = ctx.side(i, 1, past)
            gs = [ctx.ground(q[0] + dx, q[2] + dz) for dx in (-3.0, 0.0, 3.0) for dz in (-3.0, 0.0, 3.0)]
            if max(gs) - min(gs) > 2.5 or ctx.road_gap_to(q) < 18.0:
                continue
            if best is None or min(gs) > best[1]:
                best = (q, min(gs))
    if best is None:
        print("  lighthouse: no spot on the east point")
        return
    q, g = best
    wall = ctx.mats.hl2("concrete/concretewall064a")
    rail = ctx.mats.hl2("metal/metalrail013a")
    h, r = 15.0, 2.4
    ctx.cylinder(wall, [q[0], g - 1.5, q[2]], r, h + 1.5, segs=20)
    ctx.box(wall, [q[0], g + h - 0.1, q[2]], [r * 2.0 - 0.1, 0.2, r * 2.0 - 0.1], 0.0, kind="deco")
    ctx.box(wall, [q[0], g + h + 0.2, q[2]], [r * 2 + 1.8, 0.4, r * 2 + 1.8], 0.0)
    e = r + 0.85
    sides = ((e, 0.0, 0.06, e * 2), (-e, 0.0, 0.06, e * 2), (0.0, e, e * 2, 0.06), (0.0, -e, e * 2, 0.06))
    for dx, dz, sx, sz in sides:
        ctx.box(rail, [q[0] + dx, g + h + 1.4, q[2] + dz], [sx, 0.06, sz], 0.0, kind="deco", rep=1.0)
        ctx.box(rail, [q[0] + dx, g + h + 0.9, q[2] + dz], [sx, 0.04, sz], 0.0, kind="deco", rep=1.0)
    for dx in (-e, e):
        for dz in (-e, e):
            ctx.box(rail, [q[0] + dx, g + h + 0.9, q[2] + dz], [0.08, 1.0, 0.08], 0.0, kind="deco", rep=1.0)
    lamp = "props_wasteland/lighthouse_fresnel_light_base"
    if ctx.add(lamp, [q[0], g + h + 0.4, q[2]], 0.6, ground=False):
        ctx.light([q[0], g + h + 4.5, q[2]], [1.0, 0.93, 0.72], 36.0, 2.2)
    print("  lighthouse at (%.0f, %.1f, %.0f)" % (q[0], g, q[2]))


# sea stacks offshore (plan x, z, scale): the coast going on out to sea, seen past the beach and the docks
SEA_STACKS = [(-170.0, 520.0, 1.8), (110.0, 575.0, 2.4), (380.0, 610.0, 2.0), (650.0, 540.0, 2.6),
              (930.0, 420.0, 2.2), (1040.0, 160.0, 1.9)]


def _sea_stacks(ctx):
    """Rock stacks standing out of the sea well offshore, their feet under the water (far: never
    reached)."""
    rng = ctx.rng
    for k, (x, z, sc) in enumerate(SEA_STACKS):
        g = ctx.ground(x, z)
        if g > SEA_Y - 3.0:
            continue
        m = ("props_wasteland/rockcliff_cluster01b", "props_wasteland/rockcliff_cluster02a",
             "props_foliage/rock_coast02a")[k % 3]
        ctx.add(m, [x, g - 2.0, z], rng.uniform(0, 6.28), scale=sc, tag="far", ground=False)


def decorate(ctx):
    t = ctx.trk
    rng = ctx.rng
    by = _by_style(t)
    # fires and smoke (scripts/fx/ruin_fires.gd): burning wrecks on the highway, the rebels' camp fire
    ctx.fires = []
    _deck_flares(ctx, by, ("baybridge", "woodbridge"))
    # (onto the tidal pool's bridge a shorter one: a kart out on the sand past it reaches the pool's
    # shore before it has been behind the rail for Kart.BEHIND_WALL seconds)
    _deck_flares(ctx, by, ("creek",), back=22.0)
    _portal_flares(ctx, by)
    _pipe_caps(ctx)
    _bore_lids(ctx)
    _quay_wall(ctx)
    _boardwalk(ctx, sorted(by.get("boards", [])))
    _docks(ctx, by)
    ctx.camp = _rebel_camp(ctx)
    _harbour(ctx)
    _highway(ctx, by)
    _valley(ctx)
    _portal_rocks(ctx)
    _beach(ctx, by)
    _lighthouse(ctx)
    _sea_stacks(ctx)
    # the coast's rocks at the foot of the cliffs on the sea side of the cliff roads, out of reach
    rocks = ["props_wasteland/rockcliff01c", "props_wasteland/rockcliff06d", "props_wasteland/rockcliff07b",
             "props_wasteland/rockcliff06i"]
    for k, i in enumerate(by.get("cliffroad", [])[3::11]):
        q = ctx.side(i, 1, t.styles["cliffroad"]["verge_w"] + rng.uniform(12.0, 26.0))
        g = ctx.ground(q[0], q[2])
        if g > t.pos[i][1] - 4.0 or g < SEA_Y - 3.0:
            continue
        q[1] = g - 0.5
        ctx.add(rocks[k % len(rocks)], q, rng.uniform(0, 6.28))
    # highway poles on the inland side, clear of the junctions and the crane
    hw = sorted(by.get("highway", []) + by.get("start", []))
    for i in hw[10::28]:
        q = ctx.side(i, 1, t.styles["highway"]["verge_w"] + 3.0)
        if ctx.road_gap_to(q) < 3.0:
            continue
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_c17/utilitypole01a", q, ctx.yaw_facing(t.fwd[i]))
    # driftwood and an upturned boat or two on the beach, well off the boardwalk (past the sand the
    # antlions come up out of)
    drift = ["props_foliage/driftwood_02a", "props_foliage/driftwood_clump_01a", "props_wasteland/boat_01"]
    for k, i in enumerate(sorted(by.get("boards", []) + by.get("creek", []))[5::11]):
        sgn = -1 if k % 2 else 1
        q = ctx.side(i, sgn, 1.2 + rng.uniform(18.0, 34.0))
        if ctx.road_gap_to(q) < 10.0:
            continue
        g = ctx.ground(q[0], q[2])
        if g < SEA_Y + 0.3:
            continue
        q[1] = g - 0.2
        ctx.add(drift[k % len(drift)], q, rng.uniform(0, 6.28))
    TRACK["seagulls"] = _seagulls(ctx)


def _stones(ctx):
    """The stepping stones: the branch's sand strip becomes off-road (the verge's mesh: wheels on it
    are on sand, like the terrain), and boards of planks lie across it STONE_BOARD long with
    STONE_GAP of sand between them, from nose to nose (in the shared stretches the boardwalk's own
    planks are the road)."""
    t = ctx.trk
    st = t.styles["stones"]
    sand = st["road"]
    road, verge = ctx.meshes["road"], ctx.meshes["verge"]
    part = road.parts.pop(sand, None)
    if part is not None:
        dst = verge.part(sand)
        base = sum(len(a) for a in dst["p"])
        for key in ("p", "n", "uv", "c"):
            dst[key].extend(part[key])
        dst["i"].extend([np.asarray(i) + base for i in part["i"]])
    planks = ctx.mats.hl2("wood/woodfloor005a")
    beam = ctx.mats.hl2("wood/woodbeam001a")
    free = np.flatnonzero(~t.junction & ~t.gap)
    if not len(free):
        return []
    s0, s1 = t.s[free[0]] + 2.0, t.s[free[-1]] - 2.0
    boards = []
    s = s0
    def at(key, u):
        """The branch's per-sample vectors (or widths) at metres u, between its samples."""
        a = getattr(t, key)
        return np.stack([np.interp(u, t.s, a[:, c]) for c in range(3)], 1) if a.ndim == 2 else np.interp(u, t.s, a)

    while s + STONE_BOARD <= s1:
        # the board's ends and middle, wherever they fall between the samples
        u = np.linspace(s, s + STONE_BOARD, 3)
        up, right, fr, fw = at("up", u), at("right", u), at("flat_right", u), at("fwd", u)
        hw = at("width", u) / 2 + 0.3
        top = at("pos", u) + up * 0.05
        L, R = top - right * hw[:, None], top + right * hw[:, None]
        v = (u - s) / 4.0
        road.strip(planks, L, R, -hw / 4.0, hw / 4.0, v, up, up)
        for side, E in ((-1, L), (1, R)):
            low = E - UP * 0.25
            rf = fr * side
            if side > 0:
                ctx.meshes["side"].strip(beam, E, low, 0.0, 0.06, v, rf, rf)
            else:
                ctx.meshes["side"].strip(beam, low, E, 0.06, 0.0, v, rf, rf)
        for k, sgn in ((0, -1.0), (-1, 1.0)):
            a, b = L[k], R[k]
            q = [a, b, b - UP * 0.25, a - UP * 0.25]
            face(ctx.meshes["side"], beam, q, fw[k] * sgn, plane_uv(q, a, (b - a) / np.linalg.norm(b - a), 4.0))
        boards.append((round(float(s), 1), round(float(s + STONE_BOARD), 1)))
        s += STONE_BOARD + STONE_GAP
    return boards


def decorate_branch(ctx, spec):
    t = ctx.trk
    if spec["id"] == "stepping_stones":
        boards = _stones(ctx)
        if boards:
            print("  stepping stones: %d boards, u %.0f-%.0f" % (len(boards), boards[0][0], boards[-1][1]))
        # the tide line seaward of the stones: driftwood, a rowing boat dragged up, a rock or two
        rng = ctx.rng
        wash = ["props_foliage/driftwood_02a", "props_wasteland/rockgranite02a", "props_foliage/driftwood_clump_01a",
                "props_wasteland/boat_01", "props_canal/boat001a", "props_wasteland/rockgranite03a"]
        free = [i for i in range(t.n) if not t.junction[i] and not t.gap[i]]
        for k, i in enumerate(free[6::int(round(24.0 / t.step))]):
            m = wash[k % len(wash)]
            q = ctx.side(i, 1, rng.uniform(5.0, 10.0))
            g = ctx.ground(q[0], q[2])
            if g < SEA_Y + 0.3 or ctx.road_gap_to(q) < 4.0:
                continue
            _stand(ctx, m, q, ctx.yaw_along(m, t.fwd[i]) + rng.uniform(-0.6, 0.6), tol=1.0, sink=0.15)
    elif spec["id"] == "old_bridge":
        by = _by_style(t)
        _deck_flares(ctx, by, ("oldbridge",), back=24.0)
        # the fallen middle span in the water under the gap, broken into great slabs of its deck lying
        # in the channel and on its banks, rebar out of them (seen, never hit: a kart that falls short
        # drops past them into the water)
        slab = "props_debris/concrete_section128floor001a"
        for a, b in t.gaps[:1]:
            if slab not in ctx.models:
                ctx.missing.add(slab)
                break
            for k, (f_along, lat, sc, turn) in enumerate(((0.2, -3.0, 2.6, 0.35), (0.5, 2.5, 3.0, -0.2),
                                                          (0.8, -1.0, 2.4, 0.6))):
                i = a + int(round((b - a) * f_along))
                q = t.pos[i] + t.flat_right[i] * lat
                g = ctx.ground(q[0], q[2])
                q[1] = max(g, SEA_Y - 0.25) - 0.05
                yaw = ctx.yaw_facing(t.fwd[i]) + turn
                ctx.add(slab, q, yaw, scale=sc, tag="deco", ground=False)
                if k != 1:
                    ctx.add("props_debris/rebar_cluster002a", q + UP * 0.6 + t.fwd[i] * 2.0, yaw + 1.2, tag="deco",
                            ground=False)
        # the fallen span's rubble in the river under the gap, and the broken ends' rebar
        for a, b in t.gaps:
            for i in (a - 1, b):
                i = min(max(i, 0), t.n - 1)
                q = t.pos[i].copy()
                q[1] = ctx.ground(q[0], q[2])
                rubble = ("props_debris/concrete_debris256pile001a", "props_debris/concrete_floorpile01a")
                for k, m in enumerate(rubble):
                    ctx.add(m, q + t.flat_right[i] * (k * 5.0 - 2.5), ctx.rng.uniform(0, 6.28), tag="far")


# ---------------------------------------------------------------- spectators
def _open(ctx, i):
    t = ctx.trk
    return t.kind(i) == "open" and not t.gap[i] and not t.pit[i]


def crowds(ctx):
    """Rebels and refugees: a rally at the start on the highway's inland side, groups along the
    docks by the containers and up on two of them, the rebels round their camp fire, little groups
    on the dunes above the beach (out past the sand the antlions come up out of) and up the cliff
    roads, the rebels behind their barricade on the highway, and the eggs."""
    t = ctx.trk
    rng = ctx.crowd_rng
    # the start: rebels on the inland side of the highway (the other side is the cliff)
    ids = [i for i in ctx.lap_ids(-50.0, 50.0) if _open(ctx, i)]
    for ch in ctx.chunks(ids, int(30 / t.step), int(30 / t.step)):
        gid = ctx.crowd_group(ch[len(ch) // 2], 1, "line", "rebel", tags=["start"])
        for role, lo, hi, every, dodge in (("rebel", 2.5, 3.5, 2.0, True), ("refugee", 4.0, 5.5, 2.5, False)):
            ctx.crowd_line(gid, ch, 1, every, lambda i, s, a=lo, b=hi: ctx.shoulder_spot(i, s, a, b), role,
                           mood="excited" if dodge else "fan", chance=0.8, dodge=dodge, dy=(-1.5, 3.0))
    # the docks: rebels along the land side of the quay road
    quay = [i for i in range(t.n) if t.style[i] == "quay" and _open(ctx, i)]
    for ch in ctx.chunks(quay, int(40 / t.step), int(50 / t.step)):
        gid = ctx.crowd_group(ch[len(ch) // 2], -1, "line", "rebel", tags=["docks"])
        ctx.crowd_line(gid, ch, -1, 3.0, lambda i, s: ctx.shoulder_spot(i, s, 2.5, 4.5), "rebel", mood="fan",
                       chance=0.8, dy=(-1.0, 2.0))
    # ... a few up on two of the containers, cheering
    boxes = [p for p in ctx.props if p["model"].startswith("props_wasteland/cargo_container")]
    for p in boxes[1::3][:2]:
        i = ctx._nearest(np.array(p["pos"], float))
        gid = ctx.crowd_group(i, -1, "cluster", "rebel", tags=["docks"])
        ctx.on_top(p, 3, "rebel", mood="excited", gid=gid)
    # the rebels round their camp fire, turned to the road
    camp = getattr(ctx, "camp", None)
    if camp is not None:
        c, i = camp
        gid = ctx.crowd_group(i, -1, "cluster", "rebel", tags=["camp"], watch=[t.s[i] - 40.0, t.s[i] + 20.0])
        ctx.crowd_cluster(gid, c, 6, 5.0, "rebel", t.pos[i] + UP, mood="fan", ref_y=t.pos[i][1], dy=(-1.0, 3.0),
                          margin=3.0)
    # the beach: refugees in little groups on the dunes inland of the boardwalk, out past the sand the
    # antlions come up out of
    beach = [i for i in range(t.n) if t.style[i] == "boards" and _open(ctx, i) and not t.junction[i]]
    for i in beach[8::max(1, len(beach) // 6)]:
        c = ctx.shoulder_spot(i, -1, 18.0, 24.0)
        gid = ctx.crowd_group(i, -1, "cluster", "refugee", tags=["beach"])
        ctx.crowd_cluster(gid, c, int(rng.integers(3, 6)), 3.0, "refugee", t.pos[i] + UP, mood="fan",
                          ref_y=t.pos[i][1], dy=(-1.0, 3.5), margin=6.0)
    # the rebels behind their barricade at the highway's east end
    i = _lap_i(t, 2408.0)
    gid = ctx.crowd_group(i, 1, "cluster", "rebel", tags=["barricade"])
    ctx.crowd_cluster(gid, ctx.side_point(i, 1, 13.5), 5, 3.0, "rebel", t.pos[i] + UP, mood="excited",
                      ref_y=t.pos[i][1], dy=(-1.0, 3.0), margin=4.0)
    # the cliff roads: a few on the inland side
    cliff = [i for i in range(t.n) if t.style[i] == "cliffroad" and _open(ctx, i)]
    for ch in ctx.chunks(cliff, int(60 / t.step), int(10 / t.step)):
        i = ch[len(ch) // 2]
        gid = ctx.crowd_group(i, -1, "cluster", "rebel", tags=["cliff"])
        ctx.crowd_cluster(gid, ctx.shoulder_spot(i, -1, 2.0, 5.0), 3, 2.5, "rebel", t.pos[i] + UP,
                          ref_y=t.pos[i][1], dy=(-0.5, 3.0), margin=4.0)
    eggs(ctx)


def crowds_branch(ctx, spec):
    """Rebels on the far end of the old bridge watching the jump, refugees on the dune by the
    stepping stones."""
    t = ctx.trk
    if spec["id"] == "old_bridge":
        for a, b in t.gaps:
            i = min(b + int(40 / t.step), t.n - 1)
            while i < t.n - 1 and t.kind(i) != "open":
                i += 1
            if t.kind(i) != "open":
                continue
            gid = ctx.crowd_group(i, 1, "cluster", "rebel", tags=["jump"], watch=[t.s[a] - 20.0, t.s[i] + 10.0])
            ctx.crowd_cluster(gid, ctx.shoulder_spot(i, 1, 2.5, 4.5), 7, 3.0, "rebel", t.pos[b] + UP,
                              mood="excited", ref_y=t.pos[i][1], dy=(-1.5, 2.5), margin=4.0)
    elif spec["id"] == "stepping_stones":
        # refugees on the dune inside the boardwalk's swing, watching who dares the stones
        i = int(round(190.0 / t.step))
        if 0 < i < t.n - 1:
            gid = ctx.crowd_group(i, -1, "cluster", "refugee", tags=["stones"], watch=[t.s[i] - 50.0, t.s[i] + 40.0])
            ctx.crowd_cluster(gid, ctx.side_point(i, -1, 20.0), 6, 4.0, "refugee", t.pos[i] + UP, mood="excited",
                              ref_y=t.pos[i][1], dy=(-1.0, 3.0), margin=6.0)


def eggs(ctx):
    t = ctx.trk
    # the G-Man on the cliff top above the east climb, watching the karts come up from the beach
    g = ctx.gman_spot(2120.0, 2300.0)
    if g is not None:
        ctx.egg("gman", pos=g["pos"], yaw=g["yaw"], s=g["s"], model="gman_high", window=g["window"], chance=0.4)
    # seagulls pecking on the beach, the dunes and the apron, away from the roads
    flocks = 0
    for s0, sgn in ((1450.0, 1), (1700.0, 1), (1760.0, -1), (1990.0, -1), (2000.0, 1), (2050.0, 1)):
        if flocks == 4:
            break
        i = int(s0 / t.step) % t.n
        for d in (24.0, 30.0, 45.0, 60.0):
            c = ctx.side_point(i, sgn, d)
            if ctx.road_gap_xz(c) > 12.0 and ctx.ground(c[0], c[2]) > SEA_Y + 0.4 and ctx.in_prop(c, 1.5) is None:
                c[1] = ctx.ground(c[0], c[2])
                flocks += ctx.egg("birds", species="seagull", center=c, radius=4.0, count=7)
                break
    # Gnome Chompski on a crate at the rebels' camp (or else on the docks' crates)
    crates = [p for p in ctx.props if p["model"] == "props_junk/wood_crate001a"]
    camp = getattr(ctx, "camp", None)
    if camp is not None:
        crates.sort(key=lambda p: math.hypot(p["pos"][0] - camp[0][0], p["pos"][2] - camp[0][2]))
    for p in crates:
        q = np.array(p["pos"], float)
        q[1] += ctx.models[p["model"]]["aabb_max"][1]
        # (nothing else stacked on it: the crate itself does not count)
        k = next(j for j, o in enumerate(ctx.props) if o is p)
        if ctx.in_prop(q + [0.0, 0.1, 0.0], 0.0, ignore=k) is None and ctx.egg("gnome", pos=q, yaw=0.0):
            break
