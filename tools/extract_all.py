"""Extract everything HL2 Kart needs from the Half-Life 2 install into hl2kart/assets.

python -I extract_all.py [--force]

A run only adds what is missing: HL2 models, textures and sounds already in assets/ are kept
(model materials are still looked up again, so VMT fixes reach materials.json). HL1 models are
always converted again (about a second). --force converts the HL2 models again too.

The whole run rebuilds assets/data/models.json and voices.json from these lists. To add a few new
entries to an assets/ folder that is already built, without the full run, use tools/extract_extra.py.
"""
import json
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import keyvalues  # noqa: E402
import materials  # noqa: E402
import mdl  # noqa: E402
import mdl_anim  # noqa: E402
import sounds  # noqa: E402
import srcfs  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.normpath(os.path.join(HERE, "..", "assets"))
FORCE = "--force" in sys.argv

DRIVERS = ["alyx", "barney", "kleiner", "eli", "monk", "breen", "gman_high", "police",
           "combine_soldier", "odessa", "mossman", "vortigaunt", "zombie/classic"]
BODYGROUPS = {"models/zombie/classic.mdl": {"headcrab1": 1}}

# Half-Life 1 (GoldSrc) racers: Gordon's HEV model; Shephard from Opposing Force if
# installed (gearbox/), otherwise the HD HECU marine in the gas mask.
from steam_paths import HL1_ROOT  # noqa: E402
HL1_MODELS = [
    ("hl1/gordon", ["valve/models/player/gordon/gordon.mdl"], {"body": 1}),
    ("hl1/shephard", ["gearbox/models/player/shephard/shephard.mdl", "valve_hd/models/hgrunt.mdl"],
     {"heads": 0, "weapons": 2}),
]

# HL1 sounds for the start arches: the Black Mesa VOX announcer's words and HECU radio chatter
VOX_SENTENCES = [
    "attention all personnel _comma please report to sector c test lab",
    "warning _comma anomalous materials lab access is now authorized",
    "doctor freeman _comma please report to the lambda reactor core immediately",
    "black mesa announcement system test _period this is a test",
    "hazard level one _comma evacuate area immediately",
]
HL1_SOUNDS = ["hgrunt/c2a2_hg_chat1a.wav", "hgrunt/c2a2_hg_chat2a.wav", "hgrunt/c2a2_hg_chat3a.wav",
              "hgrunt/c2a2_hg_chat4a.wav", "hgrunt/c2a2_hg_chat5a.wav", "hgrunt/c2a5_hg_abandon.wav",
              "hgrunt/c2a5_hg_lebuz.wav"]
HL1_SOUNDS += sorted({"vox/%s.wav" % w for line in VOX_SENTENCES for w in line.split()})
# hazards: turrets and the sentry's gun, houndeyes, vortigaunt bolts, the tentacle, the Apache, tripmines,
# mortars; spares for later hazards: barnacles, slime arcs, falling rocks
HL1_SOUNDS += [
    "turret/tu_ping.wav", "turret/tu_alert.wav", "turret/tu_deploy.wav", "turret/tu_spinup.wav",
    "turret/tu_spindown.wav", "turret/tu_fire1.wav", "turret/tu_retract.wav",
    "weapons/hks1.wav", "weapons/hks2.wav", "weapons/hks3.wav",
    "houndeye/he_alert1.wav", "houndeye/he_alert2.wav", "houndeye/he_attack1.wav", "houndeye/he_blast1.wav",
    "houndeye/he_blast2.wav", "houndeye/he_blast3.wav", "houndeye/he_idle1.wav", "houndeye/he_pain1.wav",
    "aslave/slv_alert1.wav", "aslave/slv_alert3.wav", "debris/zap1.wav", "debris/zap4.wav",
    "weapons/electro4.wav", "weapons/electro5.wav",
    "tentacle/te_alert1.wav", "tentacle/te_roar1.wav", "tentacle/te_sing1.wav", "tentacle/te_swing1.wav",
    "tentacle/te_strike1.wav", "tentacle/te_strike2.wav", "tentacle/te_move1.wav",
    "apache/ap_rotor2.wav", "apache/ap_whine1.wav", "weapons/rocketfire1.wav", "weapons/rocket1.wav",
    "weapons/mine_deploy.wav", "weapons/mine_charge.wav", "weapons/mine_activate.wav",
    "ambience/distantmortar1.wav", "ambience/distantmortar2.wav",
    "barnacle/bcl_tongue1.wav", "barnacle/bcl_bite3.wav", "barnacle/bcl_chew1.wav", "barnacle/bcl_chew2.wav",
    "barnacle/bcl_chew3.wav", "ambience/zapmachine.wav", "debris/bustconcrete1.wav",
]

# HL1 set dressing for the Black Mesa, Xen and Surface Tension circuits (valve/models/<name>.mdl)
HL1_PROPS = [
    "forklift", "loader", "sentry", "turret", "miniturret", "scientist", "filecabinet", "holo",
    "light", "tree", "fungus", "fungus(large)", "fungus(small)", "hair", "uplant1", "uplant2", "uplant3",
    "crystal", "big_rock", "floater", "islave", "houndeye", "controller", "nihilanth", "protozoa",
    "dead_osprey", "osprey", "apache", "hgrunt", "tentacle2", "garg",
    # hazards: the Apache's rockets, tripmines (the mine alone, no hands), barnacles
    "rpgrocket", "p_tripmine", "barnacle",
    # Xen: the bullsquid that spits acid from the island edges (the controller and houndeye are above)
    "bullsquid",
]

# Spectators (scripts/crowd): City 17 residents, refugees and rebels, a one-material background
# citizen for the back tiers, the metrocops' stun baton (bonemerged on ValveBiped.Bip01_R_Hand) and Lamarr
CROWD_MODELS = (["humans/group01/male_%02d" % i for i in (1, 2, 3, 4, 5, 6, 7, 8, 9)] +
                ["humans/group01/female_%02d" % i for i in (1, 2, 3, 4, 6, 7)] +  # there is no female_05
                ["humans/group02/male_%02d" % i for i in (1, 3, 5, 7, 9)] +
                ["humans/group02/female_%02d" % i for i in (2, 4, 6)] +
                ["humans/group03/male_%02d" % i for i in (1, 2, 4, 6, 8)] +
                ["humans/group03/female_%02d" % i for i in (1, 3, 7)] +
                ["humans/group01/male_cheaple", "weapons/w_stunbaton", "lamarr"])
# HL1 spectators: key, candidates under HL1_ROOT (HD first), bodygroups (always applied)
HL1_CROWD = [
    ("hl1/sci_glasses", ["valve_hd/models/scientist.mdl", "valve/models/scientist.mdl"], {"heads": 0}),
    ("hl1/sci_einstein", ["valve_hd/models/scientist.mdl", "valve/models/scientist.mdl"], {"heads": 1}),
    ("hl1/sci_luther", ["valve_hd/models/scientist.mdl", "valve/models/scientist.mdl"], {"heads": 2}),
    ("hl1/sci_slick", ["valve_hd/models/scientist.mdl", "valve/models/scientist.mdl"], {"heads": 3}),
    ("hl1/guard", ["valve_hd/models/barney.mdl", "valve/models/barney.mdl"], {"gun": 0}),
    ("hl1/gman", ["valve_hd/models/gman.mdl", "valve/models/gman.mdl"], {}),
    ("hl1/islave_hd", ["valve_hd/models/islave.mdl", "valve/models/islave.mdl"], {}),
    ("hl1/marine_mask", ["valve_hd/models/hgrunt.mdl"], {"heads": 0, "weapons": 0}),
    ("hl1/marine_cmdr", ["valve_hd/models/hgrunt.mdl"], {"heads": 1, "weapons": 0}),
    ("hl1/marine_shot", ["valve_hd/models/hgrunt.mdl"], {"heads": 2, "weapons": 1}),
    ("hl1/zombie", ["valve/models/zombie.mdl"], {}),  # Black Mesa waste egg
    ("hl1/boid", ["valve/models/boid.mdl"], {}),  # Surface Tension birds
]

# Animations the game plays on a converted model (<key>.anims.json next to its glTF): the model key,
# the model that holds them, and our name -> its animation. Dog's run and walk are the forward ("N")
# pieces of HL2's run_all / walk_all.
ANIMS = {
    "dog": ("models/dog_animations.mdl", {"run": "a_run_N", "walk": "a_walk_N", "idle": "idle01"}),
}

MODELS = [
    "buggy", "vehicle", "combine_apc", "props_vehicles/apc001", "props_vehicles/apc_tire001",
    "props_c17/furniturebathtub001a", "props_vehicles/carparts_wheel01a",
    "manhack", "roller", "combine_scanner", "headcrabclassic", "combine_strider", "combine_dropship",
    "gunship", "combine_apc", "crow", "pigeon", "seagull", "dog",
    "items/item_item_crate", "items/item_item_crate_chunk01", "items/item_item_crate_chunk02",
    "items/item_item_crate_chunk05", "items/item_item_crate_chunk06", "items/item_item_crate_chunk07",
    "items/item_item_crate_chunk08", "items/item_item_crate_chunk09",
    "items/battery", "items/healthkit", "items/combine_rifle_ammo01", "items/hevsuit",
    "weapons/w_physics", "weapons/w_grenade", "weapons/w_rocket_launcher",
    "props_combine/headcrabcannister01a", "props_combine/combine_mine01",
    "props_c17/oildrum001", "props_c17/oildrum001_explosive", "props_junk/trafficcone001a",
    "props_junk/wood_crate001a", "props_junk/wood_crate002a", "props_junk/watermelon01",
    "props_borealis/bluebarrel001", "props_c17/concrete_barrier001a", "props_wasteland/barricade001a",
    "props_wasteland/barricade002a", "props_c17/lamppost03a_off", "props_c17/fence01a", "props_c17/fence01b",
    "props_c17/fence02a", "props_c17/traffic_light001a", "props_c17/utilitypole01a", "props_c17/utilitypole02b",
    "props_c17/signpole001", "props_c17/streetsign001c", "props_c17/streetsign004e", "props_c17/bench01a",
    "props_c17/furniturecouch001a", "props_c17/furniturefridge001a", "props_c17/furniturestove001a",
    "props_c17/furnituremattress001a", "props_c17/playground_carousel01", "props_c17/playground_swingset01",
    "props_c17/statue_horse", "props_c17/fountain_01", "props_c17/awning001a",
    "props_junk/trashdumpster01a", "props_junk/garbage_bag001a", "props_junk/popcan01a",
    "props_junk/cardboard_box001a", "props_junk/cardboard_box002a", "props_junk/gnome", "props_junk/pushcart01a",
    "props_junk/propane_tank001a", "props_junk/trashbin01a", "props_junk/bicycle01a", "props_junk/wood_pallet001a",
    "props_junk/ravenholmsign", "props_junk/cinderblock01a", "props_junk/sawblade001a",
    "props_vehicles/car001a_hatchback", "props_vehicles/car002a_physics", "props_vehicles/car003a_physics",
    "props_vehicles/car004a_physics", "props_vehicles/car005a_physics", "props_vehicles/van001a_physics",
    "props_vehicles/truck001a", "props_vehicles/truck003a", "props_vehicles/trailer002a",
    "props_vehicles/tire001c_car", "props_vehicles/tire001a_tractor", "props_vehicles/apc001",
    "props_vehicles/wagon001a_phy", "props_vehicles/tanker001a",
    "props_combine/combine_barricade_short01a", "props_combine/combine_barricade_med01a",
    "props_combine/combine_barricade_tall01a", "props_combine/combine_fence01a", "props_combine/combine_fence01b",
    "props_combine/combine_light001a", "props_combine/combine_citadel001", "props_combine/combinethumper002",
    "props_combine/combine_booth_med01a", "props_combine/combine_intmonitor001", "props_combine/breenclock",
    "props_combine/combine_bunker01", "props_combine/combinetower001", "props_combine/combinebuttress",
    "props_combine/combine_generator01", "props_combine/combine_emitter01", "props_combine/combine_bridge",
    "props_combine/combine_train02a", "props_combine/combinetrain01a",
    "props_buildings/row_res_1_fullscale", "props_buildings/row_res_2_fullscale",
    "props_buildings/row_res_2_ascend_fullscale", "props_buildings/row_corner_1_fullscale",
    "props_buildings/row_church_fullscale", "props_buildings/building_002a", "props_buildings/project_building01",
    "props_buildings/project_building02", "props_buildings/project_building03", "props_buildings/long_building001a",
    "props_buildings/short_building001a", "props_buildings/watertower_001a", "props_buildings/collapsedbuilding01a",
    "props_buildings/collapsedbuilding02a", "props_buildings/destroyed_cityblock01a",
    "props_wasteland/rockcliff01b", "props_wasteland/rockcliff01f", "props_wasteland/rockcliff05a",
    "props_wasteland/rockcliff_cluster01b", "props_wasteland/rockcliff_cluster02a", "props_wasteland/rockcliff_cluster03a",
    "props_wasteland/rockgranite01a", "props_wasteland/rockgranite02a", "props_wasteland/rockgranite03a",
    "props_wasteland/rockgranite04a", "props_wasteland/cargo_container01", "props_wasteland/cargo_container01b",
    "props_wasteland/boat_fishing01a", "props_wasteland/buoy01", "props_wasteland/lighthouse_fresnel_light_base",
    "props_wasteland/exterior_fence002b", "props_wasteland/exterior_fence003a", "props_wasteland/wood_fence01a",
    "props_wasteland/gaspump001a", "props_wasteland/powertower01", "props_wasteland/medbridge_arch01",
    "props_wasteland/coolingtank01", "props_wasteland/horizontalcoolingtank04", "props_wasteland/antlionhill",
    "props_foliage/tree_pine04", "props_foliage/tree_pine05", "props_foliage/tree_pine_large",
    "props_foliage/tree_deciduous_01a", "props_foliage/tree_deciduous_02a", "props_foliage/tree_deciduous_03a",
    "props_foliage/tree_poplar_01", "props_foliage/tree_dead01", "props_foliage/tree_cliff_01a",
    "props_foliage/oak_tree01", "props_foliage/shrub_01a", "props_foliage/bush2", "props_foliage/rock_coast02a",
    "props_foliage/rock_coast02c", "props_foliage/driftwood_01a", "props_foliage/fallentree01",
    "props_foliage/grass_cluster01", "props_foliage/ferns01",
    "props_canal/canal_bridge01", "props_canal/canal_bridge02", "props_canal/canal_bridge_railing01",
    "props_canal/boat001a", "props_canal/locks_large",
    "props_docks/dock01_pole01a_128", "props_docks/channelmarker01a",
    "props_trainstation/trainstation_clock001", "props_trainstation/benchoutdoor01a",
    "props_trainstation/trashcan_indoor001a", "props_trainstation/train001", "props_trainstation/boxcar",
    "props_trainstation/payphone001a", "props_trainstation/light_signal001a",
    "props_lab/huladoll", "props_lab/monitor01a",
    # Black Mesa
    "props_lab/crystalbulk", "props_lab/crystalholder_bars", "props_lab/crystalholder_claw",
    "props_lab/crystalholder_crystal", "props_lab/teleportframe", "props_lab/teleportring", "props_lab/servers",
    "props_lab/workspace001", "props_lab/workspace002", "props_lab/workspace003", "props_lab/generator",
    "props_lab/generatorconsole", "props_lab/pipesystem01a", "props_lab/pipesystem02a", "props_lab/pipesystem03a",
    "props_lab/lockers", "props_lab/labturret", "props_lab/hev_case", "props_lab/hev_machine", "props_lab/securitybank",
    "props_lab/blastdoor001a", "props_lab/powerbox02a", "props_lab/reciever_cart", "props_lab/filecabinet02",
    "props_lab/monitor02", "props_lab/partsbin01", "props_interiors/vendingmachinesoda01a",
    "props_interiors/furniture_desk01a", "props_interiors/furniture_chair01a", "props_wasteland/controlroom_desk001a",
    "props_wasteland/controlroom_filecabinet001a", "props_wasteland/coolingtank01", "props_wasteland/coolingtank02",
    "props_wasteland/pipecluster001a", "props_wasteland/pipecluster002a", "props_wasteland/light_spotlight01_lamp",
    "props_c17/lockers001a", "props_c17/furnitureshelf001a", "props_c17/shelfunit01a", "props_c17/furnitureboiler001a",
    "props_junk/wood_pallet001a", "props_junk/plasticcrate01a", "props_junk/propane_tank001a",
    "props_c17/light_floodlight02_off",
    # CT17
    "props_c17/lamppost03a_on", "props_trainstation/boxcar2", "props_trainstation/flatcar",
    "props_trainstation/lighttowercluster01", "props_trainstation/tanker", "props_trainstation/train002",
    "props_trainstation/trainstation_column001", "props_trainstation/benchoutdoor01a",
    # hazards: the Combine floor turret, a second train car, rockets, the tripmine fallback; spares for
    # later hazards: the big thumper, the Hunter-Chopper and its bombs
    "combine_turrets/floor_turret", "props_combine/combine_train02b", "weapons/w_missile", "weapons/w_slam",
    "props_combine/combinethumper001a", "combine_helicopter", "combine_helicopter/helicopter_bomb01",
    # Phase D creatures: antlions for the desert and Nova Prospekt, the antlion guard (Nova Prospekt's boss),
    # Episode Two's acid workers, grubs and their glowing nuggets for the antlion caves, the elite soldier and
    # the Nova Prospekt guard for the marching Combine column, the Episode Two hunter. Animations for them go
    # into ANIMS when a track needs them: the antlions' are in their own files, the hunter's in
    # models/hunter_animations.mdl, the soldiers' in models/combine_soldier_anims.mdl.
    "antlion", "antlion_worker", "antlion_guard", "antlion_grub", "grub_nugget_small", "grub_nugget_medium",
    "grub_nugget_large", "combine_super_soldier", "combine_soldier_prisonguard", "hunter",
    # the desert's magnet crane: the Highway 17 dock crane (crane_docks has the boom and cab bones,
    # crane_body_lod is the same body in one piece, crane_frame the tower under it) and its magnet
    "cranes/crane_docks", "cranes/crane_body_lod", "cranes/crane_frame", "props_wasteland/cranemagnet01a",
    # desert: planks, boards, beams and docks for the plank paths and wooden bridges over the sand, beached boats,
    # driftwood, more coast rocks, the Highway 17 bridge (whole at low detail, its middle span and railing), concrete
    # bridge pier pieces and rusted wrecks for the highway
    "props_wasteland/dockplank01a", "props_wasteland/dockplank01b", "props_debris/wood_board01a",
    "props_debris/wood_board03a", "props_debris/wood_board05a", "props_debris/wood_board07a",
    "props_docks/dock01_crossbeam01a", "props_docks/dock01_pole01a_256", "props_docks/dock01_polecluster01a",
    "props_docks/canal_dock01a", "props_docks/canal_dock03a", "props_docks/dock_broken01a",
    "props_docks/piling_cluster01a", "props_wasteland/boat_01", "props_wasteland/boat_fishing02a",
    "props_wasteland/tugtop001", "props_foliage/driftwood_02a", "props_foliage/driftwood_clump_01a",
    "props_wasteland/rockcliff01c", "props_wasteland/rockcliff06d", "props_wasteland/rockcliff06i",
    "props_wasteland/rockcliff07b", "props_wasteland/bridge_low_res", "props_wasteland/bridge_middle",
    "props_wasteland/bridge_railing", "props_wasteland/medbridge_base01", "props_wasteland/medbridge_post01",
    "props_wasteland/medbridge_strut01", "props_vehicles/car001b_hatchback", "props_vehicles/car002b",
    "props_vehicles/car003b", "props_vehicles/car004b", "props_vehicles/car005b", "props_vehicles/truck002a_cab",
    # ruined City 17: concrete chunks and rubble piles, broken walls and floors, rebar, collapsed and gutted
    # buildings, the broken flyover (a ruined viaduct), the destroyed dome, burnt-out APC wrecks, street junk
    "props_debris/concrete_chunk01a", "props_debris/concrete_chunk02a", "props_debris/concrete_chunk03a",
    "props_debris/concrete_chunk06c", "props_debris/concrete_chunk07a", "props_debris/concrete_debris128pile001a",
    "props_debris/concrete_debris128pile001b", "props_debris/concrete_debris256pile001a",
    "props_debris/concrete_debris256barricade001a", "props_debris/concrete_floorpile01a",
    "props_debris/concrete_wallpile01a", "props_debris/concrete_cornerpile01a", "props_debris/plaster_floorpile001a",
    "props_debris/plaster_ceilingpile001a", "props_debris/broken_pile001a", "props_debris/walldestroyed01a",
    "props_debris/walldestroyed03a", "props_debris/walldestroyed05a",  # not 02a: its courtyard face has no VMT
    "props_debris/walldestroyed09a", "props_debris/building_brokenexterior001a",
    "props_debris/building_brokenexterior002a", "props_debris/building_brokenpillar001c",
    "props_debris/rebar_cluster001a", "props_debris/rebar_cluster002a", "props_debris/beam01a",
    "props_debris/concrete_section128wall001a", "props_debris/concrete_section128floor001a",
    "props_debris/metal_panel01a", "props_debris/destroyedceiling01a", "props_debris/barricade_short01a",
    "props_debris/barricade_tall01a", "props_buildings/destroyed_cityblock01b", "props_buildings/destroyed_cityblock01d",
    "props_buildings/destroyed_cityblock01e", "props_buildings/destroyed_cityblock01f",
    "props_buildings/collapsedbuilding01awall", "props_buildings/collapsedbuilding02b",
    "props_buildings/collapsedbuilding02c", "props_buildings/project_destroyedbuildings01",
    "props_rooftop/parliament_dome_destroyed_exterior", "props_c17/overpass_001a", "props_c17/overpass_001b",
    "props_junk/garbage256_composite001a", "props_junk/garbage128_composite001a", "props_junk/trashcluster01a",
    "combine_apc_destroyed_gib01", "combine_apc_destroyed_gib02", "combine_apc_destroyed_gib03",
    # City 17 rooftops: aerials, chimneys, vents, roof clutter, scaffolding, dishes, gutters, broken railings
    "props_rooftop/antenna01a", "props_rooftop/antennaclusters01a", "props_rooftop/chimneypipe_cluster02a",
    "props_rooftop/roof_vent001", "props_rooftop/roof_vent002", "props_rooftop/rooftopcluser01a",
    "props_rooftop/rooftopcluser06a", "props_rooftop/rooftopcluser07a", "props_rooftop/rooftopcluser09a",
    "props_rooftop/rooftop_set01b", "props_rooftop/scaffolding01a", "props_rooftop/satellitedish02",
    "props_rooftop/roof_dish001", "props_rooftop/gutter_pipe_256", "props_c17/handrail04_long",
    "props_c17/handrail04_brokenlong",
    # Nova Prospekt: the prison seen from outside (three big pieces) and its depot, gates, doors and cell blocks,
    # beds, laundry, canteen, fences, lights; the Combine teleport of its last level and HL2's model of HL1's
    # teleporter (for the teleport rescues)
    "props_combine/prison01", "props_combine/prison01b", "props_combine/prison01c", "props_wasteland/depot",
    "props_wasteland/prison_archgate001", "props_wasteland/prison_archgate002a", "props_wasteland/prison_archwindow001",
    "props_wasteland/prison_gate001a", "props_wasteland/prison_slidingdoor001a", "props_wasteland/prison_heavydoor001a",
    "props_wasteland/prison_celldoor001a", "props_wasteland/prison_bedframe001a", "props_wasteland/prison_metalbed001a",
    "props_wasteland/prison_toilet01", "props_wasteland/prison_sink001a", "props_wasteland/prison_shelf001a",
    "props_wasteland/prison_lamp001a", "props_wasteland/prison_flourescentlight001a", "props_wasteland/prison_pipes001a",
    "props_wasteland/prison_switchbox001a", "props_debris/prison_wallchunk001a", "props_wasteland/laundry_cart001",
    "props_wasteland/laundry_dryer001", "props_wasteland/cafeteria_table001a", "props_wasteland/cafeteria_bench001a",
    "props_wasteland/kitchen_counter001a", "props_wasteland/shower_system001a", "props_wasteland/interior_fence001a",
    "props_wasteland/interior_fence002d", "props_wasteland/exterior_fence001a", "props_wasteland/speakercluster01a",
    "props_wasteland/lights_industrialcluster01a", "props_combine/combine_teleportplatform",
    "props_combine/combine_teleport_2", "props_combine/combine_tptimer", "props_lab/hl1teleport",
    # Episode Two antlion caves under Nova Prospekt: cave rocks, stalactites, mine struts and lamps, hive nests
    "props_mining/rock_caves01", "props_mining/caverocks_cluster01", "props_mining/caverocks_cluster02",
    "props_mining/stalactite_cluster01", "props_mining/stalactite_cluster02", "props_mining/stalactite_cluster03",
    "props_mining/stalactite_cluster04", "props_mining/stalactite_static01", "props_mining/stalactite_static02",
    "props_mining/struts_tunnel192_01", "props_mining/struts_tunnel320_01", "props_mining/lamps01",
    "props_hive/nest_lrg_flat", "props_hive/nest_med_flat", "props_hive/nest_sm_flat", "props_hive/egg",
    "props_hive/websackceiling01",
    # Episode Two forest: locomotives and cars (standing, wrecked, the whole long train of HL2's opening, the
    # cars that fell with the bridge in Episode Two), the see-saw bridge (the swinging span with its bones, the
    # same span in one piece, the concrete approaches), the forest bridges, pines, dead trees, logs, rocks, ferns,
    # fences and signs of White Forest
    "props_trainstation/train_engine", "props_trainstation/diesel", "props_trainstation/train_boxcar",
    "props_trainstation/train_boxcar_damaged", "props_trainstation/train_orecar", "props_trainstation/boxcar2a",
    "props_trainstation/passengercar001", "props_trainstation/train003", "props_trainstation/train003_damaged1",
    "props_trainstation/train004", "props_trainstation/train_outro_car01", "props_trainstation/wrecked_train",
    "map1_bridge/traincars", "seesawbridge/bridgemetal", "seesawbridge/bridgemetalnondynamic",
    "seesawbridge/bridge_static", "seesawbridge/bridge_static_exit", "props_outland/bridge01", "cliffs/bridge",
    "cliffs/bridge02", "props_foliage/tree_pine_01", "props_foliage/tree_pine_02", "props_foliage/tree_pine06",
    "props_foliage/tree_pine_tall_01", "props_foliage/tree_pine_tall_02", "props_foliage/tree_pine_cluster_01",
    "props_foliage/tree_dead02", "props_foliage/tree_dry01", "props_foliage/tree_dry02", "props_foliage/fallentree02",
    "props_foliage/fallentree_dry01", "props_foliage/tree_stump01", "props_foliage/rock_forest03",
    "props_foliage/rock_forest04", "props_foliage/forestrock_cluster01", "props_foliage/forestrock_single01",
    "props_foliage/ferns02", "props_foliage/fern01", "props_foliage/grass_cluster02", "props_foliage/grass_cluster03",
    "props_foliage/shrub_small", "props_forest/log", "props_forest/forest_log01", "props_forest/riverlogs",
    "props_forest/sawmill_logs", "props_forest/fence_trail_256", "props_forest/fence_border_256",
    "props_forest/whiteforestsign", "props_forest/utilitypole01b", "props_forest/sawhorse", "cliffs/rocks_large01",
    "cliffs/rocks_large01_veg", "cliffs/rocks_medium01", "cliffs/rocks_xlarge01", "cliffs/rockcluster01",
    "props_outland/haybale",
]

# chunk gibs for breakables
GIBS = {
    "props_junk/wood_crate001a": ["props_junk/wood_crate001a_chunk0%d" % i for i in (1, 2, 3, 4, 5, 6, 7, 9)],
    "props_junk/watermelon01": ["props_junk/watermelon01_chunk01a", "props_junk/watermelon01_chunk01b",
                                "props_junk/watermelon01_chunk01c", "props_junk/watermelon01_chunk02a",
                                "props_junk/watermelon01_chunk02b", "props_junk/watermelon01_chunk02c"],
}

WORLD_MATERIALS = [
    # roads, kerbs, pavements
    "concrete/concretefloor037a", "concrete/concretefloor037b", "concrete/concretefloor033k",
    "concrete/concretefloor033y", "concrete/concretefloor033p", "concrete/concretefloor028c",
    "concrete/concretefloor028d", "concrete/concretefloor011a", "concrete/concretefloor013a",
    "concrete/forest_road01", "concrete/blendroad_broken01", "nature/dirtroad001a", "nature/blendroadgrass001a",
    "stone/cobble08a", "concrete/concretefloor019a",
    # terrain (WorldVertexTransition blends)
    "nature/blendgrassgravel001a", "nature/blenddirtgrass001a", "nature/blendgrassdirt01", "nature/blendcliffgrass001a",
    "nature/blendrockblack01a", "nature/blendcliffsand01a", "nature/blenddirtgravel001a", "nature/grassfloor002a",
    "nature/dirtfloor003a", "nature/rockfloor005a", "nature/rockwall006a", "nature/rockwall021b",
    "nature/blendsandsand008a", "nature/sandfloor009a",
    # walls
    "concrete/concretewall008a", "concrete/concretewall011a", "concrete/concretewall033a", "concrete/concretewall041a",
    "concrete/concretewall044a", "concrete/concretewall064a", "concrete/concretewall070a",
    "stone/stonewall044a", "brick/brickwall031b", "brick/brickwall045c", "metal/metalwall048b",
    "metal/metalfence001a", "metal/metaltrack001a", "metal/metalcombine001", "metal/citadel_metalwall072a",
    "combine/combine_wall001", "combine/combinecrane001a", "plaster/plasterwall029a",
    # water + misc
    "nature/water_canals_water2", "nature/water_coast01", "nature/water_canals_city", "nature/canal_reeds",
    "nature/dirtfloor006a", "nature/blendsandgrass008a",
    "building_template/building_template002a", "building_template/building_template003a",
    "building_template/building_template004a", "building_template/building_template005a",
    "building_template/building_template006a", "building_template/building_template007a",
    "building_template/building_template012a", "building_template/building_template013a",
    "building_template/building_template019a", "building_template/building_template020a",
    "building_template/building_template022a", "building_template/building_template024a",
    "building_template/roof_template001a", "building_template/roof_template002a",
    "tile/tilefloor007a", "wood/woodfloor007a", "metal/metalfloor008a",
    "decals/decalstreet008a", "overlays/road_dirt_01a",
    # sprites / effects
    "sprites/glow01", "sprites/light_glow02_add", "sprites/orangeflare1", "sprites/redglow1", "sprites/blueglow1",
    "effects/ar2_altfire1", "effects/ar2_altfire1b", "effects/combinemuzzle2", "effects/fire_cloud1",
    "effects/fire_cloud2", "particle/particle_smokegrenade", "particle/smokesprites_0001", "particle/smokesprites_0003",
    "sprites/zerogxplode", "sprites/flamelet1", "sprites/flamelet2", "sprites/heatwave", "effects/fire_embers1", "effects/spark", "effects/yellowflare", "effects/blueflare1",
    "effects/strider_muzzle", "sprites/physbeam", "effects/tool_tracer", "effects/blueblacklargebeam",
    "effects/bluelaser1", "effects/laser1", "sprites/laserbeam", "effects/muzzleflash1", "effects/combine_binocoverlay",
    "decals/scorch1", "decals/rollermine_crater", "effects/fleck_cement1", "particle/fire", "effects/water_highlight",
    "particle/particle_glow_04_additive", "effects/splash2", "effects/splashwake1",
    # karts going into water / slime (Effects.splash / bubbles / drips)
    "effects/splash3", "effects/splashwake3", "effects/bubble", "effects/slime1",
    "particle/water/watersplash_001a", "particle/water/waterdrop_001a",
    # HUD / UI
    "vgui/hud/icon_locator", "console/background01", "console/background01_widescreen", "console/background02",
    "console/background03", "console/background04", "console/background05", "console/background06",
    "console/background07", "console/logo",
]

SKIES = ["sky_day01_01", "sky_day01_05", "sky_day01_06", "sky_day01_08", "sky_day02_02", "sky_day02_09",
         "sky_day03_06", "sky_borealis01"]

MUSIC = ["hl2_song12_long", "hl2_song14", "hl2_song16", "hl2_song20_submix0", "hl2_song29", "hl2_song31",
         "hl2_song3", "hl2_song4", "hl2_song15", "hl2_song25_teleporter", "hl2_song6", "hl2_song2",
         "hl2_song1", "hl2_song23_suitsong3", "hl2_song26", "hl2_song33", "hl2_song32", "hl2_intro",
         "vlvx_song27", "vlvx_song28", "vlvx_song22", "vlvx_song20", "vlvx_song4"]

SOUNDS = [
    # jeep
    "vehicles/v8/v8_idle_loop1.wav", "vehicles/v8/v8_start_loop1.wav", "vehicles/v8/v8_stop1.wav",
    "vehicles/v8/v8_rev_short_loop1.wav", "vehicles/v8/v8_firstgear_rev_loop1.wav", "vehicles/v8/first.wav",
    "vehicles/v8/second.wav", "vehicles/v8/third.wav", "vehicles/v8/fourth_cruise_loop2.wav",
    "vehicles/v8/v8_throttle_off_slow_loop2.wav", "vehicles/v8/v8_throttle_off_fast_loop1.wav",
    "vehicles/v8/v8_turbo_on_loop1.wav", "vehicles/v8/v8_turbo_off.wav", "vehicles/v8/skid_lowfriction.wav",
    "vehicles/v8/skid_normalfriction.wav", "vehicles/v8/skid_highfriction.wav",
    "vehicles/v8/vehicle_impact_heavy1.wav", "vehicles/v8/vehicle_impact_heavy2.wav",
    "vehicles/v8/vehicle_impact_heavy3.wav", "vehicles/v8/vehicle_impact_heavy4.wav",
    "vehicles/v8/vehicle_impact_medium1.wav", "vehicles/v8/vehicle_impact_medium2.wav",
    "vehicles/v8/vehicle_impact_medium3.wav", "vehicles/v8/vehicle_impact_medium4.wav",
    "vehicles/v8/vehicle_rollover1.wav", "vehicles/v8/vehicle_rollover2.wav",
    "vehicles/tank_readyfire1.wav", "vehicles/digger_grinder_loop1.wav",
    # weapons / items
    "weapons/explode3.wav", "weapons/explode4.wav", "weapons/explode5.wav",
    "weapons/irifle/irifle_fire2.wav", "weapons/physcannon/energy_bounce1.wav",
    "weapons/physcannon/energy_bounce2.wav", "weapons/physcannon/energy_sing_explosion2.wav",
    "weapons/physcannon/energy_sing_loop4.wav", "weapons/physcannon/superphys_launch1.wav",
    "weapons/physcannon/superphys_launch2.wav", "weapons/physcannon/physcannon_pickup.wav",
    "weapons/physcannon/hold_loop.wav", "weapons/physcannon/physcannon_drop.wav",
    "weapons/physcannon/physcannon_claws_open.wav", "weapons/physcannon/physcannon_dryfire.wav",
    "weapons/grenade/tick1.wav", "weapons/slam/mine_mode.wav",
    "weapons/gauss/fire1.wav", "weapons/gauss/chargeloop.wav", "weapons/crossbow/hit1.wav",
    "items/battery_pickup.wav", "items/suitchargeok1.wav", "items/medshot4.wav", "items/smallmedkit1.wav",
    "items/ammo_pickup.wav", "items/itempickup.wav", "items/ammocrate_open.wav", "items/flashlight1.wav",
    "items/suitcharge1.wav", "items/nvg_on.wav",
    "npc/manhack/mh_blade_loop1.wav", "npc/manhack/mh_engine_loop1.wav", "npc/manhack/grind1.wav",
    "npc/manhack/grind2.wav", "npc/manhack/grind_flesh1.wav", "npc/manhack/gib.wav", "npc/manhack/bat_away.wav",
    "npc/roller/mine/rmine_moveslow_loop1.wav", "npc/roller/mine/rmine_movefast_loop1.wav",
    "npc/roller/mine/rmine_blip1.wav", "npc/roller/mine/rmine_shockvehicle1.wav", "npc/roller/mine/rmine_explode_shock1.wav",
    "npc/roller/mine/rmine_tossed1.wav", "npc/roller/code2.wav", "npc/roller/blade_cut.wav",
    "npc/scanner/scanner_photo1.wav", "npc/scanner/scanner_blip1.wav", "npc/scanner/combat_scan_loop2.wav",
    "npc/scanner/scanner_siren1.wav", "npc/scanner/cbot_servoscared.wav",
    "npc/env_headcrabcanister/incoming.wav", "npc/env_headcrabcanister/launch.wav",
    "npc/env_headcrabcanister/explosion.wav", "npc/env_headcrabcanister/hiss.wav", "npc/env_headcrabcanister/land01.wav",
    "npc/headcrab/alert1.wav", "npc/headcrab/attack1.wav", "npc/headcrab/idle3.wav",
    "npc/strider/strider_step1.wav", "npc/strider/striderx_alert2.wav", "npc/strider/charging.wav",
    "npc/strider/fire.wav", "npc/combine_gunship/gunship_engine_loop3.wav",
    "npc/attack_helicopter/aheli_rotor_loop1.wav", "npc/combine_soldier/vo/contact.wav",
    "ambient/alarms/apc_alarm_loop1.wav", "ambient/alarms/scanner_alert_pass1.wav",
    "ambient/alarms/klaxon1.wav", "ambient/alarms/warningbell1.wav",
    "ambient/levels/streetwar/city_battle1.wav", "ambient/levels/streetwar/city_battle2.wav",
    "ambient/levels/streetwar/city_riot1.wav", "ambient/levels/coast/coastbird1.wav",
    "ambient/levels/coast/coastbird4.wav", "ambient/levels/coast/seagulls_ambient1.wav",
    "ambient/levels/coast/seagulls_ambient2.wav", "ambient/water/wave1.wav", "ambient/water/wave2.wav",
    "ambient/water/wave3.wav", "ambient/water/water_flow_loop1.wav", "ambient/wind/wind_snippet1.wav",
    "ambient/wind/windgust.wav", "ambient/atmosphere/city_rumble_loop1.wav", "ambient/atmosphere/city_skypass1.wav",
    "ambient/explosions/explode_1.wav", "ambient/explosions/explode_4.wav", "ambient/explosions/exp1.wav",
    "ambient/levels/citadel/citadel_flyer1.wav", "ambient/machines/thumper_hit.wav",
    "ambient/machines/thumper_dust.wav", "ambient/machines/thumper_startup1.wav",
    "ambient/energy/zap1.wav", "ambient/energy/zap5.wav", "ambient/energy/spark1.wav", "ambient/energy/spark2.wav",
    "ambient/levels/labs/electric_explosion1.wav",
    # UI / race
    "ui/buttonclick.wav", "ui/buttonclickrelease.wav", "ui/buttonrollover.wav", "ui/hint.wav",
    "buttons/button3.wav", "buttons/button9.wav", "buttons/button14.wav", "buttons/button15.wav",
    "buttons/button17.wav", "buttons/button19.wav", "buttons/blip1.wav", "buttons/bell1.wav",
    "buttons/combine_button1.wav", "buttons/combine_button7.wav", "buttons/lever7.wav",
    "npc/overwatch/radiovoice/one.wav", "npc/overwatch/radiovoice/two.wav", "npc/overwatch/radiovoice/three.wav",
    "npc/overwatch/radiovoice/on1.wav", "npc/overwatch/radiovoice/off2.wav", "npc/overwatch/radiovoice/off4.wav",
    "npc/overwatch/radiovoice/respond.wav", "npc/overwatch/radiovoice/attention.wav",
    "npc/overwatch/radiovoice/freeman.wav", "npc/overwatch/radiovoice/youarejudgedguilty.wav",
    "npc/overwatch/cityvoice/f_innactionisconspiracy_spkr.wav", "npc/overwatch/cityvoice/f_trainstation_assumepositions_spkr.wav",
    "npc/overwatch/cityvoice/fcitadel_15sectosingularity.wav",
    "npc/metropolice/vo/one.wav", "npc/metropolice/vo/two.wav", "npc/metropolice/vo/three.wav",
    "hl1/fvox/bell.wav", "hl1/fvox/beep.wav", "friends/friend_join.wav", "friends/message.wav",
    "player/suit_sprint.wav", "player/pl_drown1.wav", "player/pl_fallpain1.wav", "player/pl_fallpain3.wav",
    "physics/body/body_medium_impact_hard1.wav", "physics/body/body_medium_impact_hard2.wav",
    "physics/body/body_medium_impact_hard3.wav", "physics/glass/glass_impact_bullet1.wav",
    "physics/surfaces/sand_impact_bullet1.wav", "physics/concrete/concrete_impact_hard1.wav",
    "physics/concrete/concrete_impact_hard2.wav", "physics/concrete/concrete_impact_hard3.wav",
    "physics/metal/metal_solid_impact_hard1.wav", "physics/metal/metal_solid_impact_hard4.wav",
    "physics/metal/metal_solid_impact_hard5.wav", "physics/metal/metal_grate_impact_hard1.wav",
    "physics/wood/wood_crate_break1.wav", "physics/wood/wood_crate_break2.wav", "physics/wood/wood_crate_break3.wav",
    "physics/wood/wood_crate_break4.wav", "physics/wood/wood_crate_break5.wav", "physics/flesh/flesh_squishy_impact_hard1.wav",
    "physics/flesh/flesh_bloody_break.wav", "physics/plastic/plastic_barrel_impact_hard1.wav",
    "physics/metal/metal_box_break1.wav", "physics/metal/metal_box_break2.wav",
    "physics/cardboard/cardboard_box_break1.wav", "physics/cardboard/cardboard_box_break3.wav",
    "physics/metal/metal_barrel_impact_hard1.wav",
    # other vehicles: EP2 junker, Combine APC, Dog, the bathtub scraping along
    "vehicles/junker/jnk_first.wav", "vehicles/junker/jnk_second.wav", "vehicles/junker/jnk_third.wav",
    "vehicles/junker/jnk_fourth_cruise_loop2.wav", "vehicles/junker/jnk_idle_loop1.wav",
    "vehicles/junker/jnk_throttle_off_fast_loop1.wav", "vehicles/junker/jnk_throttle_off_slow_loop2.wav",
    "vehicles/junker/jnk_turbo_on_loop1.wav", "vehicles/junker/skid_normalfriction_nostartdelay.wav",
    "vehicles/apc/apc_cruise_loop3.wav", "vehicles/apc/apc_firstgear_loop1.wav", "vehicles/apc/apc_idle1.wav",
    "vehicles/apc/apc_slowdown_fast_loop5.wav", "vehicles/apc/apc_start_loop3.wav",
    "npc/dog/dog_idlemode_loop1.wav", "npc/dog/dog_combatmode_loop1.wav", "npc/dog/dog_playfull1.wav",
    "npc/dog/dog_laugh1.wav", "npc/dog/dog_pneumatic1.wav", "npc/dog/dog_angry1.wav", "npc/dog/car_impact1.wav",
    "physics/metal/metal_box_scrape_rough_loop1.wav", "physics/metal/metal_box_scrape_smooth_loop1.wav",
    # karts going into water / slime: splash, bubbles, the scanner fishing them out dripping
    "vehicles/airboat/pontoon_splash1.wav", "vehicles/airboat/pontoon_splash2.wav",
    "ambient/water/water_splash1.wav", "ambient/water/water_splash2.wav", "ambient/water/water_splash3.wav",
    "physics/surfaces/underwater_impact_bullet1.wav", "physics/surfaces/underwater_impact_bullet2.wav",
    "physics/surfaces/underwater_impact_bullet3.wav",
    "ambient/levels/canals/toxic_slime_sizzle1.wav", "ambient/levels/canals/toxic_slime_sizzle2.wav",
    "ambient/levels/canals/toxic_slime_sizzle3.wav", "ambient/levels/canals/toxic_slime_gurgle2.wav",
    "ambient/levels/canals/toxic_slime_gurgle4.wav", "ambient/levels/canals/toxic_slime_gurgle6.wav",
    "ambient/water/drip1.wav", "ambient/water/drip2.wav", "ambient/water/drip3.wav", "ambient/water/drip4.wav",
    # hazards: turrets, trains, aircraft, strider, mortars, tripmines, fields, arcs
    "npc/turret_floor/ping.wav", "npc/turret_floor/active.wav", "npc/turret_floor/deploy.wav",
    "npc/turret_floor/retract.wav", "npc/turret_floor/shoot1.wav", "npc/turret_floor/shoot2.wav",
    "npc/turret_floor/shoot3.wav",
    "weapons/fx/rics/ric1.wav", "weapons/fx/rics/ric2.wav", "weapons/fx/rics/ric3.wav", "weapons/fx/rics/ric4.wav",
    "weapons/fx/rics/ric5.wav", "weapons/fx/nearmiss/bulletltor03.wav", "weapons/fx/nearmiss/bulletltor05.wav",
    "weapons/fx/nearmiss/bulletltor07.wav",
    "ambient/alarms/train_crossing_bell_loop1.wav", "ambient/alarms/razortrain_horn1.wav",
    "ambient/alarms/train_horn2.wav", "ambient/machines/razor_train_wheels_loop1.wav",
    "ambient/machines/train_wheels_loop1.wav",
    "npc/strider/striderx_alert4.wav", "npc/strider/strider_hunt1.wav", "npc/strider/strider_hunt2.wav",
    "npc/strider/creak1.wav", "npc/strider/creak2.wav",
    "npc/combine_gunship/see_enemy.wav", "npc/combine_gunship/attack_start2.wav",
    "npc/combine_gunship/attack_stop2.wav", "npc/combine_gunship/gunship_fire_loop1.wav",
    "weapons/mortar/mortar_fire1.wav", "weapons/mortar/mortar_shell_incomming1.wav",
    "weapons/mortar/mortar_explode1.wav", "weapons/mortar/mortar_explode2.wav", "weapons/mortar/mortar_explode3.wav",
    "ambient/machines/combine_shield_loop3.wav", "ambient/machines/combine_shield_touch_loop1.wav",
    "ambient/energy/force_field_loop1.wav", "ambient/energy/zap2.wav", "ambient/energy/zap3.wav",
    "ambient/energy/zap6.wav", "ambient/energy/zap7.wav", "ambient/energy/zap8.wav", "ambient/energy/zap9.wav",
    "ambient/energy/newspark04.wav", "ambient/energy/newspark08.wav",
    "ambient/levels/labs/electric_explosion2.wav", "ambient/levels/labs/electric_explosion4.wav",
    # spares for later hazards: the Combine sniper, the Hunter-Chopper's bombs
    "npc/sniper/sniper1.wav", "npc/sniper/echo1.wav", "npc/attack_helicopter/aheli_mine_drop1.wav",
    "npc/attack_helicopter/aheli_megabomb_siren1.wav",
] + ["npc/dog/dog_footstep_run%02d.wav" % i for i in range(1, 10)] + ["vo/breencast/br_welcome%02d.wav" % i for i in range(1, 8)]   + ["vo/breencast/br_collaboration%02d.wav" % i for i in range(1, 12)]   + ["vo/breencast/br_instinct%02d.wav" % i for i in range(1, 12)]   + ["vo/breencast/br_overwatch%02d.wav" % i for i in range(1, 10)]

# racer voice lines: hit = when they hit someone, hurt = when they get hit, win/lose/start
VOICES = {
    "vortigaunt": {"hit": ["vo/npc/vortigaunt/vort_skillsformidable.wav", "vo/npc/vortigaunt/vortigese05.wav",
                           "vo/npc/vortigaunt/yes.wav"],
                   "hurt": ["vo/npc/vortigaunt/vortigese08.wav", "vo/npc/vortigaunt/vortigese11.wav",
                            "vo/npc/vortigaunt/vortigese03.wav"],
                   "win": ["vo/npc/vortigaunt/vort_goodfightwithus.wav", "vo/npc/vortigaunt/vort_goodtogether.wav"],
                   "start": ["vo/npc/vortigaunt/yesforward.wav", "vo/npc/vortigaunt/wewillcharge.wav"]},
    "zombie": {"hit": ["npc/zombie/zo_attack1.wav", "npc/zombie/zo_attack2.wav", "npc/zombie/zombie_alert2.wav"],
               "hurt": ["npc/zombie/zombie_pain1.wav", "npc/zombie/zombie_pain3.wav", "npc/zombie/zombie_pain5.wav"],
               "win": ["npc/zombie/zombie_alert3.wav", "npc/zombie/zombie_voice_idle3.wav"],
               "start": ["npc/zombie/zombie_alert1.wav"]},
    "alyx": {"hit": ["vo/episode_1/npc/alyx/al_combat_niceshot01.wav", "vo/episode_1/npc/alyx/al_dark_gotcha.wav",
                     "vo/episode_1/npc/alyx/al_combat_whoanice01.wav", "vo/npc/alyx/al_car_laughing06.wav"],
             "hurt": ["vo/npc/alyx/hurt04.wav", "vo/npc/alyx/hurt06.wav", "vo/npc/alyx/ohno_startle01.wav"],
             "win": ["vo/episode_1/npc/alyx/al_laugh01.wav", "vo/episode_1/npc/alyx/al_laugh03.wav",
                     "vo/npc/alyx/al_car_laughing10.wav"],
             "start": ["vo/npc/alyx/al_car_laughing08.wav"]},
    "barney": {"hit": ["vo/npc/barney/ba_laugh01.wav", "vo/npc/barney/ba_laugh02.wav", "vo/npc/barney/ba_letsgo.wav"],
               "hurt": ["vo/npc/barney/ba_damnit.wav", "vo/npc/barney/ba_pain01.wav", "vo/npc/barney/ba_ohshit03.wav"],
               "win": ["vo/npc/barney/ba_laugh03.wav", "vo/npc/barney/ba_laugh04.wav"],
               "start": ["vo/npc/barney/ba_letsgo.wav", "vo/npc/barney/ba_heretheycome01.wav"]},
    "kleiner": {"hit": ["vo/k_lab/kl_excellent.wav", "vo/k_lab2/kl_greatscott.wav", "vo/outland_11a/silo/kl_silo_yesyes.wav"],
                "hurt": ["vo/k_lab/kl_fiddlesticks.wav", "vo/k_lab/kl_ohdear.wav", "vo/k_lab/kl_dearme.wav"],
                "win": ["vo/k_lab/kl_excellent.wav"], "start": ["vo/k_lab/kl_lamarr.wav"]},
    "eli": {"hit": ["vo/eli_lab/eli_handle.wav", "vo/outland_11a/silo/eli_silo_hadalook01.wav"],
            "hurt": ["vo/episode_1/intro/eli_what01.wav", "vo/novaprospekt/eli_whatgoingon.wav", "vo/citadel/eli_damnbreen.wav"],
            "win": ["vo/eli_lab/eli_lookgordon.wav", "vo/outland_11a/silo/eli_silo_thankyou01.wav"],
            "start": ["vo/eli_lab/eli_gowithalyx01.wav"]},
    "monk": {"hit": ["vo/ravenholm/monk_kill01.wav", "vo/ravenholm/monk_kill02.wav", "vo/ravenholm/monk_kill03.wav",
                     "vo/ravenholm/monk_kill04.wav"],
             "hurt": ["vo/ravenholm/monk_pain01.wav", "vo/ravenholm/monk_pain02.wav", "vo/ravenholm/monk_pain03.wav"],
             "win": ["vo/ravenholm/monk_blocked01.wav", "vo/ravenholm/cartrap_better.wav"],
             "start": ["vo/ravenholm/firetrap_vigil.wav", "vo/ravenholm/monk_rant01.wav"]},
    # his Citadel taunts (2.6-4 s): the Breencasts run 15-48 s and kept the crowd silent after every hit
    "breen": {"hit": ["vo/citadel/br_mock06.wav", "vo/citadel/br_mock09.wav", "vo/citadel/br_mock04.wav",
                      "vo/citadel/br_mock07.wav"],
              "hurt": ["vo/citadel/br_ohshit.wav", "vo/citadel/br_no.wav", "vo/citadel/br_youfool.wav"],
              "win": ["vo/breencast/br_welcome01.wav", "vo/citadel/br_laugh01.wav"],
              "start": ["vo/breencast/br_welcome01.wav", "vo/breencast/br_collaboration01.wav"]},
    "gman_high": {"hit": ["vo/episode_1/npc/gman/gman_wellseeaboutthat.wav", "vo/gman_misc/gman_04.wav"],
                  "hurt": ["vo/episode_1/npc/gman/gman_inhale.wav", "vo/gman_misc/gman_03.wav"],
                  "win": ["vo/gman_misc/gman_02.wav"], "start": ["vo/gman_misc/gman_riseshine.wav"]},
    "police": {"hit": ["npc/metropolice/vo/pickupthecan1.wav", "npc/metropolice/vo/sentencedelivered.wav",
                       "npc/metropolice/vo/chuckle.wav", "npc/metropolice/vo/isaidmovealong.wav"],
               "hurt": ["npc/metropolice/vo/11-99officerneedsassistance.wav", "npc/metropolice/pain1.wav",
                        "npc/metropolice/pain2.wav", "npc/metropolice/vo/lookout.wav"],
               "win": ["npc/metropolice/vo/movealong.wav", "npc/metropolice/vo/movealong3.wav"],
               "start": ["npc/metropolice/vo/readytoprosecute.wav", "npc/metropolice/vo/prosecute.wav"]},
}


def _seq(fmt, first, last):
    return [fmt % i for i in range(first, last + 1)]


def _in(folder, *names):
    return ["%s/%s.wav" % (folder, n) for n in names]


def _cit(*names):
    """The same line from the male and the female citizen."""
    return [p for n in names for p in _in("vo/npc/male01", n) + _in("vo/npc/female01", n)]


# Phase D sounds. Antlions (idle, digging up and down, attacks, wings, steps, pain; the Episode Two
# workers' acid and burst), the antlion guard (roars, growls, heavy steps near and far, the shove, its
# breathing) and grubs; antlion hills, sand impacts and steps; the thumper's loop
SOUNDS += (
    _in("npc/antlion", "idle1", "idle2", "idle3", "idle4", "idle5", "digup1", "digdown1", "attack_single1",
        "attack_single2", "attack_single3", "attack_double1", "attack_double2", "attack_double3", "fly1", "foot1",
        "foot2", "foot3", "foot4", "land1", "pain1", "pain2", "rumble1", "distract1", "shell_impact1",
        "shell_impact2", "antlion_burst1", "antlion_preburst_scream1", "antlion_shoot1", "antlion_poisonball1") +
    _in("npc/antlion_guard", "angry1", "angry2", "angry3", "growl_high", "growl_idle", "foot_heavy1", "foot_heavy2",
        "foot_light1", "foot_light2", "shove1", "confused1", "antlion_guard_die1", "breathe_loop",
        "frustrated_growl1", "frustrated_growl2", "frustrated_growl3", "near_foot_heavy1", "near_foot_heavy2",
        "far_foot_heavy1", "far_foot_heavy2", "antlion_guard_pain1") +
    _in("npc/antlion_grub", "agrub_idle1", "agrub_idle3", "agrub_idle6", "agrub_alert1", "agrub_squish1",
        "agrub_squish2", "agrub_squish3", "squashed") +
    _in("ambient/levels/coast", "antlion_hill_ambient1", "antlion_hill_ambient2", "antlion_hill_ambient4") +
    _seq("physics/surfaces/sand_impact_bullet%d.wav", 2, 4) + _seq("player/footsteps/sand%d.wav", 1, 4) +
    _in("ambient/machines", "thumper_amb", "thumper_top", "thumper_shutdown1"))
# the dock crane (engine, turning, boom, creaks) and its magnet grabbing and letting go
SOUNDS += (
    _in("vehicles/crane", "crane_creak1", "crane_creak2", "crane_creak3", "crane_creak4", "crane_extend_loop1",
        "crane_extend_stop", "crane_idle_loop3", "crane_magnet_grab", "crane_magnet_release", "crane_magnet_switchon",
        "crane_slow_to_idle_loop4", "crane_startengine1", "crane_turn_loop2") +
    _in("plats/crane", "vertical_start", "vertical_stop"))
# rescues: HL2's teleports (Kleiner's lab: the suck-in before the blast, the thunder after it) for the teleport
# and the Combine teleport, the vortigaunts' green energy for the forest's vortigaunt rescue
SOUNDS += (
    _in("ambient/machines", "teleport1", "teleport3", "teleport4") +
    _in("ambient/levels/labs", "teleport_preblast_suckin1", "teleport_postblast_thunder1",
        "teleport_postblast_winddown1", "teleport_winddown1", "teleport_mechanism_windup1", "teleport_active_loop1") +
    _in("npc/vort", "attack_charge", "attack_shoot", "health_charge", "vort_attack_shoot1", "vorthealsingle_loop",
        "vort_dispell"))
# the marching Combine column (gear rattle, boots, distant marching, radio lines, Nova Prospekt's antlion calls),
# the hunter, the striders walking and firing their guns, ruins collapsing and the battle in the distance
SOUNDS += (
    _seq("npc/combine_soldier/gear%d.wav", 1, 6) + _in("npc/combine_soldier", "pain1", "pain2", "pain3", "die1") +
    _seq("npc/footsteps/hardboot_generic%d.wav", 1, 6) + ["npc/footsteps/hardboot_generic8.wav"] +
    _in("ambient/levels/streetwar", "marching_distant1", "marching_distant2") +
    _in("npc/combine_soldier/vo", "on1", "on2", "off1", "off2", "off3", "movein", "gosharp", "prepforcontact",
        "readyweapons", "affirmative", "copy", "sectorisnotsecure", "stayalert", "engaging",
        "prison_soldier_freeman_antlions", "prison_soldier_boomersinbound", "prison_soldier_bunker1",
        "swarmoutbreakinsector", "weareinaninfestationzone") +
    _in("npc/ministrider", "hunter_alert1", "hunter_angry1", "hunter_idle1", "hunter_idle2", "hunter_laugh1",
        "hunter_foundenemy1", "hunter_charge3", "hunter_prestrike1", "hunter_fire_loop3", "ministrider_fire1",
        "ministrider_footstep1", "ministrider_footstep2", "ministrider_footstep3", "flechette_explode1",
        "flechetteltor01") +
    _seq("npc/strider/strider_step%d.wav", 2, 6) + _in("npc/strider", "strider_minigun", "strider_minigun2") +
    _in("ambient/levels/streetwar", "building_rubble1", "building_rubble2", "building_rubble3", "building_rubble4",
        "building_rubble5", "strider_distant1", "strider_distant2", "strider_distant_walk1", "city_battle3",
        "city_battle4"))
# Nova Prospekt (radio chatter, the battle inside, the quiet cell block, alarms) and the antlion caves
# (cave hits, rumbles, crickets, distant growls and grubs)
SOUNDS += (
    _seq("ambient/levels/prison/radio_random%d.wav", 1, 6) +
    _in("ambient/levels/prison", "inside_battle_antlion1", "inside_battle_antlion2", "inside_battle_antlion3",
        "inside_battle_soldier1") +
    _in("ambient/atmosphere", "quiet_cellblock_amb", "cave_hit1", "cave_hit2", "cave_hit3", "terrain_rumble1") +
    _in("ambient/alarms", "alarm1", "combine_bank_alarm_loop1") +
    _in("ambient/levels/caves", "cave_crickets_loop1", "cave_howl_loop1", "dist_growl1", "dist_growl2", "dist_grub1",
        "dist_grub2", "rumble1", "rumble2"))
# the Episode Two forest: trains far and near, the see-saw bridge straining and creaking, planks underwheel,
# wind in the trees and birds
SOUNDS += (
    _in("ambient/alarms", "train_horn_distant1") +
    _in("ambient/machines", "train_freight_loop1", "train_rumble", "train_idle", "station_train_squeel",
        "train_wheels_overhead_loop1") +
    _seq("physics/metal/metal_solid_strain%d.wav", 1, 5) +
    _in("physics/metal", "metal_box_strain1", "metal_box_strain2") +
    _in("ambient/materials", "creaking", "creak5", "wood_creak1", "wood_creak2", "wood_creak3") +
    _in("doors", "drawbridge_move1", "drawbridge_stop1") +
    _seq("physics/wood/wood_plank_impact_hard%d.wav", 1, 5) +
    _in("physics/wood", "wood_plank_break1", "wood_plank_scrape_rough_loop1") +
    _in("ambient/levels/forest", "treewind1", "treewind2", "dist_birds1", "dist_birds2", "dist_birds3", "peckr1"))
# HL1: the bullsquid ("bullchicken" in Half-Life's files), the controller, houndeyes running in packs, and the
# teleports (Black Mesa's beam-in, the portal suck-in and -out, the Nihilanth's teleport and energy ball)
HL1_SOUNDS += (
    _in("bullchicken", "bc_acid1", "bc_acid2", "bc_attack1", "bc_attack2", "bc_attack3", "bc_attackgrowl",
        "bc_attackgrowl2", "bc_attackgrowl3", "bc_bite1", "bc_bite2", "bc_bite3", "bc_die1", "bc_idle1", "bc_idle2",
        "bc_idle3", "bc_idle4", "bc_idle5", "bc_pain1", "bc_pain2", "bc_pain3", "bc_pain4", "bc_spithit1",
        "bc_spithit2", "bc_spithit3") +
    _in("controller", "con_alert1", "con_alert2", "con_alert3", "con_attack1", "con_attack2", "con_attack3",
        "con_die1", "con_idle1", "con_idle2", "con_idle3", "con_idle4", "con_idle5", "con_pain1", "con_pain2",
        "con_pain3") +
    _in("houndeye", "he_hunt1", "he_hunt2", "he_hunt3", "he_hunt4", "he_alert3", "he_idle2", "he_idle3") +
    ["debris/beamstart%d.wav" % i for i in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15)] +  # 12 and 13 do not exist
    _in("ambience", "port_suckin1", "port_suckout1") + _in("x", "x_teleattack1", "x_ballattack1"))


# spectators' lines and loops, indexed as voices.json "_crowd": {role: {category: [res paths]}};
# "hl1:" paths come from Half-Life's valve/sound
_ODESSA = ("vo/coast/odessa/male01", "vo/coast/odessa/female01")
_MP, _VORT, _SCI, _BAR, _HOLO = "npc/metropolice/vo", "vo/npc/vortigaunt", "hl1:scientist", "hl1:barney", "hl1:holo"
CROWD_VOICES = {
    "citizen": {
        "cheer": (_seq(_ODESSA[0] + "/nlo_cheer%02d.wav", 1, 4) + _seq(_ODESSA[1] + "/nlo_cheer%02d.wav", 1, 3) +
                  _cit("yeah02", "fantastic01", "fantastic02", "likethat", "gotone01", "gotone02") +
                  _in("vo/npc/male01", "nice", "oneforme") + _in("vo/npc/female01", "nice01", "nice02")),
        "gordon": _cit("ahgordon01", "ahgordon02", "docfreeman01", "docfreeman02", "freeman", "hellodrfm01",
                       "hellodrfm02", "heydoc01", "hi01", "hi02"),
        "gordon_lead": _cit("finally", "abouttime01", "abouttime02"),
        "gordon_lose": _cit("notthemanithought01", "notthemanithought02", "wetrustedyou01", "wetrustedyou02"),
        "gordon_warn": _cit("lookoutfm01", "lookoutfm02"),
        "scared": _cit("ohno", "goodgod", "uhoh", "startle01", "startle02"),
        "fall": _cit("whoops01", "uhoh", "ohno"),
        "dodge": _cit("watchout", "excuseme01", "gethellout", "startle01", "startle02"),
        "headcrab": _cit("headcrabs01", "headcrabs02"),
        "zombie": _cit("zombies01", "zombies02", "runforyourlife01", "runforyourlife02"),
        "combine": _cit("civilprotection01", "cps01", "combine01"),
        "dog": _seq("vo/outland_11/dogfight/reb1_str_dogcheers%02d.wav", 1, 4),
        "start": ([p for d in _ODESSA for p in _in(d, "nlo_citizen_drivesafe")] +
                  [p for d in _ODESSA for p in _seq(d + "/nlo_citizen_greet%02d.wav", 1, 4)] +
                  _cit("letsgo01", "letsgo02")),
    },
    "metrocop": {
        "boo_rebel": _in(_MP, "anticitizen", "prepareforjudgement", "firstwarningmove", "secondwarning",
                         "finalwarning", "youwantamalcomplianceverdict", "lookingfortrouble", "getoutofhere",
                         "isaidmovealong", "malcompliant10107my1020", "criminaltrespass63"),
        "freeman": _in(_MP, "freeman", "thereheis", "allunitscloseonsuspect", "matchonapblikeness"),
        "speed": _in(_MP, "subjectisnowhighspeed", "hesrunning"),
        "salute": _in(_MP, "affirmative", "copy", "readytoprosecute", "sentencedelivered"),
        "knock": _in(_MP, "pickupthecan1", "pickupthecan2", "pickupthecan3", "putitinthetrash1", "putitinthetrash2",
                     "youknockeditover"),
        "scared": _in(_MP, "takecover", "lookout", "watchit", "holdit", "dontmove"),
        "chuckle": _in(_MP, "chuckle", "movealong"),
        "gear": _seq("npc/metropolice/gear%d.wav", 1, 6),
        "baton": (_seq("weapons/stunstick/spark%d.wav", 1, 3) + _seq("weapons/stunstick/stunstick_impact%d.wav", 1, 2) +
                  _seq("weapons/stunstick/stunstick_swing%d.wav", 1, 2)),
    },
    "scientist": {
        "freeman": _in(_SCI, "freeman", "ahfreeman", "hellofreeman", "c1a0_sci_itsyou", "goodtoseeyou", "greetings",
                       "hello", "newhevsuit"),
        "alive": _in(_SCI, "freemanalive", "c1a3_sci_atlast", "c1a3_sci_thankgod"),
        "cheer": _in(_SCI, "excellentteam", "fascinating", "stimulating", "absolutely", "yes", "yees", "perfectday"),
        "scream": (_seq(_SCI + "/scream%02d.wav", 1, 10) + _seq(_SCI + "/sci_fear%d.wav", 1, 7) +
                   _seq(_SCI + "/startle%d.wav", 1, 5) + _in(_SCI, "nooo", "noplease")),
        "headcrab": _in(_SCI, "headcrab", "seeheadcrab"),
        "fall": _in(_SCI, "ridiculous", "youinsane", "madness"),
        "idle": _in(_SCI, "cough", "sneeze"),
    },
    "guard": {"freeman": _in(_BAR, "mrfreeman", "hellonicesuit", "howdy", "heybuddy"),
              "cheer": _in(_BAR, "yougotit", "youbet", "ba_gotone"), "beer": _in(_BAR, "beertopside"),
              "bye": _in(_BAR, "ba_later")},
    "vort": {
        "freeman": _in(_VORT, "itisthefm", "isitthefm", "thefreeman", "greetingsfm", "fmhonorsus", "fmdoesushonor",
                       "forthefm"),
        "revere": (_seq(_VORT + "/vort_grp_agree%02d.wav", 1, 7) +
                   _in(_VORT, "ourhonor", "wehonored", "salute", "vort_grp_greetings04", "weknowyou", "wellmet")),
        "cheer": _in(_VORT, "vort_excellent", "vort_exceptional", "gloriousend", "prevail", "satisfaction",
                     "forfreedom"),
        "scared": _in(_VORT, "caution", "cautionfm", "standclear", "movingtarget"),
        "boo": _in(_VORT, "worthless", "undeserving", "regrettable"),
        "chant": _seq("npc/vort/ol02singlechant%02d.wav", 1, 3) + ["npc/vort/ol02dblchant02.wav"],
    },
    "islave": {"chant": _seq("hl1:aslave/slv_word%d.wav", 1, 8),
               "alert": _in("hl1:aslave", "slv_alert1", "slv_alert3", "slv_alert4")},
    "hecu": {"freeman": _in("hl1:hgrunt", "freeman!"), "salute": _in("hl1:hgrunt", "yessir!"),
             "laugh": _in("hl1:hgrunt", "c2a3_hg_laugh"), "scared": _in("hl1:hgrunt", "god!", "shit!"),
             "cheer": _in("hl1:hgrunt", "go!", "move!"), "alien": _in("hl1:hgrunt", "alien!")},
    "zombie": {"idle": ["npc/zombie/zombie_voice_idle%d.wav" % i for i in (1, 2, 3, 5, 7, 9)],
               "moan": _seq("npc/zombie/moan_loop%d.wav", 1, 2), "foot": _seq("npc/zombie/foot%d.wav", 1, 3)},
    "gman": {"hl2": _in("vo/gman_misc", "gman_02", "gman_03", "gman_04"),
             "hl1": (_in("hl1:gman", "gman_choose1", "gman_choose2", "gman_wise", "gman_potential") +
                     _seq("hl1:gman/gman_mumble%d.wav", 1, 3))},
    "holo": {"approach": _in(_HOLO, "tr_holo_jumpgap", "tr_holo_longjump"),
             "fall": _in(_HOLO, "tr_holo_fallshort", "tr_holo_tryagain", "tr_holo_keeptrying"),
             "good": _in(_HOLO, "tr_holo_nicejob", "tr_holo_greatwork", "tr_holo_fantastic"),
             "win": _in(_HOLO, "tr_holo_congrats"), "start": _in(_HOLO, "tr_holo_commencing", "tr_holo_runstart")},
    "breen": {"to_freeman": _seq("vo/breencast/br_tofreeman%02d.wav", 1, 12),
              "disruptor": _seq("vo/breencast/br_disruptor%02d.wav", 1, 8),
              "mock": _in("vo/citadel", "br_mock01", "br_mock04", "br_mock05", "br_mock06", "br_mock07", "br_mock09",
                          "br_mock13"),
              "rabble": _in("vo/citadel", "br_rabble_a", "br_rabble_b", "br_rabble_c", "br_rabble_d"),
              "lose": _in("vo/citadel", "br_youfool", "br_failing11", "br_nopoint", "br_stubborn", "br_worthit"),
              "at_last": _in("vo/citadel", "br_freemanatlast"), "laugh": _in("vo/citadel", "br_laugh01")},
    "overwatch": {"freeman": _in("npc/overwatch/cityvoice", "fprison_freemanlocated"),
                  "unrest": _in("npc/overwatch/cityvoice", "f_localunrest_spkr", "f_anticitizenreport_spkr",
                                "f_evasionbehavior_2_spkr", "f_ceaseevasionlevelfive_spkr",
                                "f_capitalmalcompliance_spkr")},
    "nihilanth": {"laugh": _in("hl1:x", "x_laugh1", "x_laugh2")},
    "lamarr": {"kleiner": _in("vo/k_lab", "kl_heremypet01", "kl_heremypet02"), "hop": ["npc/headcrab/idle3.wav"]},
    "birds": {"crow": (_seq("npc/crow/alert%d.wav", 1, 3) + _in("npc/crow", "crow2", "crow3", "hop1", "hop2") +
                       _seq("npc/crow/idle%d.wav", 1, 4)),
              "pigeon": _seq("ambient/creatures/pigeon_idle%d.wav", 1, 4),
              "seagull": _seq("ambient/creatures/seagull_idle%d.wav", 1, 3),
              "boid": _in("hl1:boid", "boid_alert1", "boid_alert2") + _seq("hl1:boid/boid_idle%d.wav", 1, 3),
              "flap": ["npc/crow/flap2.wav"]},
    "beds": {"human": ["ambient/voices/appartments_crowd_loop1.wav"],
             "riot": _in("ambient/levels/streetwar", "city_riot1", "city_riot2"),
             "alien": _in("hl1:ambience", "alien_chatter", "alien_hollow")},
    "loudspeaker": {"win": _in("vo/outland_12", "cit_loudspeaker_victory", "cit_loudspeaker_wedidit")},
}

FONTS = ["halflife2.ttf", "hl2ep2.ttf", "hl2crosshairs.ttf", "dejavusans.ttf"]


def log(*a):
    print(*a, flush=True)


def hl1_sound(rel):
    """Copy Half-Life's valve/sound/<rel> to assets/sound/hl1src ("!" becomes "_x").
    Returns the path under assets/, or None if this install lacks it."""
    src = os.path.join(HL1_ROOT, "valve", "sound", rel)
    if not os.path.exists(src):
        log("  -- missing HL1 sound", rel)
        return None
    dst_rel = "sound/hl1src/" + rel.replace("!", "_x")
    dst = os.path.join(ASSETS, dst_rel)
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(src, "rb") as fsrc:
            wav, _ = sounds.convert_wav(fsrc.read())
        with open(dst, "wb") as fdst:
            fdst.write(wav)
    return dst_rel


def surface_props(fs):
    """Merge surfaceproperties*.txt (with 'base' inheritance) and resolve impact sounds to wav lists."""
    raw = {}
    man = keyvalues.parse(fs.read("scripts/surfaceproperties_manifest.txt").decode("latin-1"))
    files = keyvalues.kv_get_all(man[0][1], "file") + ["scripts/surfaceproperties_ep2.txt"]
    for f in files:
        d = fs.read(f)
        if not d:
            continue
        for name, body in keyvalues.parse(d.decode("latin-1")):
            if isinstance(body, list):
                raw[name.lower()] = {k.lower(): v for k, v in body if not isinstance(v, list)}
    resolved = {}

    def get(n, depth=0):
        if n in resolved:
            return resolved[n]
        r = dict(raw.get("default", {})) if n != "default" else {}
        src = raw.get(n, {})
        if "base" in src and depth < 10:
            r.update(get(src["base"].lower(), depth + 1))
        r.update(src)
        resolved[n] = r
        return r

    for n in raw:
        get(n)
    # game sound name -> waves
    gs = {}
    for f in ["scripts/game_sounds_physics.txt", "scripts/game_sounds.txt", "scripts/game_sounds_ep2.txt",
              "scripts/game_sounds_world.txt"]:
        d = fs.read(f)
        if not d:
            continue
        for name, body in keyvalues.parse(d.decode("latin-1")):
            if not isinstance(body, list):
                continue
            waves = keyvalues.kv_get_all(body, "wave")
            rnd = keyvalues.kv_get(body, "rndwave")
            if isinstance(rnd, list):
                waves += keyvalues.kv_get_all(rnd, "wave")
            vol = keyvalues.kv_get(body, "volume", "1")
            gs[name.lower()] = {"waves": [w.lstrip("*#@)^<>").replace(chr(92), "/") for w in waves], "volume": vol}
    return resolved, gs


def model_todo():
    """(kind, "models/<key>.mdl") for every HL2 model in the lists: racers, props, breakables' gibs, spectators."""
    todo = [("drivers", "models/%s.mdl" % d) for d in DRIVERS] + [("props", "models/%s.mdl" % m) for m in MODELS]
    for parent, gibs in GIBS.items():
        todo += [("gibs", "models/%s.mdl" % g) for g in gibs]
    todo += [("crowd", "models/%s.mdl" % m) for m in CROWD_MODELS]
    return todo


def convert_model(fs, lib, kind, path, force=False):
    """Convert one HL2 model into assets/models. Returns (key, its models.json entry), or None when this
    install lacks the model or it does not convert (both are logged)."""
    if not fs.exists(path):
        log("  -- missing model", path)
        return None
    try:
        meta = mdl.convert(fs, lib, path, ASSETS + "/", bodygroups=BODYGROUPS.get(path), force=force)
        key = path[len("models/") : -4]
        entry = {"gltf": "res://assets/models/" + key + ".gltf", "meta": "res://assets/models/" + key + ".json",
                 "mass": meta["mass"], "surfaceprop": meta["surfaceprop"],
                 "aabb_min": meta.get("aabb_min"), "aabb_max": meta.get("aabb_max"), "kind": kind}
        log("model", key, "%.0fkg" % meta["mass"], meta["surfaceprop"])
        return key, entry
    except Exception as e:  # noqa
        log("  !! model", path, repr(e))
        return None


def hl1_jobs():
    """(key, candidates under HL1_ROOT, bodygroups, kind) for the HL1 racers and spectators."""
    return [(k, c, bg, "drivers") for k, c, bg in HL1_MODELS] + [(k, c, bg, "crowd") for k, c, bg in HL1_CROWD]


def convert_hl1(lib, key, candidates, bg, kind):
    """Convert an HL1 racer or spectator from the first candidate this install has. Returns its models.json
    entry, or None when it has none of them. Its textures' materials go into lib.db."""
    import goldsrc_mdl
    src = next((os.path.join(HL1_ROOT, c) for c in candidates if os.path.exists(os.path.join(HL1_ROOT, c))), None)
    if src is None:
        log("  -- missing HL1 model", key)
        return None
    # racers' bodygroups are meant for the HD and HEV models (Opposing Force's Shephard has his own)
    if kind == "drivers" and not ("valve_hd" in src or "gordon" in src):
        bg = {}
    meta, mats = goldsrc_mdl.convert(src, key, ASSETS, bg)
    lib.db.update(mats)
    log("hl1 model", key, src)
    return {"gltf": "res://assets/models/%s.gltf" % key, "meta": "res://assets/models/%s.json" % key,
            "mass": 90.0, "surfaceprop": "flesh", "aabb_min": meta["aabb_min"],
            "aabb_max": meta["aabb_max"], "kind": kind}


def hl1_prop_key(name):
    """models.json key of an HL1_PROPS entry: "fungus(large)" -> "hl1/fungus_large"."""
    return "hl1/" + name.replace("(", "_").replace(")", "")


def convert_hl1_prop(lib, name):
    """Convert valve/models/<name>.mdl. Returns (key, its models.json entry), or None when this install lacks
    it or it does not convert (both are logged). Its textures' materials go into lib.db."""
    import goldsrc_mdl
    src = os.path.join(HL1_ROOT, "valve", "models", name + ".mdl")
    if not os.path.exists(src):
        log("  -- missing HL1 prop", name)
        return None
    key = hl1_prop_key(name)
    try:
        meta, mats = goldsrc_mdl.convert(src, key, ASSETS, {})
    except Exception as e:  # noqa
        log("  !! HL1 prop", name, repr(e))
        return None
    lib.db.update(mats)
    log("hl1 prop", key)
    return key, {"gltf": "res://assets/models/%s.gltf" % key, "meta": "res://assets/models/%s.json" % key,
                 "mass": 200.0, "surfaceprop": "metal", "aabb_min": meta["aabb_min"],
                 "aabb_max": meta["aabb_max"], "kind": "props"}


def write_anims(fs, keys=None):
    """assets/models/<key>.anims.json for each ANIMS entry (tools/mdl_anim.py), or only for the given keys."""
    for key, (src, names) in ANIMS.items():
        if keys is not None and key not in keys:
            continue
        if not fs.exists(src):
            log("  -- missing animations", src)
            continue
        try:
            got = mdl_anim.anims(fs, src, list(names.values()))
        except Exception as e:  # noqa
            log("  !! animations", src, repr(e))
            continue
        out = {ours: got[theirs] for ours, theirs in names.items() if theirs in got}
        with open(os.path.join(ASSETS, "models", key + ".anims.json"), "w") as f:
            json.dump(out, f, separators=(",", ":"))
        log("animations", key, ", ".join("%s %d frames" % (k, v["frames"]) for k, v in out.items()))


def main():
    t0 = time.time()
    fs = srcfs.GameFS()
    lib = materials.MaterialLib(fs, ASSETS)
    os.makedirs(ASSETS, exist_ok=True)
    data_dir = os.path.join(ASSETS, "data")
    os.makedirs(data_dir, exist_ok=True)

    # ---- models ----
    model_index = {}
    for kind, path in model_todo():
        got = convert_model(fs, lib, kind, path, force=FORCE)
        if got:
            model_index[got[0]] = got[1]
    for key, candidates, bg, kind in hl1_jobs():
        entry = convert_hl1(lib, key, candidates, bg, kind)
        if entry:
            model_index[key] = entry
    for name in HL1_PROPS:
        got = convert_hl1_prop(lib, name)
        if got:
            model_index[got[0]] = got[1]
    with open(os.path.join(data_dir, "models.json"), "w") as f:
        json.dump(model_index, f, indent=1)
    write_anims(fs)

    # ---- world materials ----
    for m in WORLD_MATERIALS:
        if not fs.exists("materials/" + m + ".vmt"):
            log("  -- missing material", m)
            continue
        info = lib.material(m)
        log("material", m, info.get("shader"), info.get("albedo"))

    # ---- animated sprites -> flipbook sheets ----
    from PIL import Image
    import vtf as vtfmod
    for spr, (cols, rows) in {"sprites/zerogxplode": (5, 3)}.items():
        d = fs.read("materials/" + spr + ".vtf")
        if d is None:
            continue
        first, info = vtfmod.decode(d, 0)
        w, h = first.size
        sheet = Image.new("RGBA", (w * cols, h * rows))
        for f in range(min(info["frames"], cols * rows)):
            im, _ = vtfmod.decode(d, f)
            sheet.paste(im, ((f % cols) * w, (f // cols) * h))
        out = os.path.join(ASSETS, "materials", spr + "_sheet.png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        sheet.save(out)
        log("sheet", spr, info["frames"])

    # ---- skies ----
    sky_dir = os.path.join(ASSETS, "sky")
    os.makedirs(sky_dir, exist_ok=True)
    for s in SKIES:
        for face in ("rt", "lf", "up", "dn", "ft", "bk"):
            _, p = lib.load_vmt("skybox/" + s + face)
            tex = (p or {}).get("$basetexture", "skybox/" + s + face)
            r = lib.export_texture(tex)
            if r:
                shutil.copyfile(os.path.join(ASSETS, r["path"]), os.path.join(sky_dir, "%s%s.png" % (s, face)))
        log("sky", s)

    # ---- sounds ----
    for s in SOUNDS:
        sounds.export(fs, s, ASSETS)
    voice_index = {}
    for who, cats in VOICES.items():
        voice_index[who] = {}
        for cat, lst in cats.items():
            got = [sounds.export(fs, s, ASSETS) for s in lst]
            voice_index[who][cat] = ["res://assets/" + g for g in got if g]
    # HL1 voices straight from the Half-Life folder: the HEV suit speaks for Gordon,
    # HECU radio chatter for Shephard
    hl1_voices = {
        "gordon": {"hit": ["fvox/bell.wav", "fvox/acquired.wav", "fvox/boop.wav"],
                   "hurt": ["fvox/minor_lacerations.wav", "fvox/major_fracture.wav", "fvox/blood_loss.wav",
                            "fvox/armor_compromised.wav"],
                   "win": ["fvox/power_restored.wav", "fvox/medical_repaired.wav"],
                   "start": ["fvox/hev_logon.wav"]},
        "shephard": {"hit": ["hgrunt/c2a3_hg_laugh.wav", "hgrunt/yeah!.wav", "hgrunt/affirmative!.wav"],
                     "hurt": ["hgrunt/gr_pain1.wav", "hgrunt/gr_pain3.wav", "hgrunt/damn!.wav", "hgrunt/shit!.wav"],
                     "win": ["hgrunt/c2a3_hg_laugh.wav", "hgrunt/yessir!.wav"],
                     "start": ["hgrunt/go!.wav", "hgrunt/move!.wav"]},
    }
    for who, cats in hl1_voices.items():
        voice_index[who] = {}
        for cat, lst in cats.items():
            got = [hl1_sound(rel) for rel in lst]
            voice_index[who][cat] = ["res://assets/" + g for g in got if g]
    for rel in HL1_SOUNDS:
        hl1_sound(rel)
    voice_index["_vox"] = [line.split() for line in VOX_SENTENCES]
    voice_index["_crowd"] = {}
    for role, cats in CROWD_VOICES.items():
        voice_index["_crowd"][role] = {}
        for cat, lst in cats.items():
            got = [hl1_sound(s[4:]) if s.startswith("hl1:") else sounds.export(fs, s, ASSETS) for s in lst]
            voice_index["_crowd"][role][cat] = ["res://assets/" + g for g in got if g]
    with open(os.path.join(data_dir, "voices.json"), "w") as f:
        json.dump(voice_index, f, indent=1)
    # the whole soundtrack (for the menu jukebox), stingers excluded
    for m in fs.glob(lambda k: k.startswith("sound/music/") and k.endswith(".mp3") and "/stingers/" not in k):
        sounds.export(fs, m[len("sound/"):], ASSETS)
    log("sounds done")

    # ---- surface properties + impact sounds for the props we use ----
    props, gs = surface_props(fs)
    used = {v["surfaceprop"].lower() for v in model_index.values()} | {"default", "metal", "concrete", "dirt",
                                                                     "grass", "gravel", "jeeptire", "metalvehicle",
                                                                     "wood_crate", "watermelon", "flesh", "water"}
    out = {}
    for sp in sorted(used):
        p = props.get(sp)
        if not p:
            continue
        e = {k: p[k] for k in ("density", "elasticity", "friction", "dampening", "gamematerial") if k in p}
        for snd in ("impacthard", "impactsoft", "scraperough", "scrapesmooth", "break", "rolling"):
            name = p.get(snd)
            if name and name.lower() in gs:
                waves = [sounds.export(fs, w, ASSETS) for w in gs[name.lower()]["waves"]]
                e[snd] = ["res://assets/" + w for w in waves if w]
        out[sp] = e
    with open(os.path.join(data_dir, "surfaceprops.json"), "w") as f:
        json.dump(out, f, indent=1)
    log("surfaceprops", len(out))

    # ---- fonts ----
    fdir = os.path.join(ASSETS, "fonts")
    os.makedirs(fdir, exist_ok=True)
    for fn in FONTS:
        src = os.path.join(srcfs.HL2_ROOT, "hl2", "resource", fn)
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(fdir, fn))

    # ---- vehicle script (jeep physics) ----
    shutil.copyfile(os.path.join(srcfs.HL2_ROOT, "hl2", "scripts", "vehicles", "jeep_test.txt"),
                    os.path.join(data_dir, "jeep_test.txt"))
    mpath = os.path.join(data_dir, "materials.json")
    db = {}
    if os.path.exists(mpath):
        with open(mpath) as f:
            db = json.load(f)
    db.update(lib.db)
    with open(mpath, "w") as f:
        json.dump(db, f, indent=1)
    log("done in %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    main()
