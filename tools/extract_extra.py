"""Extract part of tools/extract_all.py's content into an assets/ folder that is already built, without the
full run (about an hour): the entries a code change added to its lists, or the models and sounds named here.

python tools/extract_extra.py --missing
    every model, sound, animation and world material in extract_all.py's lists that assets/ does not have yet
python tools/extract_extra.py [--models KEY ...] [--sounds PATH ...] [--anims KEY ...] [--force]
    models by their models.json key ("antlion", "props_wasteland/cranemagnet01a", "hl1/bullsquid"), sounds by
    their path under sound/ ("npc/antlion/idle1.wav", or "hl1:bullchicken/bc_idle1.wav" for Half-Life's own),
    animations by their ANIMS key; --force converts the named HL2 models again even when they are there
python tools/extract_extra.py --missing --dry-run
    lists what would be extracted and changes nothing

assets/data/models.json and materials.json are merged, never rebuilt: each is loaded, the new entries are
added (or replace the ones with the same key), and the result goes to a temporary file that then replaces the
old one, so every other entry stays and a reader never sees half a file. voices.json is not touched: the
racers' and spectators' lines come with the full run. Godot has to import the new files afterwards
(godot --headless --path . --import).
"""
import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import extract_all as ea  # noqa: E402
import materials  # noqa: E402
import sounds  # noqa: E402
import srcfs  # noqa: E402

DATA = os.path.join(ea.ASSETS, "data")
log = ea.log


def load_json(path):
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


def write_json(path, data):
    """Write through a temporary file swapped in at the end, so nothing ever reads a half-written index."""
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1)
    os.replace(tmp, path)


def model_files_exist(key):
    base = os.path.join(ea.ASSETS, "models", key)
    return os.path.exists(base + ".gltf") and os.path.exists(base + ".json")


def hl2_sound_exists(snd):
    return os.path.exists(os.path.join(ea.ASSETS, "sound", snd.lower().replace("\\", "/")))


def hl1_sound_exists(rel):
    return os.path.exists(os.path.join(ea.ASSETS, "sound", "hl1src", rel.replace("!", "_x")))


class Plan:
    """What to extract: HL2 models as (kind, path), HL1 racers / spectators as (key, candidates, bodygroups,
    kind), HL1 props by name, HL2 and HL1 sounds, ANIMS keys and world materials."""

    def __init__(self):
        self.hl2 = []
        self.hl1 = []
        self.hl1_props = []
        self.sounds = []
        self.hl1_sounds = []
        self.anims = []
        self.world = []
        self.unknown = []
        self.absent = []  # list entries this install does not have (left out of the plan)

    def size(self):
        return (len(self.hl2) + len(self.hl1) + len(self.hl1_props) + len(self.sounds) + len(self.hl1_sounds) +
                len(self.anims) + len(self.world))

    def show(self):
        for label, items in (("HL2 models", [p for _k, p in self.hl2]), ("HL1 models", [j[0] for j in self.hl1]),
                             ("HL1 props", self.hl1_props), ("HL2 sounds", self.sounds),
                             ("HL1 sounds", self.hl1_sounds), ("animations", self.anims),
                             ("world materials", self.world)):
            if items:
                log("%s (%d): %s" % (label, len(items), " ".join(items)))


def hl2_kinds():
    """models.json key -> (kind, path) for every HL2 model in extract_all's lists (the first list naming it)."""
    out = {}
    for kind, path in ea.model_todo():
        out.setdefault(path[len("models/") : -4], (kind, path))
    return out


def plan_missing(fs, index, mat_db):
    """Everything in extract_all's lists that assets/ lacks: a model with no models.json entry or no files,
    a sound with no file, an animation with no .anims.json, a world material with no materials.json entry.
    Entries this install does not have at all go to plan.absent instead (the full run skips them too)."""
    plan = Plan()

    def want(lst, item, present, label):
        if present:
            lst.append(item)
        else:
            plan.absent.append(label)

    for key, (kind, path) in hl2_kinds().items():
        if key not in index or not model_files_exist(key):
            want(plan.hl2, (kind, path), fs.exists(path), path)
    for job in ea.hl1_jobs():
        if job[0] not in index or not model_files_exist(job[0]):
            want(plan.hl1, job, any(os.path.exists(os.path.join(ea.HL1_ROOT, c)) for c in job[1]), job[0])
    for name in ea.HL1_PROPS:
        key = ea.hl1_prop_key(name)
        if key not in index or not model_files_exist(key):
            want(plan.hl1_props, name, os.path.exists(os.path.join(ea.HL1_ROOT, "valve", "models", name + ".mdl")),
                 key)
    for s in dict.fromkeys(ea.SOUNDS):
        if not hl2_sound_exists(s):
            want(plan.sounds, s, fs.exists("sound/" + s), s)
    for s in dict.fromkeys(ea.HL1_SOUNDS):
        if not hl1_sound_exists(s):
            want(plan.hl1_sounds, s, os.path.exists(os.path.join(ea.HL1_ROOT, "valve", "sound", s)), "hl1:" + s)
    for k, (src, _names) in ea.ANIMS.items():
        if not os.path.exists(os.path.join(ea.ASSETS, "models", k + ".anims.json")):
            want(plan.anims, k, fs.exists(src), src)
    for m in ea.WORLD_MATERIALS:
        if m not in mat_db:
            want(plan.world, m, fs.exists("materials/" + m + ".vmt"), m)
    return plan


def plan_named(models, snds, anims):
    """The models, sounds and animations named on the command line, each resolved to the list it comes from."""
    plan = Plan()
    kinds = hl2_kinds()
    hl1 = {job[0]: job for job in ea.hl1_jobs()}
    props = {ea.hl1_prop_key(n): n for n in ea.HL1_PROPS}
    for key in models:
        key = key.replace("\\", "/").strip("/")
        if key.startswith("models/"):
            key = key[len("models/"):]
        if key.endswith(".mdl"):
            key = key[:-4]
        if key in hl1:
            plan.hl1.append(hl1[key])
        elif key in props:
            plan.hl1_props.append(props[key])
        elif key.startswith("hl1/"):
            plan.hl1_props.append(key[len("hl1/"):])  # any other valve/models/<name>.mdl
        else:
            plan.hl2.append(kinds.get(key, ("props", "models/%s.mdl" % key)))
    for s in snds:
        if s.startswith("hl1:"):
            plan.hl1_sounds.append(s[len("hl1:"):])
        else:
            plan.sounds.append(s[len("sound/"):] if s.startswith("sound/") else s)
    for k in anims:
        (plan.anims if k in ea.ANIMS else plan.unknown).append(k)
    return plan


def run(fs, plan, force=False):
    """Extract what the plan names and merge the results into models.json and materials.json.
    Returns the names of the items that failed."""
    lib = materials.MaterialLib(fs, ea.ASSETS)
    failed = list(plan.unknown)
    new_entries = {}
    for kind, path in plan.hl2:
        got = ea.convert_model(fs, lib, kind, path, force=force)
        if got:
            new_entries[got[0]] = got[1]
        else:
            failed.append(path)
    for key, candidates, bg, kind in plan.hl1:
        entry = ea.convert_hl1(lib, key, candidates, bg, kind)
        if entry:
            new_entries[key] = entry
        else:
            failed.append(key)
    for name in plan.hl1_props:
        got = ea.convert_hl1_prop(lib, name)
        if got:
            new_entries[got[0]] = got[1]
        else:
            failed.append("hl1/" + name)
    for s in plan.sounds:
        if not sounds.export(fs, s, ea.ASSETS):
            failed.append(s)
    for s in plan.hl1_sounds:
        if not ea.hl1_sound(s):
            failed.append("hl1:" + s)
    if plan.anims:
        ea.write_anims(fs, set(plan.anims))
        failed += [k for k in plan.anims if not os.path.exists(os.path.join(ea.ASSETS, "models", k + ".anims.json"))]
    for m in plan.world:
        if not fs.exists("materials/" + m + ".vmt"):
            log("  -- missing material", m)
            failed.append(m)
            continue
        info = lib.material(m)
        log("material", m, info.get("shader"), info.get("albedo"))

    # merge, never rebuild: read the indexes again right before writing them
    os.makedirs(DATA, exist_ok=True)
    mpath = os.path.join(DATA, "models.json")
    index = load_json(mpath)
    before = len(index)
    added = [k for k in new_entries if k not in index]
    index.update(new_entries)
    write_json(mpath, index)
    dbpath = os.path.join(DATA, "materials.json")
    db = load_json(dbpath)
    db_before = len(db)
    db.update(lib.db)
    write_json(dbpath, db)
    log("models.json: %d entries before, %d after (%d new, %d updated)" % (
        before, len(index), len(added), len(new_entries) - len(added)))
    log("materials.json: %d entries before, %d after" % (db_before, len(db)))
    return failed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--missing", action="store_true", help="everything in extract_all's lists that assets/ lacks")
    ap.add_argument("--models", nargs="*", default=[], help="models.json keys")
    ap.add_argument("--sounds", nargs="*", default=[], help="paths under sound/; hl1:<path> for Half-Life's")
    ap.add_argument("--anims", nargs="*", default=[], help="ANIMS keys")
    ap.add_argument("--force", action="store_true", help="convert the named HL2 models again")
    ap.add_argument("--dry-run", action="store_true", help="only list what would be extracted")
    a = ap.parse_args()
    if not (a.missing or a.models or a.sounds or a.anims):
        ap.error("nothing to do: pass --missing, --models, --sounds or --anims")
    t0 = time.time()
    fs = srcfs.GameFS()
    if a.missing:
        plan = plan_missing(fs, load_json(os.path.join(DATA, "models.json")),
                            load_json(os.path.join(DATA, "materials.json")))
        named = plan_named(a.models, a.sounds, a.anims)
        for field in ("hl2", "hl1", "hl1_props", "sounds", "hl1_sounds", "anims", "unknown"):
            for item in getattr(named, field):
                if item not in getattr(plan, field):
                    getattr(plan, field).append(item)
    else:
        plan = plan_named(a.models, a.sounds, a.anims)
    plan.show()
    if plan.absent:
        log("in the lists but not in this install (%d, skipped): %s" % (len(plan.absent), " ".join(plan.absent)))
    if plan.unknown:
        log("  !! not in ANIMS:", " ".join(plan.unknown))
    if a.dry_run or not plan.size():
        log("nothing extracted" if not plan.size() else "dry run: nothing extracted")
        return 1 if plan.unknown else 0
    failed = run(fs, plan, force=a.force)
    log("done in %.1fs" % (time.time() - t0))
    if failed:
        log("not extracted (%d): %s" % (len(failed), " ".join(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
