"""Branches of a circuit's lap (shortcuts, jumps, high roads): open splines, the launch speed a
jump needs, the lap metres a branch's metres count as (s_main) and its track JSON entry. Shared
by the generators (tools/track_gen.py builds them; tools/build_track.py can use the same pieces).

The JSON entry (data["branches"], read by scripts/track/track_branch.gd):
  id, name, index, kind, fork_s / merge_s (lap metres, the game's convention: exported index *
  length / exported count), fork_i / merge_i (exported main indices), fork_nose_u / merge_nose_u
  (branch metres of the noses, where the roads part for good), fork_nose_i / merge_nose_i, side /
  merge_side (+1 right of the main road), length, saves, risk, need_speed, need_boost, ai {take,
  min_skill[, commit]}, respawn, retry_back, offtrack, merge_type, in_hall, and a path with the main path's
  keys plus closed false and s_main (monotone, fork_s .. merge_s): evenly spaced samples, the
  last one at the branch's end.
"""
import math

import numpy as np

# the jumps' gravity unless a circuit gives its own (TRACK["gravity"]; the game's is project.godot's
# 3d/default_gravity, 15.24)
G = 9.8
# a jump needs this much more than its bare ballistic launch speed ...
SPEED_MARGIN = 1.08
# ... and one that needs more than the NORMAL top speed is for boosted karts only
TOP_SPEED = 31.0
# the game's sample search around a hint (TrackPath.closest)
WINDOW = (-12, 25)


def catmull_rom_open(pts, pre, post, samples_per_seg=200):
    """Centripetal Catmull-Rom through pts (open). pre / post are phantom points that fix the end
    tangents (behind the first point and past the last). Returns dense (N,3), segment (N,) and t
    (N,) like build_track.catmull_rom_closed; the very last point (t = 1) is included."""
    P = [np.asarray(pre, float)] + [np.asarray(p, float) for p in pts] + [np.asarray(post, float)]
    out, seg, tt = [], [], []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]

        def tj(ti, a, b):
            return ti + max(np.linalg.norm(b - a), 1e-6) ** 0.5

        t0 = 0.0
        t1 = tj(t0, p0, p1)
        t2 = tj(t1, p1, p2)
        t3 = tj(t2, p2, p3)
        for k in range(samples_per_seg + (1 if i == len(P) - 3 else 0)):
            t = t1 + (t2 - t1) * k / samples_per_seg
            a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
            a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
            a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
            b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
            b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
            out.append((t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2)
            seg.append(i - 1)
            tt.append(k / samples_per_seg)
    return np.array(out), np.array(seg), np.array(tt)


def launch_speed(gap, lift, ramp_len, drop, g=G):
    """Speed at a kicker's lip (a u^2 ramp rising `lift` over `ramp_len` metres) that carries a kart
    over `gap` metres and 2 more to land on, with the far road `drop` metres below the lip
    (negative: above it), under gravity g."""
    th = math.atan(2.0 * lift / ramp_len)
    lo, hi = 1.0, 120.0
    for _ in range(60):
        v = 0.5 * (lo + hi)
        vs, vc = v * math.sin(th), v * math.cos(th)
        disc = vs * vs + 2.0 * g * drop
        if disc >= 0.0 and vc * (vs + math.sqrt(disc)) / g >= gap + 2.0:
            hi = v
        else:
            lo = v
    return hi


class LapPath:
    """The main loop as the game samples it (the exported path) with the game's own closest() and
    progress() (scripts/track/track_path.gd), so the lap metres written for a branch are the ones
    the game measures on the main road."""

    def __init__(self, center, fwd, length):
        self.c = np.asarray(center, float)
        self.f = np.asarray(fwd, float)
        self.n = len(self.c)
        self.length = float(length)
        self.step = self.length / self.n

    def closest(self, p, hint, ahead=None):
        """Sample nearest p around `hint` (height counts double, every sample away from the hint
        costs a little); `ahead` widens the search forward to that many samples."""
        k = np.arange(WINDOW[0], max(WINDOW[1], (ahead or 0) + 1))
        i = (hint + k) % self.n
        dv = p - self.c[i]
        d = dv[:, 0] ** 2 + dv[:, 2] ** 2 + 4.0 * dv[:, 1] ** 2 + np.abs(k) * self.step * 0.5
        j = int(np.argmin(d))
        return int(i[j]), int(k[j])

    def progress(self, p, i):
        """Lap metres of p near sample i: between the cross-section planes of i and its neighbour."""
        i %= self.n
        d = float((p - self.c[i]) @ self.f[i])
        s = i * self.step + d
        j = (i + (1 if d >= 0.0 else -1)) % self.n
        dj = float((p - self.c[j]) @ self.f[j])
        if d >= 0.0 > dj:
            s = i * self.step + self.step * d / (d - dj)
        elif d < 0.0 <= dj:
            s = i * self.step - self.step * d / (d - dj)
        return s % self.length


def s_main(lap, pts, near, fork_i, merge_i, noses):
    """Lap metres for each branch point pts (the exported samples, evenly spaced): monotone from
    fork_s to merge_s. Up to the fork's nose and from the merge's nose on (noses: their sample
    indices), and along any stretch where the branch runs beside the main road (near[k], the
    projection advancing steadily for 30 m or more), it is the game's own progress of the point,
    projected in lap order, so switching roads there never moves a kart's place. In between it is
    a smooth cubic from one such stretch to the next, leaving and meeting each at its own rate, so
    the mapped progress never jumps (a shortcut gains places gradually) and its rate changes
    slowly (the game's progress check allows 1.5 m per metre)."""
    m = len(pts)
    fork_s, merge_s = fork_i * lap.step, merge_i * lap.step
    proj = np.full(m, np.nan)
    hint = fork_i
    for k in range(m):
        if not near[k]:
            continue
        i, _ = lap.closest(pts[k], hint, ahead=merge_i - hint + 12)
        s = lap.progress(pts[k], i)
        # lap metres from the fork on (the stretch never wraps: 0.04 L < fork < merge < 0.96 L)
        proj[k] = fork_s + (s - fork_s + lap.length / 2) % lap.length - lap.length / 2
        hint = max(hint, i)
    # in between the noses only runs beside the main road that advance steadily (not where the
    # nearest stretch changes: a road passing over another leg of the lap), a sample off each end
    step = float(np.linalg.norm(pts[1] - pts[0])) if m > 1 else 1.0
    keep = np.zeros(m, bool)
    keep[:noses[0] + 1] = keep[noses[1]:] = True
    rate = np.diff(proj) / step
    steady = np.concatenate([[False], (rate > 0.25) & (rate < 3.0)])
    k = noses[0] + 1
    while k < noses[1]:
        if not steady[k]:
            k += 1
            continue
        e = k
        while e < noses[1] and steady[e]:
            e += 1
        if (e - k) * step >= 30.0:
            keep[k + 1:e - 1] = True
        k = e
    proj = np.where(keep, proj, np.nan)
    proj[0], proj[-1] = fork_s, merge_s
    out = proj.copy()
    anchors = np.flatnonzero(~np.isnan(proj))
    for a, b in zip(anchors[:-1], anchors[1:]):
        if b - a < 2:
            continue
        span = (b - a) * step
        sec = (proj[b] - proj[a]) / span
        # each end's own rate (the projection beside it), kept monotone (Fritsch-Carlson)
        ra = (proj[a] - proj[a - 1]) / step if a > 0 and not np.isnan(proj[a - 1]) else sec
        rb = (proj[b + 1] - proj[b]) / step if b < m - 1 and not np.isnan(proj[b + 1]) else sec
        ra, rb = np.clip([ra, rb], 0.0, 3.0 * max(sec, 0.0))
        x = np.arange(b - a + 1) / (b - a)
        out[a:b + 1] = ((2 * x ** 3 - 3 * x ** 2 + 1) * proj[a] + (x ** 3 - 2 * x ** 2 + x) * span * ra +
                        (3 * x ** 2 - 2 * x ** 3) * proj[b] + (x ** 3 - x ** 2) * span * rb)
    out = np.clip(np.maximum.accumulate(out), fork_s, merge_s)
    out[0], out[-1] = fork_s, merge_s
    return out


def entry(spec, index, path, **fields):
    """The track JSON entry of branch `spec` (a BRANCHES item): its own keys with their defaults,
    the computed fields (fork_s, merge_s, ..., need_speed) and the path."""
    ai = spec.get("ai", {})
    e = {"id": spec["id"], "name": spec.get("name", spec["id"]), "index": index, "kind": spec.get("kind", "alt")}
    e.update(fields)
    ai_out = {"take": float(ai.get("take", 0.5)), "min_skill": float(ai.get("min_skill", 0.0))}
    if "commit" in ai:
        # (metres before its gap from which a computer driver goes flat out at it; default 40)
        ai_out["commit"] = float(ai["commit"])
    e.update({"risk": float(spec.get("risk", 0.0)), "ai": ai_out,
              "respawn": spec.get("respawn", "before"), "retry_back": float(spec.get("retry_back", 45.0)),
              "offtrack": float(spec.get("offtrack", -1.0)), "merge_type": spec.get("merge_type", "gore"),
              "in_hall": bool(spec.get("in_hall", False)), "path": path})
    return e
