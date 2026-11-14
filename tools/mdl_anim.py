"""Source MDL animations (v44-v48) -> per-frame local bone poses in glTF space.

The game plays them on a model converted by tools/mdl.py, whose bones are built the same way
(conv_v for positions, [x, z, -y, w] for rotations), so a pose here is the bone's pose there. An
animation may live in another model (Dog's are in models/dog_animations.mdl and its .ani animation
blocks): its bones are matched to the target's by name.

    anims(fs, "models/dog_animations.mdl", ["a_run_N", "a_walk_N", "idle01"])
      -> {name: {"fps", "frames", "move": metres per cycle along +X (Source forward),
                 "bones": {bone name: {"r": [[x, y, z, w] per frame], "p": [[x, y, z] per frame]}}}}

Only the bones the animation moves are listed; the rest keep their rest pose. Delta animations
are not handled.

A model's animations can be authored turned from its bone table's rest pose (Dog's by 90 degrees
about the vertical): the root bones of its "reference" animation then differ from their rest by
that turn, which is taken out of every frame of the root bones so the poses fit the converted
skeleton (built from the bone table).
"""
import math
import struct

from mdl import SCALE, cstr

RAWPOS, RAWROT, ANIMPOS, ANIMROT, DELTA, RAWROT2 = 0x01, 0x02, 0x04, 0x08, 0x10, 0x20


def _angle_quat(x, y, z):
    """Source AngleQuaternion(RadianEuler): roll x, pitch y, yaw z -> (x, y, z, w)."""
    sr, cr = math.sin(x * 0.5), math.cos(x * 0.5)
    sp, cp = math.sin(y * 0.5), math.cos(y * 0.5)
    sy, cy = math.sin(z * 0.5), math.cos(z * 0.5)
    return (sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy,
            cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy)


def _quat48(d, o):
    x, y, zw = struct.unpack_from("<HHH", d, o)
    qx = (x - 32768) / 32768.0
    qy = (y - 32768) / 32768.0
    qz = ((zw & 0x7FFF) - 16384) / 16384.0
    w = math.sqrt(max(0.0, 1.0 - qx * qx - qy * qy - qz * qz))
    return (qx, qy, qz, -w if zw >> 15 else w)


def _quat64(d, o):
    (v,) = struct.unpack_from("<Q", d, o)
    qx = ((v & 0x1FFFFF) - 1048576) / 1048576.5
    qy = (((v >> 21) & 0x1FFFFF) - 1048576) / 1048576.5
    qz = (((v >> 42) & 0x1FFFFF) - 1048576) / 1048576.5
    w = math.sqrt(max(0.0, 1.0 - qx * qx - qy * qy - qz * qz))
    return (qx, qy, qz, -w if v >> 63 else w)


def _value(d, o, frame):
    """ExtractAnimValue: run-length encoded shorts (valid, total) at o, for frame."""
    k = frame
    while True:
        valid, total = d[o], d[o + 1]
        if total == 0:
            return 0
        if total > k:
            break
        k -= total
        o += (valid + 1) * 2
    i = k + 1 if valid > k else valid
    return struct.unpack_from("<h", d, o + i * 2)[0]


def _axes(d, vp, frame, scale):
    """The three animated values of a mstudioanim_valueptr_t at vp (zero where an axis has none)."""
    offs = struct.unpack_from("<3h", d, vp)
    return [(_value(d, vp + offs[i], frame) * scale[i]) if offs[i] > 0 else 0.0 for i in range(3)]


class _Model:
    def __init__(self, fs, path):
        self.d = d = fs.read(path)
        if d is None:
            raise FileNotFoundError(path)
        nb, bi = struct.unpack_from("<ii", d, 156)
        self.nanim, self.animi = struct.unpack_from("<ii", d, 180)
        self.bones = []
        for i in range(nb):
            o = bi + i * 216
            self.bones.append(dict(
                name=cstr(d, o + struct.unpack_from("<i", d, o)[0]), parent=struct.unpack_from("<i", d, o + 4)[0],
                pos=struct.unpack_from("<3f", d, o + 32), quat=struct.unpack_from("<4f", d, o + 44),
                rot=struct.unpack_from("<3f", d, o + 60), posscale=struct.unpack_from("<3f", d, o + 72),
                rotscale=struct.unpack_from("<3f", d, o + 84)))
        abn, nab, abi = struct.unpack_from("<iii", d, 348)
        self.blocks = [struct.unpack_from("<ii", d, abi + i * 8) for i in range(nab)]
        self.ani = None
        if nab:
            name = cstr(d, abn)
            self.ani = fs.read(name) or fs.read(name.lower())
        self.by_name = {}
        for i in range(self.nanim):
            a = self.animi + i * 100
            self.by_name[cstr(d, a + struct.unpack_from("<i", d, a + 4)[0])] = a

    def _data(self, a, frame, numframes):
        """(buffer, offset) of the mstudioanim_t chain holding `frame`, and the frame within it."""
        d = self.d
        block, index = struct.unpack_from("<ii", d, a + 52)
        secidx, secframes = struct.unpack_from("<ii", d, a + 80)
        local = frame
        if secframes:
            if numframes > secframes and frame == numframes - 1:
                section, local = numframes // secframes + 1, 0
            else:
                section = frame // secframes
                local = frame - section * secframes
            block, index = struct.unpack_from("<ii", d, a + secidx + section * 8)
        if block == 0:
            return d, a + index, local
        if self.ani is None:
            raise FileNotFoundError("animation block file")
        return self.ani, self.blocks[block][0] + index, local

    def pose(self, a, frame, numframes):
        """{bone index: (pos, quat)} in Source space for the bones this animation moves."""
        buf, p, local = self._data(a, frame, numframes)
        out = {}
        while True:
            bone, flags, nxt = struct.unpack_from("<BBh", buf, p)
            b = self.bones[bone]
            data = p + 4
            if flags & RAWROT2:
                q = _quat64(buf, data)
            elif flags & RAWROT:
                q = _quat48(buf, data)
            elif flags & ANIMROT:
                v = _axes(buf, data, local, b["rotscale"])
                q = _angle_quat(*v) if flags & DELTA else _angle_quat(*(b["rot"][i] + v[i] for i in range(3)))
            else:
                q = b["quat"]
            rot_size = 8 if flags & RAWROT2 else 6 if flags & (RAWROT | ANIMROT) else 0
            if flags & RAWPOS:
                pos = struct.unpack_from("<3e", buf, data + rot_size)
            elif flags & ANIMPOS:
                v = _axes(buf, data + (6 if flags & ANIMROT else 0), local, b["posscale"])
                pos = tuple(v) if flags & DELTA else tuple(b["pos"][i] + v[i] for i in range(3))
            else:
                pos = b["pos"]
            out[bone] = (pos, q)
            if nxt == 0:
                break
            p += nxt
        return out


def _qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def _qrot(q, v):
    x, y, z, _w = _qmul(_qmul(q, (v[0], v[1], v[2], 0.0)), (-q[0], -q[1], -q[2], q[3]))
    return (x, y, z)


def _root_turn(m):
    """{root bone index: quaternion} taking the animations' frame back to the bone table's rest
    (Source space), from the "reference" animation; empty if there is none."""
    a = m.by_name.get("reference") or m.by_name.get("@reference")
    if a is None:
        return {}
    frames = struct.unpack_from("<i", m.d, a + 16)[0]
    out = {}
    for bone, (_pos, q) in m.pose(a, 0, frames).items():
        b = m.bones[bone]
        if b["parent"] < 0:
            r = b["quat"]
            # rest * reference^-1: turns a reference-frame root pose onto the rest one
            out[bone] = _qmul(r, (-q[0], -q[1], -q[2], q[3]))
    return out


def anims(fs, path, names):
    m = _Model(fs, path)
    turn = _root_turn(m)
    out = {}
    for name in names:
        a = m.by_name.get(name) or m.by_name.get("@" + name)
        if a is None:
            continue
        fps, aflags, frames, nmov, movi = struct.unpack_from("<fiiii", m.d, a + 8)
        move = 0.0
        for j in range(nmov):
            pos = struct.unpack_from("<3f", m.d, a + movi + j * 44 + 32)
            move += pos[0] * SCALE
        poses = [m.pose(a, f, frames) for f in range(frames)]
        # An animation stored in sections (sectionframes, 30 for the antlion guard's and the hunter's long
        # idles; its last frame has a section of its own) lists in each section only the bones that leave
        # their rest pose there. A bone missing from a section sits at its rest for that section: the
        # engine poses it so (CalcAnimation takes the bone table's pos / quat, zero for a delta animation),
        # and in the data the frames next to such a gap, and frame 0 of a loop whose separate last frame
        # leaves a bone out, hold that bone at its rest. So a missing bone is filled with its rest, and
        # then goes through the same conversion as every other frame.
        delta = bool(aflags & 0x4)  # STUDIO_DELTA
        moved = sorted(set().union(*[set(p) for p in poses]))
        bones = {}
        for bone in moved:
            b = m.bones[bone]
            rest = ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)) if delta else (b["pos"], b["quat"])
            e = bones[b["name"]] = {"r": [], "p": []}
            for f in range(frames):
                pos, q = poses[f].get(bone, rest)
                if bone in turn:
                    q = _qmul(turn[bone], q)
                    pos = _qrot(turn[bone], pos)
                n = math.sqrt(sum(c * c for c in q)) or 1.0
                e["r"].append([round(q[0] / n, 5), round(q[2] / n, 5), round(-q[1] / n, 5), round(q[3] / n, 5)])
                e["p"].append([round(pos[0] * SCALE, 5), round(pos[2] * SCALE, 5), round(-pos[1] * SCALE, 5)])
        out[name] = {"fps": fps, "frames": frames, "move": round(move, 4), "bones": bones}
    return out
