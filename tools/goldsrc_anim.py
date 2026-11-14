"""GoldSrc (Half-Life 1) studio model sequences -> per-frame local bone poses in glTF space.

The game plays them on a model converted by tools/goldsrc_mdl.py, so every pose here is written in the
space of that converter's skeleton: positions through conv_v (Source x, z, -y, in metres) and rotations
as [x, z, -y, w] of the HLSDK AngleQuaternion, the same change of axes it gives each joint. A root bone
also gets the converter's face_fix turn about the vertical (0 for the props and racers it builds now).

    anims("valve/models/bullsquid.mdl", ["run", "range"])
      -> {name: {"fps", "frames", "move": metres per cycle along the way the model faces,
                 "move_vec": [x, y, z] metres per cycle in glTF model space, "forward": [x, y, z],
                 "loop": bool, "events": [[frame, event, options], ...],
                 "bones": {bone name: {"r": [[x, y, z, w] per frame], "p": [[x, y, z] per frame]}}}}

This is the format tools/mdl_anim.py writes for Source models, with extra keys the older reader of it
(Dog in scripts/kart/kart_visual.gd) ignores; "forward" is the way the animated model faces, in glTF
model space. Bone names go through goldsrc_mdl.rename_bone, so they are the converted skeleton's names.
Only the bones the sequence moves away from their bind pose are listed; the rest keep their rest pose,
which is exactly what the game falls back to.

The bind pose and the sequences are not in the same frame: studiomdl turns the root bones of every
sequence (not of the reference skeleton the bind pose comes from) by the $origin rotation plus 90 degrees
about the vertical, 90 for every model checked (houndeye, controller, bullsquid, scientist, hgrunt, ...).
Played as stored, a sequence would turn the converted model a quarter turn away from its bind pose. That
turn is taken out of the root bones here, so a sequence's frame 0 lands on the bind pose and an animated
creature faces where its bind pose faces: glTF +Z (Source -Y) for the creatures, see "forward".
Checked: frame 0 of many houndeye and bullsquid sequences (the houndeye's 180l / eat, the bullsquid's
bite / range / flinchs ...) lands on the converted rest pose within 0.1 mm and 0.01 degrees; the
controller's bind pose is no frame of any of its sequences (its reference pose stands about 0.9 m
higher than where its sequences hold it).

How GoldSrc stores a sequence (HLSDK studio.h, StudioCalcBonePosition / StudioCalcBoneQuaterion): each
sequence has, per blend, one mstudioanim_t per bone: six unsigned short offsets (pos x y z, rot x y z)
from that mstudioanim_t to a run-length packed list of shorts, or 0 when the channel never leaves the
bone's default. A channel's value is the bone's default value[] plus the short times the bone's scale[].
Rotations are Euler angles in radians (roll x, pitch y, yaw z). The sequence's linear movement (the
"LX" motion type) is taken out of the root bone when the model is compiled and kept in linearmovement,
so a run plays in place and moves that far per cycle. A looping sequence's cycle is numframes - 1 frames
(its last frame is its first again), as in HL1's StudioEstimateFrame. Sequences of a model with
numseqgroups > 1 may live in <name>01.mdl, <name>02.mdl ... next to it, at the same animindex offsets.

python tools/goldsrc_anim.py <model.mdl> [sequence ...]   lists the sequences, or checks the named ones
"""
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from goldsrc_mdl import angle_quat, rename_bone  # noqa: E402
from mdl import SCALE  # noqa: E402

STUDIO_LOOPING = 1
EPS_ROT = 1e-5  # a frame closer than this to the rest pose counts as resting (quaternion components)
EPS_POS = 1e-5  # metres


def _cstr(b):
    return b.split(b"\0")[0].decode("latin-1")


def _value(d, o, frame):
    """The short a run-length packed mstudioanimvalue_t list at o holds for `frame`.

    Each run starts with a header slot of two bytes (valid, total): `total` frames follow, the first
    `valid` of them with their own short in the next slots, the rest repeating the last of those."""
    k = frame
    while True:
        valid, total = d[o], d[o + 1]
        if total == 0:
            return 0  # an empty run (not written by studiomdl): no data
        if total > k:
            break
        k -= total
        o += (valid + 1) * 2
    i = k + 1 if valid > k else valid
    return struct.unpack_from("<h", d, o + i * 2)[0]


def _qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


class GoldSrcAnims:
    """The bones, sequences and sequence group files of one GoldSrc v10 model."""

    def __init__(self, path):
        self.path = path
        with open(path, "rb") as f:
            self.d = d = f.read()
        ident, ver = struct.unpack_from("<4si", d, 0)
        if ident != b"IDST" or ver != 10:
            raise ValueError("not a GoldSrc v10 model: " + path)
        (self.numbones, boneindex, _nbc, _bci, _nhb, _hbi, self.numseq, seqindex,
         self.numseqgroups, seqgroupindex) = struct.unpack_from("<10i", d, 140)
        self.bones = []
        for i in range(self.numbones):
            o = boneindex + i * 112
            self.bones.append({"name": _cstr(d[o:o + 32]), "parent": struct.unpack_from("<i", d, o + 32)[0],
                               "value": struct.unpack_from("<6f", d, o + 64),
                               "scale": struct.unpack_from("<6f", d, o + 88)})
        self.groups = []
        for g in range(self.numseqgroups):
            o = seqgroupindex + g * 104
            self.groups.append({"label": _cstr(d[o:o + 32]), "name": _cstr(d[o + 32:o + 96])})
        self._group_data = {0: d}
        self.seqs = []
        for i in range(self.numseq):
            o = seqindex + i * 176
            fps, flags, activity = struct.unpack_from("<fii", d, o + 32)
            numevents, eventindex, numframes = struct.unpack_from("<iii", d, o + 48)
            motiontype, motionbone = struct.unpack_from("<ii", d, o + 68)
            events = []
            for e in range(numevents):
                eo = eventindex + e * 76
                frame, event, _type = struct.unpack_from("<3i", d, eo)
                events.append([frame, event, _cstr(d[eo + 12:eo + 76])])
            self.seqs.append({
                "label": _cstr(d[o:o + 32]), "fps": fps, "flags": flags, "activity": activity,
                "frames": numframes, "motiontype": motiontype, "motionbone": motionbone,
                "linearmovement": struct.unpack_from("<3f", d, o + 76),
                "numblends": struct.unpack_from("<i", d, o + 120)[0],
                "animindex": struct.unpack_from("<i", d, o + 124)[0],
                "seqgroup": struct.unpack_from("<i", d, o + 156)[0], "events": events})

    def zrotation(self):
        """The turn (degrees about the vertical) studiomdl gave every sequence's root bones: the multiple
        of 90 nearest the most common difference between a root's yaw at frame 0 and its bind yaw."""
        counts = {}
        for s in self.seqs:
            try:
                pose = self.pose(s, 0)[0]
            except (OSError, ValueError):
                continue  # a sequence group file this install lacks
            for i, b in enumerate(self.bones):
                if b["parent"] < 0:
                    key = round(math.degrees(pose[i][1][2] - b["value"][5]) % 360.0)
                    counts[key] = counts.get(key, 0) + 1
        if not counts:
            return 90.0
        mode = max(counts, key=counts.get)
        return float(round(mode / 90.0) * 90 % 360)

    def sequence(self, label):
        """The first sequence with this label (HL1 models repeat some, like the houndeye's three "run"s)."""
        for s in self.seqs:
            if s["label"].lower() == label.lower():
                return s
        return None

    def _group(self, g):
        """The bytes holding sequence group g: the model itself for 0, else <name>NN.mdl next to it."""
        if g not in self._group_data:
            base = os.path.splitext(self.path)[0]
            cands = [base + "%02d.mdl" % g]
            stored = self.groups[g]["name"].replace("\\", "/") if g < len(self.groups) else ""
            if stored:
                cands.append(os.path.join(os.path.dirname(self.path), os.path.basename(stored)))
            for c in cands:
                if os.path.exists(c):
                    with open(c, "rb") as f:
                        data = f.read()
                    if data[:4] != b"IDSQ":
                        raise ValueError("not a GoldSrc sequence group file: " + c)
                    self._group_data[g] = data
                    break
            else:
                raise FileNotFoundError("sequence group %d of %s (%s)" % (g, self.path, " or ".join(cands)))
        return self._group_data[g]

    def pose(self, seq, frame, blend=0):
        """[(pos, angles)] per bone at an integer frame, in GoldSrc space and units (angles in radians),
        plus the set of bones whose channels hold any data in this sequence."""
        buf = self._group(seq["seqgroup"])
        base = seq["animindex"] + blend * self.numbones * 12
        out = []
        animated = set()
        for i, b in enumerate(self.bones):
            o = base + i * 12
            offs = struct.unpack_from("<6H", buf, o)
            v = list(b["value"])
            for j in range(6):
                if offs[j]:
                    v[j] += _value(buf, o + offs[j], frame) * b["scale"][j]
                    animated.add(i)
            out.append((tuple(v[0:3]), tuple(v[3:6])))
        # the X / Y / Z motion types pin the motion bone on that axis (HL1's StudioCalcRotations)
        mb = seq["motionbone"]
        if 0 <= mb < len(out) and seq["motiontype"] & 7:
            p = list(out[mb][0])
            for j in range(3):
                if seq["motiontype"] & (1 << j):
                    p[j] = 0.0
            out[mb] = (tuple(p), out[mb][1])
        return out, animated


def _gltf_quat(q):
    """A Source/GoldSrc quaternion (x, y, z, w) -> the converted skeleton's axes, normalised."""
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return [q[0] / n, q[2] / n, -q[1] / n, q[3] / n]


def _gltf_pos(p):
    return [p[0] * SCALE, p[2] * SCALE, -p[1] * SCALE]


def _rest(m, face_fix):
    """[(gltf pos, gltf quat)] per bone: the rest pose goldsrc_mdl.convert gives its joints."""
    turn = _face_turn(face_fix)
    out = []
    for b in m.bones:
        pos, q = b["value"][0:3], angle_quat(b["value"][3:6])
        if b["parent"] < 0 and turn is not None:
            pos, q = _turn(turn, pos), _qmul(turn, q)
        out.append((_gltf_pos(pos), _gltf_quat(q)))
    return out


def _face_turn(face_fix):
    if not face_fix:
        return None
    h = math.radians(face_fix) * 0.5
    return (0.0, 0.0, math.sin(h), math.cos(h))


def _turn(q, v):
    x, y, z, _w = _qmul(_qmul(q, (v[0], v[1], v[2], 0.0)), (-q[0], -q[1], -q[2], q[3]))
    return (x, y, z)


def _differs(track, rest):
    rq, rp = rest
    for q in track["r"]:
        # q and -q are the same rotation
        if min(sum(abs(a - b) for a, b in zip(q, rq)), sum(abs(a + b) for a, b in zip(q, rq))) > EPS_ROT * 4:
            return True
    for p in track["p"]:
        if sum(abs(a - b) for a, b in zip(p, rp)) > EPS_POS * 3:
            return True
    return False


def anims(path, names, face_fix=0.0, blend=0):
    """{name: animation} for the named sequences of the GoldSrc model at `path` (names it lacks are left
    out). face_fix must be the one goldsrc_mdl.convert built the model with."""
    m = GoldSrcAnims(path)
    rest = _rest(m, face_fix)
    # root bones: first undo studiomdl's turn of the sequences, then apply the converter's face_fix
    turn = _face_turn(face_fix - m.zrotation())
    forward = _gltf_pos(_turn(turn, (1.0 / SCALE, 0.0, 0.0)) if turn is not None else (1.0 / SCALE, 0.0, 0.0))
    out = {}
    for name in names:
        s = m.sequence(name)
        if s is None:
            continue
        frames = max(1, s["frames"])
        tracks = [{"r": [], "p": []} for _ in m.bones]
        moved = set()
        for f in range(frames):
            pose, animated = m.pose(s, f, min(blend, s["numblends"] - 1))
            moved |= animated
            for i, (pos, ang) in enumerate(pose):
                q = angle_quat(ang)
                if m.bones[i]["parent"] < 0 and turn is not None:
                    pos, q = _turn(turn, pos), _qmul(turn, q)
                gq = _gltf_quat(q)
                # one hemisphere along the track, so a slerp between frames takes the short way
                prev = tracks[i]["r"][-1] if tracks[i]["r"] else rest[i][1]
                if sum(a * b for a, b in zip(gq, prev)) < 0.0:
                    gq = [-c for c in gq]
                tracks[i]["r"].append([round(c, 5) for c in gq])
                tracks[i]["p"].append([round(c, 5) for c in _gltf_pos(pos)])
        bones = {}
        for i in sorted(moved):
            if _differs(tracks[i], rest[i]):
                bones[rename_bone(m.bones[i]["name"])] = tracks[i]
        lm = s["linearmovement"]
        mv = _gltf_pos(_turn(turn, lm) if turn is not None else lm)
        out[name] = {"fps": s["fps"], "frames": frames, "move": round(lm[0] * SCALE, 4),
                     "move_vec": [round(c, 4) for c in mv], "forward": [round(c, 4) for c in forward],
                     "loop": bool(s["flags"] & STUDIO_LOOPING), "events": s["events"], "bones": bones}
    return out


def rest_pose(path, face_fix=0.0):
    """{bone name: (pos, quat)} of the converted skeleton's rest, for checks."""
    m = GoldSrcAnims(path)
    return {rename_bone(b["name"]): r for b, r in zip(m.bones, _rest(m, face_fix))}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    m = GoldSrcAnims(path)
    names = sys.argv[2:]
    if not names:
        print("%s: %d bones, %d sequences, %d sequence groups" % (path, m.numbones, m.numseq, m.numseqgroups))
        for s in m.seqs:
            print("  %-16s %3d frames %5.1f fps %s group %d move %s events %s" % (
                s["label"], s["frames"], s["fps"], "loop" if s["flags"] & STUDIO_LOOPING else "once",
                s["seqgroup"], [round(c * SCALE, 2) for c in s["linearmovement"]], s["events"]))
        return 0
    got = anims(path, names)
    for n, a in got.items():
        print("%-12s %3d frames %4.1f fps move %.3f m loop %s, %d bones moved" % (
            n, a["frames"], a["fps"], a["move"], a["loop"], len(a["bones"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
