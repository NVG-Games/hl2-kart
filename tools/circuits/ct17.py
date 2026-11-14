"""CT17: City 17 in ruins, a figure-8 of about 2.6 km.

The station plaza under the Breencasts, down into a cutting under the old-town flyover, the
underpass below the railway embankment, up onto the ruined viaduct over the canal (its jerseys
torn out in places, one span collapsed: the road runs down its sagging slab and up the next),
down into the rail yard with its jump and a level crossing, the canal corner over a bridge, the
Combine checkpoint, the old-town switchbacks and up over the flyover to the boulevard toward the
Citadel: in through a hole blown in a block's facade, across its ground floor and out through
another, up a ramp of rubble onto the long roof of a collapsed building and down its fallen floor
slab, back to the plaza.

Two branches: a jump straight over the canal instead of the canal corner (it takes speed: short
of the far bank you swim) and the rooftops of the old town instead of its switchbacks, a long way
over the roofs: a ramp spiralling up off the hill road, three jumps over alleys, a run along the
roofs beside the south street and down a collapsed floor slab into it (no boost needed: about as
quick as the switchbacks). A train crosses the yard, floor turrets guard the checkpoint and three
striders walk beside the viaduct, the canal corner and the boulevard, firing their warp cannons
and machine guns at the karts; what is left of the city turns out to watch the race.

The city is in ruins, as in Half-Life 2's "Anticitizen One" and "Follow Freeman": heaps of
broken concrete under the collapsed span, beside the ramp of rubble and round craters, broken
edges round the holes blown in the block, burnt-out cars and an APC, rubble shutting the side
streets, gutted and collapsed blocks and the destroyed dome on the skyline, most street lamps
dead, and fires and columns of smoke all over it (data["fires"], scripts/fx/ruin_fires.gd).
"""
import math

import numpy as np

from crowds import FAR_MODEL
from track_gen import UP, _side_w, _treatment, _unwrap_s, carve, face, noise2, plane_uv, smoothstep, wall_strip

# (x, y, z, width, style, flags): the start first. The west lobe runs clockwise seen from above
# (the plaza, the cutting under the flyover, the underpass), the east lobe counter-clockwise (the
# viaduct, the rail yard, the canal corner, the checkpoint, the old town, the flyover)
CTRL = [
    (0, 0, 0, 24, "plaza"), (105, 0, 0, 24, "plaza"), (170, -1.0, 10, 20, "avenue"),
    (222, -4.0, 26, 18, "cut", {"height": 4.6}), (268, -5.0, 38, 18, "cut", {"height": 4.6}),
    (318, -5.5, 50, 18, "underpass"),
    # the ruined viaduct: out of the underpass's hollow up onto the broken elevated road, over the
    # canal, down the collapsed span's slab and up the far one, then down into the yard
    (362, -5.0, 60, 17, "viaramp"), (394, 0.0, 80, 17, "viaramp"), (424, 4.0, 102, 17, "viaduct"),
    (458, 6.2, 116, 17, "viaduct"), (474, 6.2, 119, 17, "span"), (500, 2.2, 119, 17, "span"),
    (522, 6.2, 112, 17, "viaduct"), (542, 6.0, 98, 17, "viaduct"), (550.5, 4.4, 85.5, 17.5, "viaramp"),
    (558, 2.6, 72, 18, "viaramp"),
    (566, 0, 40, 20, "yard"),
    # (a long kicker: a kart coming at it fast is not thrown high off it)
    (570, 0, 4, 21, "yard", {"gap": True, "gap_span": (0.025, 0.17), "ramp_lift": 1.4, "ramp_len": 24}),
    (584, 0, -82, 20, "yard"),
    (601, 0, -140, 18, "avenue"),
    # north over the canal on its bridge, round the corner and back west along the canal's far side
    (619, 0, -170, 18, "avenue"), (630, 0.4, -198, 16, "canalbridge"), (635, 0.4, -258, 18, "avenue"),
    (625, 0, -296, 18, "avenue"), (591, 0, -309, 17, "approach"),
    # the checkpoint climbs onto the old town's hill
    (480, 0, -300, 18, "checkpoint"), (420, 0, -300, 18, "checkpoint"),
    # the old town: west along the hill, a U-turn east down into the middle street, a wider U-turn
    # west (the switchbacks, each hairpin one steady arc), then round south to the flyover. The
    # rooftops climb off the hill road (5.5 m to the roofs) and come down beside the south street
    (330, 3.5, -298, 15, "old"), (272, 3.5, -298, 15, "old"),
    (236, 3.5, -298, 15, "switchback"), (219, 2.92, -293.4, 15, "switchback"), (206.6, 2.33, -281, 15, "switchback"),
    (202, 1.75, -264, 15, "switchback"), (206.6, 1.17, -247, 15, "switchback"), (219, 0.58, -234.6, 15, "switchback"),
    (236, 0, -230, 15, "switchback"),
    (252, 0, -230, 15, "switchback"), (272, 0, -224.6, 15, "switchback"), (286.6, 0, -210, 15, "switchback"),
    (292, 0, -190, 15, "switchback"), (286.6, 0, -170, 15, "switchback"), (272, 0, -155.4, 15, "switchback"),
    (252, 0, -150, 15, "switchback"),
    (200, 0, -150, 15, "old"), (139.9, 0, -150, 15, "old"),
    (123.8, 0.2, -145.3, 17, "switchback"), (112.7, 0.5, -132.7, 18, "switchback"), (110.2, 0.9, -116.1, 18, "switchback"),
    (116.9, 1.5, -100.7, 18, "switchback"), (146, 2.5, -66, 18, "avenue"),
    # over the plaza road's cutting
    (206, 5.0, -26, 18, "flyover"), (248, 7.0, 32, 18, "flyover"),
    # the boulevard toward the Citadel: in through a hole blown in a block's facade, across its
    # ground floor and out through another, up a ramp of rubble onto the long roof of a collapsed
    # building, along it and down its fallen floor slab, back round to the plaza
    (252, 3.5, 92, 18, "avenue"), (238, 1.2, 120, 18, "avenue"),
    (220, 1.0, 138, 18, "breach"), (196, 1.0, 152, 18, "breach"),
    (170, 1.0, 159, 18, "avenue"), (150, 1.0, 161, 16, "rubble"),
    (114, 8.0, 160, 16, "roofroad"), (98, 8.0, 159.2, 16, "roofroad"), (70, 8.0, 156, 16, "roofroad"),
    (34, 8.0, 146, 16, "roofroad"),
    (12, 6.4, 136, 16, "fallen"),
    (-24, 0.5, 112, 18, "avenue"), (-52, 0, 86, 20, "avenue"),
    (-88, 0, 40, 22, "plaza"), (-78, 0, 6, 24, "plaza"), (-40, 0, 0, 24, "plaza"),
]
CTRL = [c if len(c) > 5 else c + ({},) for c in CTRL]

# the canal's centre line: from the north-east under the corner's bridge, south-west between the
# corner's two legs, under the viaduct and away south
CANAL = [(760.0, -262.0), (601.0, -228.0), (552.0, -216.0), (512.0, -200.0), (484.0, -164.0), (470.0, -110.0),
         (400.0, 68.0), (430.0, 420.0)]
CANAL_HALF = 11.0
WATER = -11.0
FOOTBRIDGE = 1.6  # the footbridges' scale: they span the canal's 36 m from bank top to bank top
# metres a broken railing's unseen wall (_broken_edges) reaches over its whole railing's "col_h":
# with no jersey or parapet to hit first, a kart that hits the edge hard (head-on, at full speed, or
# rammed into it in the pack) rides up the unseen wall, and over one only as tall as the railing's
BROKEN_UP = 1.5

TRACK = {
    "id": "ct17",
    "name": "CT17",
    "ctrl": CTRL,
    # (one on the viaduct's deck before the collapsed span, one on the collapsed building's roof)
    "items": [0.0433, 0.1167, 0.1784, 0.2925, 0.3346, 0.3856, 0.4065, 0.4320, 0.6400, 0.7048, 0.8089, 0.8842],
    # (none on the run to the yard's jump or in the old town, whose hairpins and exit bend a boosted
    # kart runs wide in: the first is out on the boulevard; none before the ramp of rubble, whose top
    # would throw a boosted kart at the roof's parapet: one along the roof)
    "boosts": [0.0286, 0.0781, 0.3926, 0.4691, 0.7257, 0.7836, 0.8668, 0.9505],
    "barrels": [0.1360],
    "vmax": 38.0,
    "offtrack": 40.0,
    "sky": "sky_day01_01",
    "water": {"level": WATER},
    "background": "city17",
    "citadel": [-950, -200, 240, 9.0],
    "gantry": "combine",
    "env": {"fog_begin": 260.0, "fog_end": 2600.0},
    # the jumps' launch speeds under the game's own gravity (project.godot)
    "gravity": 15.24,
}

# the checkpoint stretch starts at this lap metre and the yard jump lands at this one (the hazards
# are placed from them, as on the old layout)
CHECKPOINT_S = 1137.8
YARD_LANDING_S = 686.5
TRACK["hazards"] = [
    # Combine floor turrets on the checkpoint's pavements, between the barricades, facing the oncoming karts
    {"type": "turret", "s": CHECKPOINT_S + 35, "side": -1, "setback": 1.6,
     "zone": [CHECKPOINT_S - 8, CHECKPOINT_S + 40], "model": "combine_turrets/floor_turret", "fallback": "hl1/sentry",
     "scale": 1.4},
    {"type": "turret", "s": CHECKPOINT_S + 91, "side": 1, "setback": 1.6,
     "zone": [CHECKPOINT_S + 48, CHECKPOINT_S + 96], "model": "combine_turrets/floor_turret", "fallback": "hl1/sentry",
     "scale": 1.4},
    {"type": "turret", "s": CHECKPOINT_S + 147, "side": -1, "setback": 1.6,
     "zone": [CHECKPOINT_S + 104, CHECKPOINT_S + 152], "model": "combine_turrets/floor_turret",
     "fallback": "hl1/sentry", "scale": 1.4},
    # a Combine train crosses the rail yard between the jump's landing and the yard's crates
    {"type": "train", "s": YARD_LANDING_S + 46, "angle": 90, "reach": 90,
     "cars": ["props_combine/combinetrain01a", "props_combine/combine_train02a", "props_combine/combine_train02b"],
     "car_axis": ["-x", "z", "z"], "speed": 28, "period": 26, "first": 50, "warn": 4.5},
    # three striders walk their own beats beside the road (scripts/hazards/strider_hazard.gd): at
    # each halt the warp cannon at the nearest kart in view, machine-gun bursts down the road
    # while they walk. Their zones lie 60 m or more apart (a pass through two would share one
    # hit) and clear of the branches' forks and merges. On the inside of the viaduct's bend, on
    # the open ground between it and the rail yard (the karts see it across the deck all round
    # the bend); its zone ends 110 m before the yard jump's lip, so a kart it knocks about has
    # the room to get back up to the jump's speed. (Its metre is the collapsed span's low point:
    # the hazard lint counts a strider more than 4 m under the road at its metre as having no
    # floor, and the deck elsewhere stands 6 m over the ground it walks on)
    {"type": "strider", "s": 525, "zone": [425, 565], "cycle": 11.0, "phase": 3.0,
     "walk": [[440, -1, 20], [500, -1, 24], [555, -1, 22]]},
    # between the canal jump and the avenue to the canal corner, in view from the yard's exit on
    {"type": "strider", "s": 860, "zone": [815, 935], "cycle": 11.0, "phase": 8.0,
     "walk": [{"xz": [592, -165]}, {"xz": [597, -187]}, {"xz": [601, -208]}]},
    # inside the west loop, west of the flyover's way down to the boulevard (seen from the
    # flyover and on toward the breach)
    {"type": "strider", "s": 2060, "zone": [2020, 2110], "cycle": 10.0, "phase": 2.0,
     "walk": [{"xz": [220, 55]}, {"xz": [219, 75]}, {"xz": [214, 95]}]},
]

BRANCHES = [
    # straight over the canal instead of round the corner: speed-gated, short of the far bank you swim
    {"id": "canal_jump", "name": "Canal jump", "kind": "jump", "fork": (585, -92), "merge": (510, -300),
     "ctrl": [(580, 0, -122, 12, "service"), (571, 0, -150, 12, "service"), (569, 0.3, -182, 11, "ramp"),
              (569, 0.5, -204, 11, "ramp", {"gap": True, "gap_span": (0.03, 0.66), "ramp_lift": 2.8, "ramp_len": 18}),
              (566, 0, -248, 12, "avenue"), (561, 0, -264, 12, "avenue"), (549, 0, -282, 12, "avenue"),
              (531, 0, -294, 12, "avenue")],
     "items": [0.32, 0.72], "risk": 0.55, "ai": {"take": 0.65, "min_skill": 0.85}, "respawn": "before",
     "retry_back": 60.0},
    # the long way over the old town's roofs instead of its switchbacks: a ramp up off the hill road
    # that climbs on round a U-turn back east onto the roofs, the run east over the blocks, round
    # south and two jumps over alleys, round west and along the roofs beside the south street with
    # a jump over a third alley, and down a collapsed floor slab beside the street into it. The
    # alleys are short (any kart at speed clears them: no boost needed) and the turns are tight, so
    # a good driver is about as quick up here as down in the switchbacks. A kart that drops into an
    # alley tries that jump again from 30 m before it (the jumps lie further apart than that: a
    # retry never starts in the alley before). All of it stays between the fork and the merge
    # along the lap (east of the fork's line a kart would count as off the end of the branch) and
    # at least 20 m from the middle street (a stretch beside a street counts that street's lap
    # metres, and the middle street's lie far ahead of the fork's)
    {"id": "rooftops", "name": "Rooftops", "kind": "ledge", "fork": (320, -298), "merge": (152, -150),
     "ctrl": [(303, 3.68, -290, 10, "rooframp"), (288, 3.8, -284.1, 10, "rampwall"), (277, 4.7, -281.5, 10, "rampwall"),
              (268, 5.5, -284.3, 9, "spiral"), (259, 6.2, -284.6, 9, "spiral"), (253, 6.9, -278.5, 9, "spiral"),
              (252.5, 7.6, -270, 9, "spiral"), (258.5, 8.3, -264.5, 9, "spiral"), (267, 8.85, -263.3, 10, "roof"),
              (282, 9.0, -263.5, 11, "roof"),
              (298, 9.0, -259.5, 11, "roof"), (307, 9.0, -249, 11, "roof"), (309.5, 9.0, -237, 11, "roof"),
              (310, 9.0, -226, 11, "roof", {"gap": True, "gap_span": (0.3, 0.68), "ramp_lift": 1.0, "ramp_len": 12}),
              (310, 8.2, -210, 11, "landing"), (310, 8.2, -199, 11, "landing"),
              (310, 8.2, -187, 11, "roof", {"gap": True, "gap_span": (0.32, 0.68), "ramp_lift": 1.0, "ramp_len": 12}),
              (310, 7.4, -171, 11, "landing"), (309, 7.4, -160, 11, "landing"),
              (303.5, 7.4, -147.5, 11, "roof"), (294, 7.4, -137.5, 11, "roof"), (280, 7.4, -131, 11, "roof"),
              (264, 7.4, -129.5, 11, "roof", {"gap": True, "gap_span": (0.3, 0.68), "ramp_lift": 1.0, "ramp_len": 12}),
              (248, 6.6, -129.5, 11, "landing"), (234, 6.6, -129.5, 11, "landing"),
              (222, 5.2, -130.5, 11, "slab"), (210, 2.7, -133.5, 10, "slab"),
              (194, 0.6, -136.5, 10, "rooframp"), (176, 0.0, -142.5, 10, "rooframp")],
     # (computer drivers take it about half the time on NORMAL and HARD, about a quarter on EASY)
     "items": [0.26], "risk": 0.3, "ai": {"take": 0.65, "min_skill": 0.8, "commit": 20.0}, "respawn": "before",
     "retry_back": 30.0},
]


def styles(m):
    curb = m.hl2("concrete/concretefloor019a")
    road = m.hl2("concrete/concretefloor037a")
    concrete = m.hl2("concrete/concretewall008a")
    # every barrier stops a kart thrown up off its road up to 3 m (an unseen wall over it, "col_h"):
    # a blast or a hop off a kerb no longer carries one over a jersey onto another level or behind
    # a wall
    jersey = {"kind": "jersey", "mat": m.hl2("concrete/concretewall064a"), "col_h": 3.0}
    avenue = {"kind": "street", "road": road, "road_u": "full", "curb": curb, "walk": 4.5,
              "walk_mat": m.hl2("concrete/concretefloor028c_c17"), "barrier": jersey, "skirt": concrete}
    old = {"kind": "street", "road": m.hl2("stone/cobble08a"), "road_rep": 3.0, "curb": curb, "walk": 3.0,
           "walk_mat": m.hl2("concrete/concretefloor028c"),
           "barrier": {"kind": "wall", "mat": m.hl2("stone/stonewall029b"), "h": 2.0, "rep": 3.0, "col_h": 3.0},
           "cushion": {"model": "props_c17/concrete_barrier001a", "tyres": True, "sink": 1.6}}
    # the roofs: tar on top of a brick block whose walls (with windows) go down to the ground, a
    # brick parapet round them (and an unseen wall over it: a kart that lands wide off the jump
    # slides along it instead of over it)
    parapet = {"kind": "bridge", "road": m.hl2("props/rubberroof002a"), "road_rep": 5.0,
               "skirt": m.hl2("brick/brickwall031b"), "skirt_h": 9.5, "pillar_every": 1e9, "ground": "nat",
               "barrier": {"kind": "wall", "mat": m.hl2("brick/brickwall031b"), "h": 1.2, "thick": 0.45, "rep": 3.0,
                           "col_h": 3.5}, "gap_dip": False}
    rooframp = {"kind": "bridge", "road": road, "road_u": "full", "skirt": concrete, "skirt_h": 9.5, "barrier": jersey,
                "pillar_every": 1e9, "ground": "nat"}
    viaduct = {"kind": "bridge", "road": m.hl2("concrete/concretefloor013a"), "road_rep": 6.0, "skirt": concrete,
               "skirt_h": 1.4, "barrier": dict(jersey, sides="left", broken=[18.0, 6.0]), "pillar": concrete,
               "pillar_every": 20.0, "pillar_size": 1.8, "ground": "nat"}
    return {
        # the plaza's cobbles are laid flat in plan (no stretch round its tight last corner)
        "plaza": {"kind": "street", "road": m.hl2("stone/stonefloor006d_c17"), "road_rep": 4.0, "curb": curb,
                  "walk": 7.0, "walk_mat": m.hl2("concrete/concretefloor028c_c17"), "uv": "plan",
                  "barrier": {"kind": "wall", "mat": m.hl2("stone/stonewall022a_c17"), "h": 0.9, "rep": 3.0,
                              "col_h": 2.5}},
        # the old town's walls stand 2 m: a kart thrown about by a blast stays in the street. Its
        # junctions are the rooftops' noses, where the ramp and the slab beside the street are 2.5 m
        # up: the crash cushion stands on the ground under the middle of the nose
        "old": old,
        # the switchbacks and the old town's exit bend (out to the boulevard): no pavement, the wall
        # stands at the kerb, so a kart that runs wide slides along it instead of climbing the kerb
        # and nosing into a wall across a pavement; the walls stop a kart up to 3.5 m (one a blast or
        # a rollermine throws about stays in the street, and the people behind them still look over
        # them). A computer driver takes the hairpins and the short streets between them at one
        # steady speed
        "switchback": dict(old, walk=0.6, barrier=dict(old["barrier"], col_h=3.5), vmax=21.0),
        "avenue": avenue,
        # the avenue's last 110 m before the checkpoint (past the canal jump's merge) has 2.4 m walls
        # instead of jerseys: a kart a blast throws onto a jersey there hops it and lands behind the
        # checkpoint's walls, with no way back to the road
        "approach": dict(avenue, barrier={"kind": "wall", "mat": concrete, "h": 2.4, "rep": 3.0, "col_h": 3.0}),
        # the checkpoint's Combine walls stand 5 m: karts a blast or a mine throws about there (the
        # crates and the turrets bunch them up) stay in it instead of landing in the yards behind
        "checkpoint": {"kind": "street", "road": road, "road_u": "full", "curb": curb, "walk": 3.5,
                       "walk_mat": m.hl2("concrete/concretefloor033k_c17"),
                       "barrier": {"kind": "wall", "mat": m.hl2("metal/citadel_metalwall072a"), "h": 5.0,
                                   "thick": 0.6, "rep": 4.0}},
        "yard": {"kind": "open", "road": m.hl2("concrete/concretefloor011a"), "road_rep": 5.0,
                 "verge": m.hl2("nature/dirtfloor003a"), "verge_w": 5.0,
                 "barrier": {"kind": "fence", "mat": m.hl2("metal/metalfence001a"), "h": 2.6, "off": 5.0,
                             "rep": 2.5}},
        "cut": {"kind": "trench", "road": road, "road_u": "full", "wall": concrete, "wall_rep": 4.0,
                "lip": 3.0, "lip_mat": m.hl2("concrete/concretefloor028c_c17")},
        "underpass": {"kind": "tunnel", "road": road, "road_u": "full", "height": 7.5, "wall": concrete,
                      "wall_rep": 4.0, "band": m.hl2("props/hazardstrip001a"), "band_h": 0.9, "band_rep": 1.8,
                      "ceil": m.hl2("concrete/concretefloor013a"), "light": m.hl2("lights/fluorescentcool001a"),
                      "light_every": 10.0, "light_rows": [-0.45, 0.45], "light_color": [0.85, 0.92, 1.0],
                      "light_energy": 1.6, "portal": concrete, "wall_gap": 0.6, "cover": 2.5, "lid_w": 8.0,
                      "lid_mat": m.hl2("nature/dirtfloor003a")},
        # the corner's bridge over the canal: stone parapets both sides, pillars down into the canal,
        # the street level left as it is under its ends (the canal cuts through)
        "canalbridge": {"kind": "bridge", "road": road, "road_u": "full", "skirt": concrete, "skirt_h": 1.4,
                        "barrier": {"kind": "wall", "mat": m.hl2("stone/stonewall022a_c17"), "h": 1.1, "thick": 0.45,
                                    "rep": 3.0, "col_h": 3.0},
                        "pillar": concrete, "pillar_every": 16.0, "pillar_size": 1.4, "ground": "keep"},
        # the ruined viaduct: a cracked concrete deck on pillars over the city's own ground and the
        # canal. Its jerseys stand whole on the left; on the right stretches of them are torn out
        # ("broken": 6 m gone in every 18), with an unseen wall along that whole edge
        # (_broken_edges), so the deck looks open there but no kart falls off it
        "viaduct": viaduct,
        # its low ends, out of the underpass's hollow and down into the yard: the same deck on an
        # embankment up to it ("keep": no slot under a low deck for a kart to wedge itself in)
        "viaramp": dict(viaduct, ground="keep"),
        # the collapsed span: the deck broke between two piers and its slab lies sagging between
        # them, the road down it and up the next; walls down into the rubble under it, no pillars
        "span": dict(viaduct, road=m.hl2("concrete/concretefloor007a"), road_rep=4.0, skirt_h=6.0, pillar_every=1e9),
        # the old-town flyover over the plaza road's cutting: jersey barriers, pillars down to the
        # ground beside the cutting (none in it)
        "flyover": {"kind": "bridge", "road": road, "road_u": "full", "skirt": concrete, "skirt_h": 1.8,
                    "barrier": jersey, "pillar": concrete, "pillar_every": 20.0, "pillar_size": 1.8, "ground": "keep"},
        # the canal jump's way out of the yard: a concrete track along the fence, a narrow dirt verge
        "service": {"kind": "open", "road": m.hl2("concrete/concretefloor011a"), "road_rep": 5.0,
                    "verge": m.hl2("nature/dirtfloor003a"), "verge_w": 0.8},
        # the canal jump's kicker: an avenue with hazard stripes for kerbs
        "ramp": {"kind": "street", "road": road, "road_u": "full", "curb": m.hl2("props/hazardstrip001a"), "walk": 4.5,
                 "walk_mat": m.hl2("concrete/concretefloor028c_c17"), "barrier": jersey, "skirt": concrete},
        # the ramps up onto the roofs and back down: a concrete deck with jersey barriers, closed
        # below by its walls down to the city's ground (no pillars, no embankment)
        "rooframp": rooframp,
        # the roofs (the jumps over the alleys dig no pit: under them are the blocks' yards)
        "parapet": parapet,
        # round the tight corners and on to the jumps a computer driver keeps to the middle (an open
        # edge's line, "pit"): it comes to each kicker straight, not across it from a corner's exit,
        # and leaves the lip heading for the far roof. The roofs over the alleys (the run-ups and
        # the landings) stop a kart up to 9 m over them: a boosted kart thrown high off a kicker
        # (landing from one jump onto the next one's kicker, or scraping the parapet up it) flies
        # over the next alley and comes down on the roof, not over the next corner's parapet
        "roof": dict(parapet, pit=True, barrier=dict(parapet["barrier"], col_h=9.0)),
        "landing": dict(parapet, barrier=dict(parapet["barrier"], col_h=9.0)),
        # the ramp's last stretch climbs on round a U-turn back east onto the roofs (a kart that
        # comes at it too fast meets the wall, not a crest that throws it off); a computer driver
        # keeps to its middle at a steady speed, as in the switchbacks below. Upright concrete walls
        # instead of jerseys (a kart pressed against a jersey round a tight turn rides up it and
        # rolls over), stopping a kart up to 6 m
        "spiral": dict(rooframp, pit=True, vmax=11.0,
                       barrier={"kind": "wall", "mat": concrete, "h": 1.2, "thick": 0.45, "rep": 3.0, "col_h": 6.0}),
        # the bend in the ramp just before the U-turn has the same walls: a kart that comes up the
        # ramp at full speed runs wide there and meets the outside wall at speed (on a jersey it
        # rode up it, rolled over and was thrown across the U-turn, over its wall or down the ramp)
        "rampwall": dict(rooframp, barrier={"kind": "wall", "mat": concrete, "h": 1.2, "thick": 0.45, "rep": 3.0,
                                            "col_h": 6.0}),
        # the rooftops' way down: a floor slab fallen from the last roof, tilted down to the street
        # beside the south street's wall, its broken edges walls down to the ground
        "slab": dict(parapet, road=m.hl2("concrete/concretefloor013a"), road_rep=6.0, skirt=concrete),
        # the boulevard's breach: in through a hole blown in a block's facade, across its ground
        # floor and out through another. Plaster walls, a concrete ceiling 6 m up, a floor beside
        # the road out to the walls (its pillars stand there, debris for the dressing), lit by
        # fires instead of strip lights (no panels); the facades round the holes reach 9 m out to
        # the sides and 8 m over the ceiling, the rest of the block is _breach_block's
        "breach": {"kind": "tunnel", "road": m.hl2("concrete/concretefloor013a"), "road_rep": 6.0, "height": 6.0,
                   "wall": m.hl2("plaster/plasterwall021a"), "wall_rep": 4.0, "wall_gap": 3.5,
                   "side_floor": m.hl2("concrete/concretefloor007a"), "ceil": m.hl2("concrete/concretefloor013a"),
                   "light": m.hl2("lights/white001"), "light_rows": [], "light_every": 12.0,
                   "light_color": [1.0, 0.72, 0.45], "light_energy": 1.3, "lamp_every": 1,
                   "portal": m.hl2("building_template/building_template002i"), "portal_w": 9.0, "portal_h": 8.0,
                   "cover": 0.0},
        # the ramp of rubble up onto the collapsed building's roof: its fallen end, broken concrete
        # on top and heaped rubble down its sides to the ground (no pillars), jerseys partly torn out
        "rubble": dict(viaduct, road=m.hl2("concrete/concretefloor007a"), road_rep=4.0,
                       skirt=m.hl2("concrete/concretefloor020a"), skirt_h=9.0, pillar_every=1e9),
        # the main road along that roof: tar on its block of broken brick, a parapet whole on the
        # left and broken on the right (an unseen wall along that edge, _broken_edges)
        "roofroad": dict(parapet, barrier=dict(parapet["barrier"], sides="left", broken=[14.0, 5.0]), skirt_h=9.0,
                         skirt=m.hl2("brick/brickwall021a")),
        # ... and down the floor slab fallen from its far end to the boulevard
        "fallen": dict(viaduct, road=m.hl2("concrete/concretefloor013a"), road_rep=6.0, skirt_h=8.0,
                       pillar_every=1e9),
    }


def _canal_dist(P):
    """Plan distance of points P (N, 2) from the canal's centre line."""
    best = np.full(len(P), 1e9)
    pts = np.asarray(CANAL, float)
    for a, b in zip(pts[:-1], pts[1:]):
        ab = b - a
        t = np.clip(((P - a) @ ab) / (ab @ ab), 0.0, 1.0)
        best = np.minimum(best, np.linalg.norm(P - (a + t[:, None] * ab), axis=1))
    return best


def _canal_along(u):
    """A point (x, z) u metres along the canal's centre line and the line's direction there."""
    pts = np.asarray(CANAL, float)
    for a, b in zip(pts[:-1], pts[1:]):
        seg = float(np.linalg.norm(b - a))
        if u <= seg:
            d = (b - a) / seg
            return a + d * u, d
        u -= seg
    return pts[-1], (pts[-1] - pts[-2]) / np.linalg.norm(pts[-1] - pts[-2])


def terrain(trk, m):
    # the ruined city's ground: broken concrete ("pave"), and heaped rubble with splintered wood
    # where the concrete gives out (the base layer: patches of it all over the city and the ring
    # out to the hills, where it used to be grass)
    layers = {"base": m.hl2("nature/blendrubbledirt001a"), "dirt": m.hl2("nature/dirtfloor003a"),
              "rock": m.hl2("concrete/concretewall008a"), "pave": m.hl2("concrete/concretefloor007a"),
              "sand": m.hl2("nature/blenddirtmud01")}

    def build(f, trk):
        P = f.P
        # the city is flat; hills rise beyond its edge
        far = smoothstep(260.0, 520.0, f.dist)
        nat = far * (25.0 + noise2(P[:, 0] / 160.0, P[:, 1] / 160.0, 4) * 70.0)
        cd = _canal_dist(P)
        canal = smoothstep(CANAL_HALF + 1.5, CANAL_HALF - 0.5, cd)
        nat = nat * (1 - canal) + (WATER - 3.0) * canal
        h = carve(f, nat, trk, flat=9.0, blend=24.0, gap_floor=WATER - 3.0)
        # the breach runs through a block of flats, not a hill: round it the ground stays level
        # with the street (as beside an avenue) instead of rising to its ceiling
        under = f.road_h + f.bank * np.clip(f.lat, -f.half, f.half) - 0.35 - np.abs(f.bank) * 1.5
        t = smoothstep(f.half + 9.0, f.half + 33.0, f.dist)
        h = np.where(f.style == "breach", np.minimum(under * (1 - t) + nat * t, f.cap), h)
        # the canal cuts through the shoulders too (it passes under the corner's bridge, the canal
        # jump and the viaduct)
        h = np.where(canal > 0.5, np.minimum(h, WATER - 3.0), h)
        Hm = h.reshape(f.nz, f.nx)
        gz, gx = np.gradient(Hm, f.cell)
        slope = np.sqrt(gx ** 2 + gz ** 2).ravel()
        rock = smoothstep(0.6, 1.0, slope)
        yard = np.isin(f.style, ["yard"]) & (f.dist < f.half + 40)
        embank = (f.style == "underpass") & (f.dist < f.half + 30)
        dirt = np.clip(yard * 0.9 + embank * 0.8 + far, 0, 1)
        pave = np.clip(1.0 - far * 1.4, 0, 1) * (1 - dirt)
        # rubble in patches tens of metres across through the broken concrete
        rubble = smoothstep(0.52, 0.66, noise2(P[:, 0] / 45.0 + 31.0, P[:, 1] / 45.0 - 17.0, 9))
        pave = pave * (1.0 - rubble * 0.85)
        sand = smoothstep(WATER + 0.5, WATER - 1.5, h)
        col = np.stack([dirt, rock, pave, sand], 1).astype(np.float32)
        return h, col

    return {"margin": 560.0, "cell": 4.0, "build": build, "layers": layers}


# (not row_res_2_ascend_fullscale: it steps up a slope, and on the city's level ground one end of
# it hangs 6-10 m in the air)
BUILDINGS = ["props_buildings/row_res_1_fullscale", "props_buildings/row_res_2_fullscale",
             "props_buildings/row_corner_1_fullscale", "props_buildings/building_002a",
             "props_buildings/row_church_fullscale"]
TOWERS = ["props_buildings/project_building01", "props_buildings/project_building02",
          "props_buildings/project_building03"]
WAGONS = ["props_trainstation/boxcar", "props_trainstation/train001", "props_trainstation/tanker",
          "props_trainstation/flatcar", "props_trainstation/boxcar2", "props_trainstation/train002"]


def _canal_clear(ctx, model, q, yaw):
    pts = np.array(ctx.footprint(model, q, yaw, 2.0))
    return bool((_canal_dist(pts) > CANAL_HALF + 4.0).all())


def _lamps(ctx):
    """Street lamps on the pavements of ctx's road, their arms over the road; none under another
    road's jump (a branch's jump over a street at lamp height), none where a junction left the
    pavement out or there is hardly any (the switchbacks) and none on the checkpoint's narrow
    pavements (its turrets and barricades stand there). In the ruined city the power is out on
    most of them: one in three still burns."""
    t = ctx.trk
    r = ctx.roads
    fly = np.where(r.gap & (r.route != r.trks.index(t)))[0]
    lit = 0
    for i in ctx.every(32.0):
        # (a street's end sample: its pavement starts or ends right under the lamp)
        if any(t.kind(t.wrap(i + d)) != "street" for d in (-1, 0, 1)) or t.gap[i] or t.style[i] == "checkpoint":
            continue
        st = t.styles[t.style[i]]
        if st.get("walk", 3.0) < 1.5:
            continue
        for sgn in (-1, 1):
            if t.side_off[i, (sgn + 1) // 2]:
                continue
            q = ctx.side(i, sgn, 0.3 + st.get("walk", 3.0) * 0.35)
            q[1] = t.pos[i][1] + 0.16
            under = np.hypot(r.pos[fly, 0] - q[0], r.pos[fly, 2] - q[2]) < r.width[fly] / 2 + 3.0
            if (under & (r.pos[fly, 1] < q[1] + 14.0)).any():
                continue
            lit += 1
            ctx.add("props_c17/lamppost03a_on" if lit % 3 == 1 else "props_c17/lamppost03a_off", q,
                    ctx.yaw_facing(t.flat_right[i] * sgn), ground=False)


def _rails(ctx, P, width=2.8):
    """A siding's track (sleepers and rails) along the ground under the points P (k, 3)."""
    d = np.gradient(P, axis=0)
    d[:, 1] = 0.0
    d /= np.linalg.norm(d, axis=1, keepdims=True)
    side = np.cross(UP, d)
    P = P.copy()
    P[:, 1] = [ctx.ground(p[0], p[2]) + 0.06 for p in P]
    v = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))]) / width
    n = np.repeat(UP[None], len(P), 0)
    # (wound to face up, like its normals)
    ctx.meshes["decal"].strip(ctx.mats.hl2("wood/woodtrack001a"), P + side * width / 2, P - side * width / 2, 1.0, 0.0,
                              v, n, n)


def _yard(ctx):
    """The rail yard: sidings past the fences on both sides with wagons parked along them, clear of
    the train's level crossing (its corridor refuses them), a light tower and signals."""
    t = ctx.trk
    yard = [i for i in range(t.n) if t.style[i] == "yard" and not t.gap[i]]
    if not yard:
        return
    fence = t.styles["yard"]["barrier"]["off"]
    for sgn, dist in ((-1, 14.0), (1, 14.0), (1, 23.0)):
        # the sidings follow the yard road from the end of its bend to the avenue
        ids = [i for i in yard if abs(t.curv[i]) < 0.006]
        if len(ids) < 10:
            continue
        P = np.array([ctx.side(i, sgn, dist) for i in ids])
        _rails(ctx, P)
        for k, i in enumerate(ids[3::12]):
            m = WAGONS[(k + int(dist)) % len(WAGONS)]
            q = ctx.side(i, sgn, max(dist, fence + min(ctx.model_size(m)[[0, 2]]) / 2 + 1.0))
            yaw = ctx.yaw_along(m, t.fwd[i])
            g = ctx.site(m, q, yaw, tol=0.5)
            if g is not None:
                q[1] = g
                ctx.add(m, q, yaw)
    # the light tower: a mast with the lamp cluster on top, past the west siding
    i = yard[len(yard) // 3]
    q = ctx.side(i, -1, 30.0)
    q[1] = ctx.ground(q[0], q[2])
    if ctx.free(q + UP * 8.0, [2.0, 16.0, 2.0]):
        mast = 16.0
        ctx.cylinder(ctx.mats.hl2("metal/metalpipe010a"), q - UP * 0.5, 0.35, mast + 0.5, segs=10, rep=2.0)
        ctx.add("props_trainstation/lighttowercluster01", q + UP * mast, ctx.yaw_facing(t.flat_right[i]), solid=False)
        ctx.light(q + UP * (mast - 1.0), [1.0, 0.95, 0.85], 40.0, 1.6)
    for i in yard[8::40]:
        q = ctx.side(i, 1, 7.5)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_trainstation/light_signal001a", q, ctx.yaw_facing(-t.fwd[i]))


def _canal(ctx):
    """Footbridges over the canal and boats moored on it, away from the roads."""
    total = sum(float(np.linalg.norm(np.subtract(b, a))) for a, b in zip(CANAL[:-1], CANAL[1:]))
    for u in np.arange(60.0, total - 40.0, 150.0):
        c, d = _canal_along(u)
        if ctx.road_gap_to([c[0], 0.0, c[1]]) < 45.0:
            continue
        # across the canal (the model's long span is its x), its deck ends resting on both banks
        # past the canal's sloping sides (the model's bottom is its deck's); none where a bank is not
        # level with the other or dips into the canal
        span = ctx.model_size("props_canal/canal_bridge01")[0] * FOOTBRIDGE / 2 - 1.0
        ends = [ctx.ground(c[0] + d[1] * k, c[1] - d[0] * k) for k in (-span, span)]
        if min(ends) < -0.5 or abs(ends[0] - ends[1]) > 0.6:
            continue
        ctx.add("props_canal/canal_bridge01", [c[0], max(ends), c[1]], float(math.atan2(d[0], d[1])),
                scale=FOOTBRIDGE, ground=False, tag="bridge")
    for u in np.arange(130.0, total - 40.0, 150.0):
        c, d = _canal_along(u)
        q = np.array([c[0], WATER - 0.35, c[1]]) + np.array([-d[1], 0.0, d[0]]) * (CANAL_HALF - 3.0)
        if ctx.road_gap_to(q) < 30.0:
            continue
        ctx.add("props_canal/boat001a", q, float(math.atan2(d[0], d[1])) - math.pi / 2, ground=False, base=False)


def _roofs(ctx):
    """The roofscape beside the rooftops' road: chimney stacks rising from its walls against the
    parapet's outside, an aerial on some, none of them on the road."""
    t = ctx.trk
    brick = ctx.mats.hl2("brick/brickwall017a")
    roof = [k for k in range(t.n) if t.style[k] in ("parapet", "roof", "landing") and not t.gap[k]]
    for n, k in enumerate(roof[4::9]):
        sgn = 1 if n % 2 else -1
        q = ctx.side(k, sgn, 1.25)
        h = 2.6 + (n % 3) * 0.5
        top = t.pos[k][1] + h
        g = ctx.ground(q[0], q[2])
        ctx.box(brick, [q[0], (g - 0.5 + top) / 2, q[2]], [1.5, top - g + 0.5, 1.5], ctx.yaw_facing(t.fwd[k]))
        if n % 4 == 1:
            ctx.cylinder(ctx.mats.hl2("metal/metalpipe010a"), [q[0], top, q[2]], 0.06, 3.5, segs=6, kind="deco")


def _pavement_ends(ctx):
    """Where a street and a bridge meet (the canal corner's bridge, the flyover, the ramp of
    rubble and the fallen slab), a stub of the street's barrier across the end of its pavement,
    from the deck's edge out to the barrier: a kart running along the pavement meets it instead
    of driving off the pavement's end onto the ground beside the deck, and none drops into the
    open corner beside a deck's end where the pavement starts."""
    t = ctx.trk
    for i in range(t.n):
        j = t.wrap(i - 1)
        a, b = t.styles[t.style[j]], t.styles[t.style[i]]
        if a["kind"] == "street" and b["kind"] == "bridge":
            st, k = a, j
        elif a["kind"] == "bridge" and b["kind"] == "street":
            st, k = b, i
        else:
            continue
        if not st.get("barrier") or t.gap[i] or t.cut[i]:
            continue
        bar = st["barrier"]
        h = 1.05 if bar.get("kind") == "jersey" else bar.get("h", 1.2)
        for sgn in (-1, 1):
            if t.side_off[i, (sgn + 1) // 2] or t.side_off[j, (sgn + 1) // 2]:
                continue
            hi = 0.3 + _side_w(t, [k], sgn, st.get("walk", 4.0), _treatment(st) - st.get("walk", 4.0))[0] + 0.4
            c = ctx.side(i, sgn, hi / 2)
            y0 = t.pos[i][1] + st.get("curb_h", 0.16)
            ctx.box(bar["mat"], [c[0], y0 + (h - 0.3) / 2, c[2]], [hi, h + 0.3, 0.4], ctx.yaw_facing(t.fwd[i]))


def _barrier_steps(ctx):
    """Where two street styles meet with their barriers at different distances from the road (a
    wider pavement on one side of the change), a stub of the taller barrier across the step at the
    change: no slot between the two barriers' ends for a kart on the pavement to slip out by."""
    t = ctx.trk
    for i in range(t.n):
        a, b = t.styles[t.style[t.wrap(i - 1)]], t.styles[t.style[i]]
        if a is b or a["kind"] != "street" or b["kind"] != "street" or t.gap[i] or t.cut[i]:
            continue
        if not a.get("barrier") or not b.get("barrier"):
            continue
        for sgn in (-1, 1):
            if t.side_off[i, (sgn + 1) // 2] or t.side_off[t.wrap(i - 1), (sgn + 1) // 2]:
                continue
            offs = [0.3 + _side_w(t, [i], sgn, st.get("walk", 4.0), _treatment(st) - st.get("walk", 4.0))[0]
                    for st in (a, b)]
            if abs(offs[0] - offs[1]) < 0.2:
                continue
            hs = [1.05 if st["barrier"].get("kind") == "jersey" else st["barrier"].get("h", 1.2) for st in (a, b)]
            bar, h = (a, b)[int(np.argmax(hs))]["barrier"], max(hs)
            lo, hi = min(offs), max(offs) + 0.4
            c = ctx.side(i, sgn, (lo + hi) / 2)
            y0 = t.pos[i][1] + 0.16
            ctx.box(bar["mat"], [c[0], y0 + (h - 0.3) / 2, c[2]], [hi - lo, h + 0.3, 0.4], ctx.yaw_facing(t.fwd[i]))


def _broken_edges(ctx):
    """Along the side of a deck whose railing is broken (a bridge style's barrier with "broken" and
    "sides" naming the whole one), an unseen wall from the deck up to BROKEN_UP over the barrier's
    "col_h": the gaps torn in the jerseys or the parapet look open, but a kart thrown at them stays
    on the deck (on every road: the lap's viaduct, collapsed span, ramp of rubble, roof and fallen
    slab). It stands 5 cm in from the deck's edge: a kart sliding along it never catches the blunt
    end of the next piece of railing."""
    for t in ctx.roads.trks:
        for name, st in t.styles.items():
            bar = st.get("barrier") or {}
            if st["kind"] != "bridge" or not bar.get("broken") or bar.get("sides") not in ("left", "right"):
                continue
            sgn = 1 if bar["sides"] == "left" else -1
            for ids in t.runs(lambda i, nm=name: t.style[i] == nm):
                if len(ids) < 2:
                    continue
                E = t.pos[ids] + t.right[ids] * sgn * (t.width[ids] / 2 - 0.05)[:, None] - UP * 0.3
                wall_strip(ctx.meshes["colonly"], "colonly", E, E + UP * (bar.get("col_h", 3.0) + BROKEN_UP + 0.3),
                           _unwrap_s(t, ids), sgn, 3.0)


def _span_caps(ctx):
    """The collapsed span's slab hangs its walls deeper than the viaduct's deck either side of it:
    where they meet, a face across the deck from the viaduct's underside down to the slab's
    closes the slab's end (no looking into it from under the viaduct)."""
    t = ctx.trk
    for ids in t.runs(lambda i: t.style[i] == "span"):
        for j, k, out in ((ids[0], t.wrap(ids[0] - 1), -1.0), (ids[-1], t.wrap(ids[-1] + 1), 1.0)):
            st, nb = t.styles["span"], t.styles[t.style[k]]
            if nb["kind"] != "bridge":
                continue
            hw = t.width[j] / 2
            top, low = t.pos[j][1] - nb.get("skirt_h", 1.6), t.pos[j][1] - st["skirt_h"]
            q = [t.pos[j] + t.right[j] * (hw * a) for a in (-1.0, 1.0, 1.0, -1.0)]
            q = [np.array([p[0], y, p[2]]) for p, y in zip(q, (low, low, top, top))]
            face(ctx.meshes["side"], st["skirt"], q, t.fwd[j] * out, plane_uv(q, q[0], t.flat_right[j], 4.0))


def _decks(ctx):
    """The decks that stand on their own walls (the roofs, the ramps and slabs up to them, the
    collapsed span: skirts 5 m and deeper) are held in the overlap registry, deck and side
    treatment from the ground to 2 m over it, so no building of the rows or the grid placed later
    stands through their walls or parapets."""
    for t in ctx.roads.trks:
        for i in range(0, t.n, 3):
            st = t.styles[t.style[i]]
            if st["kind"] != "bridge" or st.get("skirt_h", 1.6) < 5.0 or t.gap[i]:
                continue
            w = t.width[i] + 2.0 * ((_treatment(st) or 0.0) + 0.3)
            g = ctx.ground(t.pos[i][0], t.pos[i][2])
            lo, hi = min(g, t.pos[i][1]) - 0.5, t.pos[i][1] + 2.0
            ctx.block([t.pos[i][0], (lo + hi) / 2, t.pos[i][2]], [w, hi - lo, 3 * t.step + 0.5],
                      ctx.yaw_facing(t.fwd[i]))


def _breach_block(ctx):
    """The block of flats the boulevard's breach runs through: its ground floor is the hall (the
    breach style, a tunnel), whose portals are the facades round the two holes; from their outer
    edges the block's side walls run along it and its flat roof covers all of it 8 m over the
    hall's ceiling. Square pillars stand on the hall's floor beside the road (a kart that runs
    wide meets them). It collides like a wall, and the overlap registry holds its walls and the
    floors over the hall, so no later prop stands in it (the hall itself is left free for the
    dressing)."""
    t = ctx.trk
    st = t.styles["breach"]
    mats = ctx.mats
    for ids in t.runs(lambda i: t.style[i] == "breach", with_gaps=True):
        inner = t.width[ids] / 2 + st["wall_gap"]
        out = inner + st["portal_w"]
        H = t.pos[ids, 1] + st["height"]
        top = H + st["portal_h"]
        v = _unwrap_s(t, ids)
        edge = []
        for sgn in (-1, 1):
            E = t.pos[ids] + t.flat_right[ids] * sgn * out[:, None]
            low = E.copy()
            low[:, 1] = [min(ctx.ground(p[0], p[2]), y) - 1.0 for p, y in zip(E, t.pos[ids, 1])]
            high = E.copy()
            high[:, 1] = top
            wall_strip(ctx.meshes["walls"], st["portal"], low, high, v, -sgn, 4.0)
            edge.append(high)
        ctx.meshes["walls"].strip(mats.hl2("props/rubberroof002a"), edge[0], edge[1], 0.0,
                                  float(np.mean(out)) * 2 / 5.0, v / 5.0, np.tile(UP, (len(ids), 1)),
                                  np.tile(UP, (len(ids), 1)))
        for a in range(0, len(ids) - 1, 3):
            b = min(a + 3, len(ids) - 1)
            i, j = ids[a], ids[b]
            c = (t.pos[i] + t.pos[j]) / 2
            f = t.pos[j] - t.pos[i]
            yaw = ctx.yaw_facing(f)
            ln = float(np.hypot(f[0], f[2])) + 0.5
            rf = (t.flat_right[i] + t.flat_right[j]) / 2
            w_in, w_out = (inner[a] + inner[b]) / 2 + 0.3, (out[a] + out[b]) / 2
            for sgn in (-1, 1):
                m = c + rf * sgn * (w_in + w_out) / 2
                ctx.block([m[0], (c[1] - 1.0 + top[a]) / 2, m[2]], [w_out - w_in, top[a] - c[1] + 1.0, ln], yaw)
            ctx.block([c[0], (H[a] + top[a]) / 2, c[2]], [2 * w_out, top[a] - H[a], ln], yaw)
        # the pillars: down the middle of the floor beside the road, every 9 m, clear of the ends
        k = max(1, int(round(9.0 / t.step)))
        for q in range(k // 2 + 2, len(ids) - 2, k):
            i = ids[q]
            for sgn in (-1, 1):
                p = t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + st["wall_gap"] * 0.55)
                ctx.box(mats.hl2("concrete/concretewall008a"), [p[0], t.pos[i][1] + st["height"] / 2, p[2]],
                        [0.9, st["height"] + 0.1, 0.9], ctx.yaw_facing(t.fwd[i]))


def _prism(ctx, pts, base, top):
    """A block of flats over the plan outline pts ((k, 2), in order round it): brick walls with
    windows from base up to top and a tar roof. It collides like a wall, and the overlap registry
    holds it (one box per slice from each wall to the middle), so no later prop stands in it."""
    P = np.asarray(pts, float)
    c = P.mean(0)
    wall, roof = ctx.mats.hl2("brick/brickwall031b"), ctx.mats.hl2("props/rubberroof002a")
    h = (top - base) / 4.0
    u = 0.0
    for a, b in zip(P, np.roll(P, -1, axis=0)):
        e = b - a
        ln = float(np.hypot(*e))
        if ln < 0.05:
            continue
        nrm = np.array([e[1], 0.0, -e[0]]) / ln
        mid = (a + b) / 2
        if nrm[[0, 2]] @ (mid - c) < 0:
            nrm = -nrm
        q = [np.array([a[0], base, a[1]]), np.array([b[0], base, b[1]]), np.array([b[0], top, b[1]]),
             np.array([a[0], top, a[1]])]
        face(ctx.meshes["walls"], wall, q, nrm, [[u, h], [u + ln / 4, h], [u + ln / 4, 0], [u, 0]])
        u += ln / 4
        inward = c - mid
        depth = float(np.hypot(*inward))
        ctx.block([(mid[0] + c[0]) / 2, (base + top) / 2, (mid[1] + c[1]) / 2], [ln, top - base, depth * 0.9],
                  math.atan2(e[0], e[1]) - math.pi / 2)
    face(ctx.meshes["walls"], roof, [np.array([x, top, z]) for x, z in P], UP, [[x / 4, z / 4] for x, z in P],
         center=True)
    ctx.old_blocks.append(P)


def _old_town(ctx):
    """The old town's blocks filled in: a curved block of flats inside each switchback, behind the
    terrace there (no slot behind the wall for a kart to drop into), then row houses wherever a
    block still has room, facing the nearest street."""
    t = ctx.trk
    st = t.styles["old"]
    back = 0.3 + st["walk"] + 0.4 + 1.1
    old = np.array([s in ("old", "switchback") for s in t.style])
    bend = old & (np.abs(t.curv) > 1.0 / 45.0)
    for run in ctx.runs_of([i for i in range(t.n) if bend[i]]):
        if len(run) < 10:
            continue
        run = run[2:-2]
        sgn = -1 if np.mean(t.curv[run]) < 0 else 1
        arc = [t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + back) for i in run]
        pts = np.array([p[[0, 2]] for p in arc])
        # (a gentle bend's arc and its chord make a thin slab, not a block of flats: none there)
        px, pz = pts[:, 0], pts[:, 1]
        if abs(px @ np.roll(pz, -1) - pz @ np.roll(px, -1)) / 2 < 150.0:
            continue
        g = min(ctx.ground(x, z) for x, z in pts)
        _prism(ctx, pts, g - 0.5, t.pos[run[0]][1] + 13.0)
    ids = [i for i in range(t.n) if old[i]]
    lo = t.pos[ids][:, [0, 2]].min(0) - 30.0
    hi = t.pos[ids][:, [0, 2]].max(0) + 30.0
    spots = []
    for x in np.arange(lo[0], hi[0], 6.0):
        for z in np.arange(lo[1], hi[1], 6.0):
            gap = ctx.road_gap_to([x, 0.0, z])
            if 5.0 < gap < 40.0:
                spots.append((gap, x, z))
    for gap, x, z in sorted(spots):
        q = np.array([x, 0.0, z])
        i = int(np.argmin(((ctx.roads.pos[:, [0, 2]] - q[[0, 2]]) ** 2).sum(1)))
        yaw = round(ctx.yaw_facing(ctx.roads.pos[i] - q) / (math.pi / 2)) * math.pi / 2
        for m in ("props_buildings/row_res_2_fullscale", "props_buildings/row_res_1_fullscale"):
            if not ctx.fits(m, q, yaw, 4.0) or not _canal_clear(ctx, m, q, yaw):
                continue
            g = ctx.site(m, q, yaw, tol=1.0)
            if g is None:
                continue
            q[1] = g
            if ctx.add(m, q, yaw, tag="building", ground=False):
                break


# ---------------------------------------------------------------- the ruins
# heaps of broken concrete (the first two big, the rest small) and the chunks strewn round them
HEAPS = ["props_debris/concrete_debris256pile001a", "props_debris/concrete_floorpile01a",
         "props_debris/concrete_debris128pile001a", "props_debris/concrete_debris128pile001b",
         "props_debris/concrete_cornerpile01a"]
CHUNKS = ["props_debris/concrete_chunk01a", "props_debris/concrete_chunk02a", "props_debris/concrete_chunk06c",
          "props_debris/concrete_chunk07a"]
# burnt-out cars (HL2's rusted wrecks)
WRECKS = ["props_vehicles/car001b_hatchback", "props_vehicles/car002b", "props_vehicles/car003b",
          "props_vehicles/car004b", "props_vehicles/car005b"]
# the skyline's gutted and fallen-in blocks among the tower blocks
RUINED_TOWERS = ["props_buildings/project_destroyedbuildings01", "props_buildings/collapsedbuilding02b",
                 "props_buildings/collapsedbuilding02c"]
# what shuts a side street ("wreck": one of WRECKS)
SHUTTERS = ["props_debris/concrete_debris256barricade001a", "props_debris/barricade_tall01a", "wreck",
            "props_debris/concrete_debris256barricade001a", "props_debris/barricade_short01a"]
# the lap metres whose side streets are shut: the avenue to the canal corner, the old town's exit
# and the boulevard before the breach, between it and the ramp of rubble and on into the plaza
SIDE_STREETS = ((823.0, 1025.0), (1757.0, 1853.0), (2059.0, 2115.0), (2171.0, 2191.0), (2378.0, 2476.0))
# craters beside the road (lap metres, side, metres past the road edge): those on level open
# ground are dug (the yard's verges between the fence and the sidings, the open ground beside
# the viaduct and the collapsed building, the plaza's approach)
CRATERS = ((460.0, 1, 12.0), (662.0, 1, 9.0), (700.0, -1, 9.0), (2205.0, 1, 18.0), (2240.0, -1, 16.0),
           (2420.0, 1, 22.0), (2370.0, 1, 16.0))
# burnt-out vehicles by the road (lap metres, side, metres past the road edge, model, burning)
WRECK_SPOTS = ((656.0, -1, 21.0, WRECKS[0], True), (1100.0, 1, 26.0, WRECKS[3], False),
               (2094.0, -1, 14.0, "combine_apc_destroyed_gib01", True), (2400.0, 1, 19.0, WRECKS[2], True),
               (2445.0, -1, 20.0, WRECKS[4], False))


def _lap_i(t, s):
    """The sample at lap metres s."""
    return int(round(s / t.step)) % t.n


def _fire(ctx, q, size=1.0, smoke=1.0, light=False):
    """A fire for scripts/fx/ruin_fires.gd with its flames at q: `size` scales the flames (1: a
    burning car), `smoke` the column of smoke over it (0 none, 1 a car's, 3 a burning block's
    seen from across the city) and `light` gives it a flickering light."""
    ctx.fires.append({"pos": [round(float(c), 2) for c in q], "size": round(float(size), 2),
                      "smoke": round(float(smoke), 2), "light": bool(light)})


def _ground_prop(ctx, model, q, yaw, tol=0.6, **kw):
    """A prop standing on the ground at plan point q (on the lowest ground under its footprint):
    False where that ground varies by more than tol or the prop is refused (see Ctx.add)."""
    if model not in ctx.models:
        ctx.missing.add(model)
        return False
    q = np.array([q[0], 0.0, q[2]], float)
    g = ctx.site(model, q, yaw, scale=kw.get("scale", 1.0), tol=tol)
    if g is None:
        return False
    q[1] = g
    return ctx.add(model, q, yaw, **kw)


def _centred(ctx, model, c, yaw):
    """The origin that puts a model's box (in plan) centred on c when turned by yaw."""
    mm = ctx.models[model]
    mid = (np.array(mm["aabb_min"]) + np.array(mm["aabb_max"])) / 2
    q = np.array(c, float)
    q -= np.array([math.cos(yaw), 0.0, -math.sin(yaw)]) * mid[0] + np.array([math.sin(yaw), 0.0, math.cos(yaw)]) * mid[2]
    return q


def _heap(ctx, c, big=True, chunks=2, pile=None):
    """A heap of rubble on the ground at plan point c: a pile, big or small (or the one named by
    `pile`), with a few chunks of concrete strewn round it. The height of the pile's top when it
    stands, else None."""
    rng = ctx.rng
    piles = HEAPS[:2] if big else HEAPS[2:]
    m = piles[int(rng.integers(0, len(piles)))]
    m = pile or m
    ok = _ground_prop(ctx, m, c, float(rng.uniform(0, 6.28)), tol=0.8)
    top = ctx.props[-1]["pos"][1] + ctx.models[m]["aabb_max"][1] if ok else None
    if ok:
        r0 = 3.6 if big else 2.2
        for _ in range(chunks):
            a = float(rng.uniform(0, 6.28))
            r = r0 + float(rng.uniform(0.0, 1.2))
            q = np.array([c[0] + math.cos(a) * r, 0.0, c[2] + math.sin(a) * r])
            _ground_prop(ctx, CHUNKS[int(rng.integers(0, len(CHUNKS)))], q, float(rng.uniform(0, 6.28)), tol=0.4)
    return top


def _decal_tris(P, nrm, nx, nz):
    """Triangles of a grid of (nx + 1) x (nz + 1) points P (row by row), wound to face nrm."""
    tri = []
    for j in range(nz):
        for k in range(nx):
            a, b = j * (nx + 1) + k, j * (nx + 1) + k + 1
            c, d = b + nx + 1, a + nx + 1
            tri += [a, b, c, a, c, d]
    if np.dot(np.cross(P[tri[1]] - P[tri[0]], P[tri[2]] - P[tri[0]]), nrm) < 0:
        tri = [x for k in range(0, len(tri), 3) for x in (tri[k], tri[k + 2], tri[k + 1])]
    return tri


def _ground_decal(ctx, mat, c, size, yaw, lift=0.1, n=4):
    """A decal lying on the ground (n x n cells following the terrain) centred on plan point c,
    `size` metres square, turned by yaw."""
    ax = np.array([math.cos(yaw), 0.0, -math.sin(yaw)])
    az = np.array([math.sin(yaw), 0.0, math.cos(yaw)])
    P, uv = [], []
    for j in range(n + 1):
        for k in range(n + 1):
            p = np.array([c[0], 0.0, c[2]]) + ax * size * (k / n - 0.5) + az * size * (j / n - 0.5)
            p[1] = ctx.ground(p[0], p[2]) + lift
            P.append(p)
            uv.append([k / n, j / n])
    P = np.array(P)
    ctx.meshes["decal"].add(mat, P, [UP] * len(P), uv, _decal_tris(P, UP, n, n))


def _road_decal(ctx, t, i, lat, length, width, mat):
    """A decal on the road of t, `length` metres along it centred on sample i, `width` across
    centred `lat` metres right of its middle (it follows the road's slope)."""
    k = max(2, int(round(length / t.step)) + 1)
    ids = np.array([t.wrap(i - k // 2 + j) for j in range(k)])
    if t.gap[ids].any() or (t.mag[ids] > 0.0).any():
        return
    A = np.array([t.surface(j, lat - width / 2, 0.03) for j in ids])
    B = np.array([t.surface(j, lat + width / 2, 0.03) for j in ids])
    ctx.meshes["decal"].strip(mat, A, B, 0.0, 1.0, np.linspace(0.0, 1.0, k), t.up[ids], t.up[ids])


def _wall_decal(ctx, mat, c, nrm, along, w, h):
    """An upright decal w x h metres centred on c, facing nrm (soot on a facade)."""
    u, v = along * (w / 2), UP * (h / 2)
    P = np.array([c - u - v, c + u - v, c - u + v, c + u + v])
    ctx.meshes["decal"].add(mat, P, [nrm] * 4, [[0, 1], [1, 1], [0, 0], [1, 0]], _decal_tris(P, nrm, 1, 1))


def _landmarks(ctx):
    """The ruins' big pieces, placed before the city's rows and grid (they fill round them): two
    spans of a broken flyover standing in the rubble outside the viaduct's bend beside its
    collapsed span (clear of the canal), a gutted block of flats south of the collapsed
    building's roof (seen from it) and the destroyed dome on the skyline west of the plaza, toward
    the Citadel, with smoke rising out of both."""
    t = ctx.trk
    for s, off, model, skew in ((524.0, 26.0, "props_c17/overpass_001a", 0.35),
                                (570.0, 30.0, "props_c17/overpass_001b", -0.45)):
        i = _lap_i(t, s)
        yaw = ctx.yaw_facing(t.fwd[i]) + skew
        c = ctx.side(i, 1, off + 6.0)
        if model in ctx.models and _canal_clear(ctx, model, c, yaw):
            _ground_prop(ctx, model, c, yaw, tol=2.5, tag="building")
    i = _lap_i(t, 2280.0)
    m = "props_buildings/project_destroyedbuildings01"
    if m in ctx.models:
        yaw = ctx.yaw_facing(t.flat_right[i])
        c = ctx.side(i, -1, 26.0 + ctx.model_size(m)[2] / 2)
        if ctx.fits(m, c, yaw, 18.0) and _ground_prop(ctx, m, c, yaw, tol=2.0, tag="building"):
            _fire(ctx, [c[0], ctx.ground(c[0], c[2]) + 30.0, c[2]], 1.5, 3.0)
    m = "props_rooftop/parliament_dome_destroyed_exterior"
    c = np.array([-270.0, 0.0, 205.0])
    if m in ctx.models and ctx.road_gap_to(c) > 150.0 and _ground_prop(ctx, m, c, 0.6, tol=6.0, scale=2.2,
                                                                       tag="building"):
        _fire(ctx, [c[0], ctx.ground(c[0], c[2]) + 40.0, c[2]], 2.0, 3.5)


def _viaduct_ruins(ctx):
    """The ruined viaduct: rubble and crumbs of concrete over its deck (decals), heaps of rubble
    on the ground both sides of the collapsed span, rebar out of the broken piers at its ends and
    fires in the heaps (their smoke rises past the deck)."""
    t = ctx.trk
    rng = ctx.rng
    deck = [i for i in range(t.n) if t.style[i] in ("viaduct", "span", "viaramp") and not t.gap[i]]
    for n, i in enumerate(deck[3::7]):
        hw = t.width[i] / 2
        mat = ("decals/rubble01a", "decals/debris_concrete001a")[n % 2]
        _road_decal(ctx, t, i, float(rng.uniform(-hw + 2.8, hw - 2.8)), 5.0, 4.0, ctx.mats.hl2(mat))
    span = [i for i in range(t.n) if t.style[i] == "span"]
    if len(span) < 6:
        return
    # (the heaps stand past the span's walls and their 2.3 m in the overlap registry, _decks)
    for k, i in enumerate(span[2:-2:5]):
        for sgn in (-1, 1):
            big = (k + (sgn > 0)) % 2 == 0
            _heap(ctx, ctx.side(i, sgn, (6.2 if big else 4.2) + float(rng.uniform(0.0, 2.5))), big)
    for i in (span[0], span[-1]):
        for sgn in (-1, 1):
            _ground_prop(ctx, "props_debris/rebar_cluster002a", ctx.side(i, sgn, 2.9), float(rng.uniform(0, 6.28)),
                         tol=0.8)
    for i, sgn in ((span[len(span) // 3], 1), (span[2 * len(span) // 3], -1)):
        q = ctx.side(i, sgn, 5.0)
        q[1] = ctx.ground(q[0], q[2]) + 0.8
        _fire(ctx, q, 1.2, 1.8, light=sgn > 0)


def _breach_ruins(ctx):
    """The breach: broken edges hanging under the lintels of the two holes blown in the block's
    facades and soot over them, heaps of plaster and broken floor against the hall's walls between
    its pillars (none of them over 0.41 m, all 1.5 m or more from the road) with pieces of the
    ceiling hanging over the floor, fires in the hall and on heaps outside both holes."""
    t = ctx.trk
    rng = ctx.rng
    st = t.styles["breach"]
    H = st["height"]
    soot = ctx.mats.hl2("decals/scorch2")
    for ids in t.runs(lambda i: t.style[i] == "breach", with_gaps=True):
        for end, out in ((ids[0], -1.0), (ids[-1], 1.0)):
            f = t.fwd[end] * out
            f = np.array([f[0], 0.0, f[2]]) / np.hypot(f[0], f[2])
            rr = t.flat_right[end]
            c = t.pos[end]
            w2 = t.width[end] / 2 + st["wall_gap"]
            # (their fronts, local +x, face out of the facade; hung on it, they block nothing; none
            # over the middle of the road, where Ctx.add counts a prop 7 m up as on it)
            yaw = ctx.yaw_facing(f) - math.pi / 2
            for lat, m in ((-6.0, "002a"), (6.0, "002a"), (-(w2 - 1.7), "001a"), (w2 - 1.7, "001a")):
                q = c + f * 0.22 + rr * lat
                q[1] = c[1] + H - 0.4
                ctx.add("props_debris/building_brokenexterior" + m, q, yaw, tag="deco", solid=False, ground=False)
            for lat in (-8.5, 8.5):
                _wall_decal(ctx, soot, c + f * 0.05 + rr * lat + UP * (H + 2.8), f, rr, 7.0, 5.5)
            # a heap burning outside the hole, beyond the avenue's barrier
            j = t.wrap(end + int(out * 4))
            sgn = -1 if out < 0 else 1
            q = ctx.side(j, sgn, (_treatment(t.styles[t.style[j]]) or 2.0) + 3.5)
            if _heap(ctx, q, False, chunks=1) is not None:
                _fire(ctx, [q[0], ctx.ground(q[0], q[2]) + 0.7, q[2]], 1.0, 1.5, light=True)
        # against the walls on the hall's floor, between its pillars (every 9 m, _breach_block)
        k = max(1, int(round(9.0 / t.step)))
        n = 0
        for q_ in range(k // 2 + 2 + k // 2, len(ids) - 3, k):
            i = ids[q_]
            for sgn in (-1, 1):
                if rng.random() < 0.3:
                    continue
                m = ("props_debris/plaster_floorpile001a", "props_debris/broken_pile001a")[n % 2]
                at = ctx.against_wall(i, sgn, m, y=t.pos[i][1])
                n += 1
                if at is None:
                    continue
                if n % 3 == 1:
                    _fire(ctx, [at[0], t.pos[i][1] + 0.3, at[2]], 0.55, 0.0)
                if n % 3 == 2:
                    # (square to the walls: turned, its corners would reach into them)
                    q = t.pos[i] + t.flat_right[i] * sgn * (t.width[i] / 2 + 1.7)
                    q[1] = t.pos[i][1] + H - 0.1
                    ctx.add("props_debris/destroyedceiling01a", q, ctx.yaw_facing(t.fwd[i]), base=False, tag="deco",
                            solid=False, ground=False)


def _roof_ruins(ctx):
    """The collapsed building: rubble heaped on the ground along both sides of the ramp of rubble,
    rebar out of the broken ends of the roof's parapet on its right and where the fallen slab
    broke off it, a fire on the roof's broken edge and smoke rising past the roof from fires on
    the ground beside the building."""
    t = ctx.trk
    rng = ctx.rng
    ramp = [i for i in range(t.n) if t.style[i] == "rubble"]
    for k, i in enumerate(ramp[1::4]):
        for sgn in (-1, 1):
            big = (k + (sgn > 0)) % 2 == 0
            _heap(ctx, ctx.side(i, sgn, (6.0 if big else 4.0) + float(rng.uniform(0.0, 2.0))), big)
    st = t.styles["roofroad"]
    bar = st["barrier"]
    every, open_ = bar["broken"]
    for ids in t.runs(lambda i: t.style[i] == "roofroad"):
        v = _unwrap_s(t, ids)
        v = v - v[0]
        piece = (v % every) > open_
        ends = [j + (0 if piece[j] else 1) for j in range(len(ids) - 1) if piece[j] != piece[j + 1]]
        for n, j in enumerate(ends):
            i = ids[j]
            # on the parapet's top, its right-hand side being the broken one (sides "left"); square
            # to the road, none of it over the road's edge
            q = t.pos[i] + t.right[i] * (t.width[i] / 2) + t.flat_right[i] * (bar["thick"] / 2)
            q[1] += bar["h"]
            if n % 2 == 0:
                yaw = ctx.yaw_facing(t.fwd[i])
                ctx.add("props_debris/rebar_cluster001a", _centred(ctx, "props_debris/rebar_cluster001a", q, yaw), yaw,
                        solid=False, ground=False)
            elif n == 3:
                # a fire on the roof's broken edge: on the top of this piece of parapet at its
                # broken end (a fire out in the gap would hang in the air over the drop)
                e = q - t.fwd[i] * (0.5 if piece[j] else -0.5)
                _fire(ctx, e + UP * 0.1, 0.7, 1.2, light=True)
        # where the fallen slab broke off: rebar out of the left parapet's end (its narrow side
        # across the parapet)
        i = ids[-1]
        q = t.pos[i] - t.right[i] * (t.width[i] / 2) - t.flat_right[i] * (bar["thick"] / 2) - t.fwd[i] * 0.5
        q[1] += bar["h"]
        yaw = ctx.yaw_facing(t.flat_right[i])
        ctx.add("props_debris/rebar_cluster002a", _centred(ctx, "props_debris/rebar_cluster002a", q, yaw), yaw,
                solid=False, ground=False)
    # (the burning heaps are the big piles of broken concrete, the flames down in their tops: on a
    # flat floor pile the same fire hung over it)
    for s, sgn, off, light in ((2262.0, -1, 10.0, False), (2312.0, 1, 12.0, True)):
        i = _lap_i(t, s)
        q = ctx.side(i, sgn, off)
        top = _heap(ctx, q, True, chunks=1, pile=HEAPS[0])
        if top is not None:
            _fire(ctx, [q[0], top + 0.25, q[2]], 1.4, 2.4, light=light)


def _side_streets(ctx):
    """Rubble shutting the side streets: in each gap the building rows left behind the barrier
    along the avenue to the canal corner, the old town's exit and the boulevard, a rubble or a
    junk barricade or a burnt-out car, a metre or more behind the barrier."""
    t = ctx.trk
    rng = ctx.rng
    n = 0
    for s0, s1 in SIDE_STREETS:
        for sgn in (-1, 1):
            s = s0 + 3.0
            while s < s1 - 3.0:
                i = _lap_i(t, s)
                st = t.styles[t.style[i]]
                if st["kind"] != "street" or not st.get("barrier") or t.side_off[i, (sgn + 1) // 2] or \
                        t.junction[i] or t.cut[i]:
                    s += 3.0
                    continue
                m = SHUTTERS[n % len(SHUTTERS)]
                if m == "wreck":
                    m = WRECKS[(n // len(SHUTTERS)) % len(WRECKS)]
                if m not in ctx.models:
                    ctx.missing.add(m)
                    n += 1
                    s += 3.0
                    continue
                size = ctx.model_size(m)
                q = ctx.side(i, sgn, _treatment(st) + 1.0 + min(size[0], size[2]) / 2)
                yaw = ctx.yaw_along(m, t.fwd[i]) + float(rng.uniform(-0.15, 0.15))
                if _ground_prop(ctx, m, q, yaw, tol=0.8):
                    n += 1
                    s += 11.0 + max(size[0], size[2])
                else:
                    s += 3.0


def _wrecks(ctx):
    """Burnt-out cars and the burnt hull of an APC by the road (WRECK_SPOTS), some still burning."""
    t = ctx.trk
    rng = ctx.rng
    for s, sgn, off, m, burning in WRECK_SPOTS:
        i = _lap_i(t, s)
        if m not in ctx.models:
            ctx.missing.add(m)
            continue
        q = ctx.side(i, sgn, off)
        yaw = ctx.yaw_along(m, t.fwd[i]) + float(rng.uniform(-0.6, 0.6))
        if _ground_prop(ctx, m, q, yaw, tol=0.6) and burning:
            top = ctx.props[-1]["pos"][1] + ctx.models[m]["aabb_max"][1] * 0.7
            _fire(ctx, [q[0], top, q[2]], 1.0 if "apc" in m else 0.8, 1.6 if "apc" in m else 1.0,
                  light="apc" in m)


def _craters(ctx):
    """Shell craters on open ground beside the road (CRATERS): a crater decal with chunks of
    concrete thrown round its rim, where the ground is level and nothing stands."""
    t = ctx.trk
    rng = ctx.rng
    mat = ctx.mats.hl2("decals/decal_crater001a")
    dug = 0
    for s, sgn, off in CRATERS:
        i = _lap_i(t, s)
        c = ctx.side(i, sgn, off)
        g = [ctx.ground(c[0] + dx, c[2] + dz) for dx in (-3.5, 0.0, 3.5) for dz in (-3.5, 0.0, 3.5)]
        if max(g) - min(g) > 1.2 or ctx.road_gap_to(c) < 4.5 or not ctx.free([c[0], min(g) + 1.0, c[2]],
                                                                                 [6.5, 2.0, 6.5]):
            continue
        dug += 1
        _ground_decal(ctx, mat, c, 7.5, float(rng.uniform(0, 6.28)))
        for k in range(5):
            a = k * 1.26 + float(rng.uniform(-0.3, 0.3))
            q = np.array([c[0] + math.cos(a) * 4.2, 0.0, c[2] + math.sin(a) * 4.2])
            # (none on a verge or a pavement inside a fence or a barrier: those are driven on)
            if ctx.road_gap_to(q) > 7.0:
                _ground_prop(ctx, CHUNKS[k % len(CHUNKS)], q, float(rng.uniform(0, 6.28)), tol=0.5)
    print("  ruins: %d of %d craters dug" % (dug, len(CRATERS)))


def _skyline_fires(ctx):
    """Smoke rising out of the skyline's ruined blocks (the grid's RUINED_TOWERS), a few of them
    far apart."""
    picked = [f["pos"] for f in ctx.fires if f["smoke"] >= 3.0]
    for p in ctx.props:
        if p["model"] not in RUINED_TOWERS or any(math.hypot(p["pos"][0] - q[0], p["pos"][2] - q[2]) < 220.0
                                                  for q in picked):
            continue
        h = ctx.models[p["model"]]["aabb_max"][1] - ctx.models[p["model"]]["aabb_min"][1]
        q = [p["pos"][0], p["pos"][1] + ctx.models[p["model"]]["aabb_min"][1] + h * 0.7, p["pos"][2]]
        _fire(ctx, q, 1.8, 3.0)
        picked.append(q)
        if len(picked) >= 7:
            break


def _soot(ctx):
    """Soot up the old town's blocks of flats (_prism) where fire came out of their windows: a
    black scorch high on about half of their long walls."""
    rng = ctx.rng
    mat = ctx.mats.hl2("decals/scorch1")
    for P in getattr(ctx, "old_blocks", []):
        c = P.mean(0)
        for a, b in zip(P, np.roll(P, -1, axis=0)):
            e = b - a
            ln = float(np.hypot(*e))
            if ln < 12.0 or rng.random() < 0.5:
                continue
            mid = a + e * float(rng.uniform(0.3, 0.7))
            nrm = np.array([e[1], 0.0, -e[0]]) / ln
            if nrm[[0, 2]] @ (mid - c) < 0:
                nrm = -nrm
            q = np.array([mid[0], ctx.ground(mid[0], mid[1]) + float(rng.uniform(5.0, 8.0)), mid[1]]) + nrm * 0.05
            _wall_decal(ctx, mat, q, nrm, np.array([e[0], 0.0, e[1]]) / ln, 6.0, 5.0)


def _ruins(ctx):
    """The ruined city round the circuit (stage D3), after the buildings and the street furniture:
    see the parts."""
    _viaduct_ruins(ctx)
    _breach_ruins(ctx)
    _roof_ruins(ctx)
    _wrecks(ctx)
    _craters(ctx)
    _side_streets(ctx)
    _soot(ctx)
    _skyline_fires(ctx)


def decorate_branch(ctx, spec):
    """A branch's dressing (ctx dresses its road): building rows and lamps along its avenues, the
    roofscape along the rooftops."""
    for sgn in (-1, 1):
        ctx.row_along({"avenue", "ramp"}, BUILDINGS[2:] + BUILDINGS[:2], sgn, 4.5 + 2.4, gap=1.0, accept=_canal_clear)
    _lamps(ctx)
    if spec["id"] == "rooftops":
        _roofs(ctx)
        _alley_guides(ctx)


def _alley_guides(ctx):
    """Across each alley the rooftops jump, an unseen wall along both edges of the gap from the
    take-off roof's parapet to the landing roof's (as tall as the landing's stops a kart): a kart
    that flies across beside an edge (a boosted one thrown off its line by the landing before)
    slides along it onto the landing roof instead of catching the blunt end of the landing's
    parapet and dropping into the alley. A kart that falls short drops between them."""
    t = ctx.trk
    for a, b in t.gaps:
        ids = np.arange(max(a - 3, 0), min(b + 2, t.n))
        h = t.styles[t.style[ids[-1]]]["barrier"].get("col_h", 3.0)
        for sgn in (-1, 1):
            E = t.pos[ids] + t.right[ids] * sgn * (t.width[ids] / 2)[:, None] - UP * 0.3
            wall_strip(ctx.meshes["colonly"], "colonly", E, E + UP * (h + 0.3), t.s[ids], sgn, 3.0)


def decorate(ctx):
    t = ctx.trk
    rng = ctx.rng
    L = t.length
    # the block the breach runs through and the decks on their own walls first: every building
    # placed after them keeps out of them
    _breach_block(ctx)
    _decks(ctx)
    # the ruins' big pieces next (the broken flyover spans, the gutted block, the dome): the rows
    # and the grid fill round them
    ctx.fires = []
    _landmarks(ctx)
    # building rows behind the pavements, clear of the canal (rows first: the grid fills round them)
    for sgn in (-1, 1):
        ctx.row_along({"plaza"}, BUILDINGS, sgn, 7.0 + 2.2, gap=0.5, accept=_canal_clear)
        ctx.row_along({"old", "switchback"}, BUILDINGS[::-1], sgn, 3.0 + 1.8, gap=0.0, accept=_canal_clear)
        ctx.row_along({"avenue", "approach"}, BUILDINGS[2:] + BUILDINGS[:2], sgn, 4.5 + 2.4, gap=1.0,
                      accept=_canal_clear)
        ctx.row_along({"checkpoint"}, ["props_buildings/row_res_2_fullscale", "props_buildings/row_res_1_fullscale"],
                      sgn, 3.5 + 3.0, gap=2.0, accept=_canal_clear)
    ctx.old_blocks = []
    _old_town(ctx)
    # the rest of the city: tower blocks and rows on a loose grid, clear of the circuit, each on
    # level ground, fronts (the tower blocks are open at the back) turned to the nearest road of any
    roads = ctx.roads.pos
    for x in np.arange(-520, 1120, 46.0):
        for z in np.arange(-720, 720, 46.0):
            q = np.array([x + rng.uniform(-8, 8), 0.0, z + rng.uniform(-8, 8)])
            gap = ctx.road_gap_to(q)
            if gap < 22 or gap > 430:
                continue
            m = TOWERS[int(rng.integers(0, 3))] if gap > 120 or rng.random() < 0.25 else BUILDINGS[int(rng.integers(0, len(BUILDINGS)))]
            # out on the skyline about one tower block in three is gutted or has fallen in
            if m in TOWERS and gap > 100 and rng.random() < 0.35:
                m = RUINED_TOWERS[int(rng.integers(0, len(RUINED_TOWERS)))]
            i = int(np.argmin(((roads[:, [0, 2]] - q[[0, 2]]) ** 2).sum(1)))
            yaw = round(ctx.yaw_facing(roads[i] - q) / (np.pi / 2)) * np.pi / 2
            if m in TOWERS:
                # of its four sides, the one fewest road samples within 200 m see the open back of
                # (the nearest road's first)
                d = roads[:, [0, 2]] - q[[0, 2]]
                d = d[np.hypot(d[:, 0], d[:, 1]) < 200.0]
                yaw = min((yaw + k * np.pi / 2 for k in range(4)),
                          key=lambda y: int((d[:, 0] * math.sin(y) + d[:, 1] * math.cos(y) < 0.0).sum()))
            if not ctx.fits(m, q, yaw, 14.0) or not _canal_clear(ctx, m, q, yaw):
                continue
            g = ctx.site(m, q, yaw, tol=0.6)
            if g is None or g < -2.0 or g > 6.0:
                continue
            if any(np.hypot(p["pos"][0] - q[0], p["pos"][2] - q[2]) < 30 for p in ctx.props if p.get("tag") == "building"):
                continue
            q[1] = g
            ctx.add(m, q, yaw, tag="building", ground=False)
    _lamps(ctx)
    # plaza: Breencast screens either side of the line (its pavements are left clear: a kart pushed
    # onto them wedged itself between a column or a bench and the wall)
    ctx.screens = []
    for s, sgn in ((70.0, -1), (L - 120.0, 1)):
        i = int(round(s / t.step)) % t.n
        q = ctx.side(i, sgn, 7.0 + 2.0)
        q[1] = t.pos[i][1] + 13.0
        ctx.screens.append({"pos": q.tolist(), "yaw": float(ctx.yaw_facing(-t.flat_right[i] * sgn)), "w": 10.0,
                            "h": 5.6})
    # Combine checkpoint: barricades backed onto its walls (a kart spun onto the pavement is
    # not wedged behind one), booths, a watchtower, a bunker
    chk = [i for i in range(t.n) if t.style[i] == "checkpoint"]
    walk = t.styles["checkpoint"]["walk"]
    depth = ctx.model_size("props_combine/combine_barricade_tall01a")[2]
    for k, i in enumerate(chk[::7]):
        for sgn in (-1, 1):
            q = ctx.side(i, sgn, walk - depth / 2 - 0.05)
            q[1] = t.pos[i][1] + 0.16
            ctx.add("props_combine/combine_barricade_tall01a", q, ctx.yaw_facing(-t.flat_right[i] * sgn), ground=False)
    if chk:
        mid = chk[len(chk) // 2]
        for sgn in (-1, 1):
            q = ctx.side(mid, sgn, 3.5 + 5.0)
            q[1] = ctx.ground(q[0], q[2])
            ctx.add("props_combine/combine_booth_med01a", q, ctx.yaw_facing(-t.flat_right[mid] * sgn), ground=False)
        q = ctx.side(chk[0], 1, 3.5 + 6.0)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_combine/combinetower001", q, 0.0, ground=False)
        q = ctx.side(chk[-1], -1, 3.5 + 6.0)
        q[1] = ctx.ground(q[0], q[2])
        ctx.add("props_combine/combine_bunker01", q, ctx.yaw_facing(t.flat_right[chk[-1]]), ground=False)
    _canal(ctx)
    _yard(ctx)
    _broken_edges(ctx)
    _span_caps(ctx)
    _barrier_steps(ctx)
    _pavement_ends(ctx)
    # trains parked on the embankment over the underpass
    tun = [i for i in range(t.n) if t.style[i] == "underpass"]
    for k, i in enumerate(tun[8::14]):
        m = WAGONS[k % len(WAGONS)]
        q = t.pos[i].copy()
        q[1] = t.pos[i][1] + t.height[i] + 2.5
        ctx.add(m, q, ctx.yaw_along(m, t.fwd[i]), ground=False)
    # the boulevard toward the Citadel: Combine machinery along it, on level ground
    fly = [i for i in range(t.n) if t.style[i] == "flyover"]
    blv = [i for i in range(t.n) if t.style[i] == "avenue" and fly and t.s[i] > t.s[fly[-1]]]
    for k, i in enumerate(blv[::30]):
        sgn = 1 if k % 2 else -1
        m = ["props_combine/combinebuttress", "props_combine/combine_generator01", "props_combine/combine_emitter01"][k % 3]
        q = ctx.side(i, sgn, 4.5 + 9.0)
        yaw = ctx.yaw_facing(-t.flat_right[i] * sgn)
        g = ctx.site(m, q, yaw)
        if g is not None:
            q[1] = g
            ctx.add(m, q, yaw)
    # a few physics props at the back of the pavement on the inside of slow corners (never on the
    # road, out of the way of a kart that runs wide onto the pavement; not in the hairpins or by
    # the turrets), 15 m or more from a crate row or a boost pad
    keep = [f * L for f in TRACK["items"] + TRACK["boosts"]]
    for i in ctx.every(140.0, 60.0):
        if t.gap[i] or abs(t.curv[i]) < 0.012 or t.kind(i) != "street" or t.junction[i]:
            continue
        if t.style[i] in ("switchback", "checkpoint"):
            continue
        if min(abs((t.s[i] - s + L / 2) % L - L / 2) for s in keep) < 15.0:
            continue
        sgn = -1 if t.curv[i] < 0 else 1
        st = t.styles[t.style[i]]
        base = ctx.side(i, sgn, 0.3 + st.get("walk", 3.0) - 0.9)
        base[1] = t.pos[i][1] + st.get("curb_h", 0.16)
        for k in range(3):
            q = base + t.fwd[i] * rng.uniform(-3, 3) + t.flat_right[i] * sgn * rng.uniform(-0.3, 0.3)
            ctx.add(["props_junk/trafficcone001a", "props_c17/oildrum001", "props_junk/wood_crate001a"][k],
                    q + UP * 0.02, rng.uniform(0, 6.28), physics=True, ground=False)
    # the ruins round everything placed so far: they fill the gaps it left
    _ruins(ctx)


# ---------------------------------------------------------------- spectators (tools/crowds.py)
START = (-34.0, 30.0)  # grandstands either side of the line (lap metres)
PLAZA = ((-75.0, -36.0), (32.0, 60.0))  # two-step terraces beyond them
CP_EVERY = 9.0  # metrocops posted along the plaza terraces
# old-town terrace steps rise to this much under the wall's top: the people on them look over it
# from the waist up (the checkpoint's guards stand on a step behind its 5 m wall)
OLD_RISE = 0.7
OLD_EVERY = 60.0  # a 20 m terrace every this many metres of walled street
JUMP_WATCH = 32.0  # the switchbacks' terraces this near the rooftops' first jump are its watchers'
GMAN_S = (754.0, 1004.0)  # the lap metres the G-Man may stand beside (ctx.gman_spot)
GUARD_EVERY, GUARD_LEN, GUARD_DEPTH, GUARD_H = 36.0, 5.0, 1.6, 0.5  # the checkpoint guards' platforms


def _walled(ctx, i):
    """A street with a barrier you can see over (stands go behind it)."""
    return not ctx.trk.gap[i] and ctx.street_back(i) is not None


def _lap_walled(ctx, w):
    return [i for i in ctx.lap_ids(*w) if _walled(ctx, i)]


def _landings(ctx, before=10.0, after=40.0):
    """(gap end sample, sample ids from `before` m ahead of the landing to `after` m past it)."""
    t = ctx.trk
    out = []
    for a, b in t.gaps:
        s = ctx.s_of(b % t.n)
        out.append((b % t.n, ctx.lap_ids(s - before, s + after)))
    return out


def _start_window(ctx, i):
    s = ctx.s_of(i)
    L = ctx.trk.length
    rel = (s + L / 2) % L - L / 2
    return PLAZA[0][0] - 5 <= rel <= PLAZA[1][1] + 5


def _old_walls(ctx):
    """The old town's and the plaza's walled stretches away from the start (one-step terraces; not
    the checkpoint's approach)."""
    t = ctx.trk
    return [i for i in range(t.n) if _walled(ctx, i) and not _start_window(ctx, i) and t.style[i] != "approach"
            and ctx.style_of(i).get("barrier", {}).get("kind") == "wall"]


def _jump_watch(ctx):
    """The walled main-road samples near the rooftops' first jump, within JUMP_WATCH of its middle."""
    t = ctx.trk
    roof = ctx.roads.trks[1 + [b["id"] for b in BRANCHES].index("rooftops")]
    a, b = roof.gaps[0]
    mid = roof.pos[(a + b) // 2]
    return [i for i in range(t.n) if _walled(ctx, i) and np.hypot(*(t.pos[i] - mid)[[0, 2]]) < JUMP_WATCH]


def _old_chunks(ctx):
    """The one-step terraces' stretches: 20 m every OLD_EVERY m along the old walls (none over the
    switchbacks' near the rooftops' first jump), and the stretches near the jump (its watchers')."""
    t = ctx.trk
    jump = _jump_watch(ctx)
    old = [ch for ch in ctx.chunks(_old_walls(ctx), int(OLD_EVERY / t.step), int(20 / t.step))
           if not set(ch) & set(jump)]
    return old, ctx.runs_of(jump)


def stands(ctx):
    for sgn in (-1, 1):
        # start / finish: a Combine-built grandstand each side (4 tiers, back wall, canopy)
        ctx.grandstand(_lap_walled(ctx, START), sgn)
        for w in PLAZA:
            ctx.terrace(_lap_walled(ctx, w), sgn, steps=2)
        # the other walled streets: one step in 20 m chunks, raised so the people on it look over
        # the wall
        old, jump = _old_chunks(ctx)
        for ch in old + jump:
            h = ctx.style_of(ch[0])["barrier"].get("h", 2.0)
            ctx.terrace(ch, sgn, steps=1, rise=max(0.6, h - OLD_RISE))


def crowds(ctx):
    t = ctx.trk
    rng = ctx.crowd_rng
    # metrocops posted on the plaza terraces first (egg: they condemn rebels, salute Breen)
    for sgn in (-1, 1):
        for w in PLAZA:
            ids = _lap_walled(ctx, w)
            gid = ctx.crowd_group(ids[len(ids) // 2] if ids else 0, sgn, "post", "metrocop", tags=["start", "egg_cp"],
                                  bed="")
            ctx.crowd_line(gid, ids, sgn, CP_EVERY, lambda i, s: ctx.terrace_spot(i, s, 0), "metrocop", mood="loyal",
                           lod=lambda k: 0, margin=0.4, on="geom")
    # the grandstands: citizens, the back tiers on the one-material background citizen
    for sgn in (-1, 1):
        ids = _lap_walled(ctx, START)
        gid = ctx.crowd_group(ids[len(ids) // 2] if ids else 0, sgn, "stand", "citizen",
                              tags=["start", "grandstand"])
        for tier, chance in enumerate((0.75, 0.6, 0.35, 0.35)):
            far = tier >= 2
            ctx.crowd_line(gid, ids, sgn, 2.0, lambda i, s, k=tier: ctx.terrace_spot(i, s, k), "citizen",
                           mood=["fan", "fan", "excited", "polite"][int(rng.integers(0, 4))], chance=chance,
                           lod=(lambda k: 1) if far else None, margin=0.4, on="geom",
                           model=FAR_MODEL if far else None)
    # either side of them: the plaza crowd on its two steps, refugees out of the ruins (fewer
    # than the old city's crowd)
    for sgn in (-1, 1):
        for w in PLAZA:
            ids = _lap_walled(ctx, w)
            gid = ctx.crowd_group(ids[len(ids) // 2] if ids else 0, sgn, "terrace", "refugee", tags=["start"])
            ctx.crowd_line(gid, ids, sgn, 2.0, lambda i, s: ctx.terrace_spot(i, s, 0), "refugee", chance=0.5,
                           margin=0.4, on="geom")
            ctx.crowd_line(gid, ids, sgn, 2.0, lambda i, s: ctx.terrace_spot(i, s, 1), "refugee", chance=0.3,
                           lod=lambda k: 2, margin=0.4, on="geom")
    # the old town (and the plaza's far side): refugees on the one-step terraces, a group per chunk
    for ch in _old_chunks(ctx)[0]:
        for sgn in (-1, 1):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "terrace", "refugee")
            ctx.crowd_line(gid, ch, sgn, 1.6, lambda i, s: ctx.terrace_spot(i, s, 0), "refugee",
                           mood=["fan", "polite"][int(rng.integers(0, 2))], chance=0.6, margin=0.4, on="geom")
    # the yard jump's landing: rebels in clusters on the open ground past the fences
    for land, ids in _landings(ctx):
        if t.kind(land) != "open":
            continue
        st = ctx.style_of(land)
        off = st.get("barrier", {}).get("off", 0.0) + 4.0
        j = min(ids[len(ids) // 3:] or [land], key=lambda k: abs(t.curv[k]))
        for sgn in (-1, 1):
            c = ctx.side_point(j, sgn, st.get("verge_w", 4.5) + off + 4.0)
            gid = ctx.crowd_group(j, sgn, "cluster", "rebel", tags=["jump"])
            ctx.crowd_cluster(gid, c, 10, 6.0, "rebel", t.pos[j] + np.array([0, 1.0, 0]), mood="excited",
                              ref_y=t.pos[j][1])
    # the rest of the fenced yard: rebels beyond the fence
    fenced = [i for i in range(t.n) if t.kind(i) == "open" and not t.gap[i]
              and ctx.style_of(i).get("barrier", {}).get("kind") == "fence"]
    for sgn in (-1, 1):
        def beyond(i, s):
            st = ctx.style_of(i)
            return ctx.side_point(i, s, st.get("barrier", {}).get("off", 0.0) + rng.uniform(1.5, 6.0), jitter=1.0)

        for ch in ctx.chunks(fenced, int(40 / t.step), int(40 / t.step)):
            gid = ctx.crowd_group(ch[len(ch) // 2], sgn, "line", "rebel")
            ctx.crowd_line(gid, ch, sgn, 3.0, beyond, "rebel", chance=0.28, margin=2.5, dy=(-1.0, 3.0))
    # the cutting: rebels on both lips looking down into it
    for ids in ctx.runs_of([i for i in range(t.n) if t.kind(i) == "trench"]):
        for sgn in (-1, 1):
            gid = ctx.crowd_group(ids[len(ids) // 2], sgn, "lip", "rebel", tags=["lip"])
            ctx.crowd_line(gid, ids, sgn, 2.0, ctx.lip_spot, "rebel", chance=0.4, margin=0.3, on="geom")
    _guards(ctx)
    # the Breencast screens: the plaza crowd near one watches it instead now and then
    for scr in getattr(ctx, "screens", []):
        sp = np.array(scr["pos"], float)
        for m in ctx.crowds:
            if m["role"] != "metrocop" and math.hypot(m["pos"][0] - sp[0], m["pos"][2] - sp[2]) < 35.0 \
                    and rng.random() < 0.4:
                m["yaw"] = round(math.atan2(sp[0] - m["pos"][0], sp[2] - m["pos"][2]), 3)
    eggs(ctx)


def _guards(ctx):
    """The checkpoint's guards (its walls are too tall to see over): on platforms behind its walls,
    their tops GUARD_H under the walls' (they show from the chest up over them), every GUARD_EVERY
    m along both walls where there is room: two metrocops each, a Combine soldier on some (egg:
    they condemn rebels and salute Breen)."""
    t = ctx.trk
    st = t.styles["checkpoint"]
    bar = st["barrier"]
    chk = [i for i in range(t.n) if t.style[i] == "checkpoint"]
    for sgn in (-1, 1):
        for n, i in enumerate(chk[int(GUARD_EVERY / 2 / t.step)::int(GUARD_EVERY / t.step)]):
            back = 0.3 + st["walk"] + bar["thick"] + 0.05
            c = ctx.side(i, sgn, back + GUARD_DEPTH / 2)
            top = t.pos[i][1] + bar["h"] - GUARD_H
            g = min(ctx.ground(*ctx.side(i, sgn, back + k)[[0, 2]]) for k in (0.0, GUARD_DEPTH))
            size = [GUARD_DEPTH, top - g + 0.5, GUARD_LEN]
            yaw = ctx.yaw_facing(t.fwd[i])
            centre = [c[0], (top + g - 0.5) / 2, c[2]]
            if not ctx.free(centre, size, yaw):
                continue
            ctx.box(bar["mat"], centre, size, yaw)
            gid = ctx.crowd_group(i, sgn, "post", "metrocop", tags=["checkpoint"], bed="")
            look = t.pos[i] + UP * 1.0
            for k, role in enumerate(("metrocop", "metrocop", "combine")[:3 if n % 2 else 2]):
                q = c + t.fwd[i] * (k - 1) * 1.6
                q[1] = top
                ctx.crowd_add(gid, q, look, role, mood="military" if role == "combine" else "loyal", lod=0,
                              margin=0.4, on="geom")


def crowds_branch(bctx, spec):
    """People watching a branch's jump (their group follows the karts on that branch): rebels on
    the canal's banks beside the canal jump, and refugees on the switchbacks' terraces near the
    rooftops' jumps, looking up."""
    t = bctx.trk
    for a, b in t.gaps:
        mid = (a + b) // 2
        watch = [float(t.s[max(a - 25, 0)]), float(t.s[min(b + 10, t.n - 1)])]
        look = t.pos[mid] + UP * 2.0
        if spec["id"] == "canal_jump":
            for k, sgn in ((a - 6, -1), (a - 6, 1), (min(b + 6, t.n - 1), -1), (min(b + 6, t.n - 1), 1)):
                c = bctx.side_point(k, sgn, 8.0)
                gid = bctx.crowd_group(k, sgn, "cluster", "rebel", tags=["jump"], watch=watch)
                bctx.crowd_cluster(gid, c, 6, 4.0, "rebel", look, mood="excited", ref_y=t.pos[k][1],
                                   dy=(-1.5, 1.5))
        elif spec["id"] == "rooftops":
            # the main road's own terrace steps below the jump
            main = bctx.roads.trks[0]
            under = [i for i in range(main.n) if (bctx._steps.get((None, i, -1)) or bctx._steps.get((None, i, 1)))
                     and np.hypot(*(main.pos[i] - t.pos[mid])[[0, 2]]) < JUMP_WATCH]
            if not under:
                continue
            gid = bctx.crowd_group(mid, 0, "terrace", "refugee", tags=["jump"], watch=watch)
            for i in under:
                for sgn in (-1, 1):
                    st = bctx._steps.get((None, i, sgn))
                    if st is None or bctx.crowd_rng.random() > 0.45:
                        continue
                    back, rise, depth, steps, base, _ = st
                    q = main.pos[i] + main.flat_right[i] * sgn * (main.width[i] / 2 + back + depth * 0.5)
                    q[1] = base + rise
                    bctx.crowd_add(gid, q, look, "refugee", mood="excited", margin=0.4, on="geom")


def _in_blocks(ctx, q):
    """Inside one of the old town's blocks of flats (_prism)."""
    for P in getattr(ctx, "old_blocks", []):
        a, b = P, np.roll(P, -1, axis=0)
        cross = (a[:, 1] > q[2]) != (b[:, 1] > q[2])
        with np.errstate(divide="ignore", invalid="ignore"):
            x = a[:, 0] + (q[2] - a[:, 1]) * (b[:, 0] - a[:, 0]) / (b[:, 1] - a[:, 1])
        if (cross & (q[0] < x)).sum() % 2:
            return True
    return False


def eggs(ctx):
    t = ctx.trk
    rng = ctx.crowd_rng
    # pigeons on the plaza's and the old town's pavements, away from the stands
    walled = [i for i in range(t.n) if _walled(ctx, i) and not _start_window(ctx, i)]
    for k, i in enumerate(walled[len(walled) // 5::max(1, len(walled) // 2)][:2]):
        sgn = 1 if k % 2 else -1
        st = ctx.style_of(i)
        c = ctx.side_point(i, sgn, 0.3 + st.get("walk", 3.0) * 0.6, y=t.pos[i][1] + 0.16)
        ctx.egg("birds", species="pigeon", center=c, radius=2.5, count=8)
    # zombies shambling behind an old-town wall where no building stands
    done = False
    old = [i for i in walled if t.style[i] in ("old", "switchback")]
    for ch in ctx.chunks(old, int(30 / t.step), int(12 / t.step)):
        if done:
            break
        for sgn in (-1, 1):
            back = ctx.street_back(ch[0])
            if back is None:
                continue
            a = ctx.side_point(ch[0], sgn, back[0] + 2.0)
            b = ctx.side_point(ch[-1], sgn, back[0] + 2.0)
            if all(ctx.crowd_ok(p, margin=2.0) and not _in_blocks(ctx, p) for p in (a, (a + b) / 2, b)) and \
                    ctx.egg("zombies", path=[a, b], count=3, model="zombie/classic"):
                done = True
                break
    # the G-Man by the canal corner, ahead of the karts coming round it, clear of the crate rows:
    # seen 25-70 m off for a few seconds, gone when you come close or look away (a kart on the canal
    # jump misses him: where every kart drives, fences and walls hide him too soon)
    g = ctx.gman_spot(*GMAN_S)
    if g is not None:
        ctx.egg("gman", pos=g["pos"], yaw=g["yaw"], s=g["s"], model="gman_high", window=g["window"], chance=0.4)
    # Gnome Chompski on a grandstand canopy
    if ctx.canopies:
        c = ctx.canopies[int(rng.integers(0, len(ctx.canopies)))]
        ctx.egg("gnome", pos=c["pos"], yaw=math.atan2(-t.flat_right[c["i"]][0] * c["sgn"],
                                                      -t.flat_right[c["i"]][2] * c["sgn"]))
