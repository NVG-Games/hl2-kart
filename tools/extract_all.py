"""Extract everything HL2 Kart needs from the Half-Life 2 install into hl2kart/assets.

python -I extract_all.py [--force]
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

# HL1 set dressing for the Black Mesa, Xen and Surface Tension circuits (valve/models/<name>.mdl)
HL1_PROPS = [
    "forklift", "loader", "sentry", "turret", "miniturret", "scientist", "filecabinet", "holo",
    "light", "tree", "fungus", "fungus(large)", "fungus(small)", "hair", "uplant1", "uplant2", "uplant3",
    "crystal", "big_rock", "floater", "islave", "houndeye", "controller", "nihilanth", "protozoa",
    "dead_osprey", "osprey", "apache", "hgrunt", "tentacle2", "garg",
]

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
    "breen": {"hit": ["vo/breencast/br_instinct01.wav", "vo/breencast/br_overwatch07.wav"],
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

FONTS = ["halflife2.ttf", "hl2ep2.ttf", "hl2crosshairs.ttf", "dejavusans.ttf"]


def log(*a):
    print(*a, flush=True)


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


def main():
    t0 = time.time()
    fs = srcfs.GameFS()
    lib = materials.MaterialLib(fs, ASSETS)
    os.makedirs(ASSETS, exist_ok=True)
    data_dir = os.path.join(ASSETS, "data")
    os.makedirs(data_dir, exist_ok=True)

    # ---- models ----
    model_index = {}
    todo = [("drivers", "models/%s.mdl" % d) for d in DRIVERS] + [("props", "models/%s.mdl" % m) for m in MODELS]
    for parent, gibs in GIBS.items():
        todo += [("gibs", "models/%s.mdl" % g) for g in gibs]
    for kind, path in todo:
        if not fs.exists(path):
            log("  -- missing model", path)
            continue
        try:
            meta = mdl.convert(fs, lib, path, ASSETS + "/", bodygroups=BODYGROUPS.get(path), force=FORCE)
            key = path[len("models/") : -4]
            model_index[key] = {"gltf": "res://assets/models/" + key + ".gltf",
                                "meta": "res://assets/models/" + key + ".json",
                                "mass": meta["mass"], "surfaceprop": meta["surfaceprop"],
                                "aabb_min": meta.get("aabb_min"), "aabb_max": meta.get("aabb_max"), "kind": kind}
            log("model", key, "%.0fkg" % meta["mass"], meta["surfaceprop"])
        except Exception as e:  # noqa
            log("  !! model", path, repr(e))
    import goldsrc_mdl
    for key, candidates, bg in HL1_MODELS:
        src = next((os.path.join(HL1_ROOT, c) for c in candidates if os.path.exists(os.path.join(HL1_ROOT, c))), None)
        if src is None:
            log("  -- missing HL1 model", key)
            continue
        meta, mats = goldsrc_mdl.convert(src, key, ASSETS, bg if "valve_hd" in src or "gordon" in src else {})
        lib.db.update(mats)
        model_index[key] = {"gltf": "res://assets/models/%s.gltf" % key, "meta": "res://assets/models/%s.json" % key,
                            "mass": 90.0, "surfaceprop": "flesh", "aabb_min": meta["aabb_min"],
                            "aabb_max": meta["aabb_max"], "kind": "drivers"}
        log("hl1 model", key, src)
    for name in HL1_PROPS:
        src = os.path.join(HL1_ROOT, "valve", "models", name + ".mdl")
        if not os.path.exists(src):
            log("  -- missing HL1 prop", name)
            continue
        key = "hl1/" + name.replace("(", "_").replace(")", "")
        try:
            meta, mats = goldsrc_mdl.convert(src, key, ASSETS, {})
        except Exception as e:  # noqa
            log("  !! HL1 prop", name, repr(e))
            continue
        lib.db.update(mats)
        model_index[key] = {"gltf": "res://assets/models/%s.gltf" % key, "meta": "res://assets/models/%s.json" % key,
                            "mass": 200.0, "surfaceprop": "metal", "aabb_min": meta["aabb_min"],
                            "aabb_max": meta["aabb_max"], "kind": "props"}
        log("hl1 prop", key)
    with open(os.path.join(data_dir, "models.json"), "w") as f:
        json.dump(model_index, f, indent=1)

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
            got = []
            for rel in lst:
                src = os.path.join(HL1_ROOT, "valve", "sound", rel)
                if not os.path.exists(src):
                    continue
                dst_rel = "sound/hl1src/" + rel.replace("!", "_x")
                dst = os.path.join(ASSETS, dst_rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                if not os.path.exists(dst):
                    with open(src, "rb") as fsrc:
                        wav, _ = sounds.convert_wav(fsrc.read())
                    with open(dst, "wb") as fdst:
                        fdst.write(wav)
                got.append("res://assets/" + dst_rel)
            voice_index[who][cat] = got
    for rel in HL1_SOUNDS:
        src = os.path.join(HL1_ROOT, "valve", "sound", rel)
        dst = os.path.join(ASSETS, "sound", "hl1src", rel)
        if os.path.exists(src) and not os.path.exists(dst):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(src, "rb") as fsrc:
                wav, _ = sounds.convert_wav(fsrc.read())
            with open(dst, "wb") as fdst:
                fdst.write(wav)
    voice_index["_vox"] = [line.split() for line in VOX_SENTENCES]
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
