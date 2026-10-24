"""Source WAV/MP3 export: decodes MS-ADPCM, keeps loop points (cue -> smpl) for Godot."""
import os
import struct

import numpy as np

MS_COEF = [(256, 0), (512, -256), (0, 0), (192, 64), (240, 0), (460, -208), (392, -232)]
MS_ADAPT = [230, 230, 230, 230, 307, 409, 512, 614, 768, 614, 512, 409, 307, 230, 230, 230]


def _chunks(d):
    i = 12
    while i + 8 <= len(d):
        cid = d[i : i + 4]
        sz = struct.unpack_from("<I", d, i + 4)[0]
        yield cid, d[i + 8 : i + 8 + sz]
        i += 8 + sz + (sz & 1)


def _msadpcm(data, channels, block_align, samples_per_block):
    out = []
    for b in range(0, len(data) - 7 * channels + 1, block_align):
        blk = data[b : b + block_align]
        if len(blk) < 7 * channels:
            break
        p = 0
        pred = list(blk[p : p + channels]); p += channels
        delta = list(struct.unpack_from("<%dh" % channels, blk, p)); p += 2 * channels
        s1 = list(struct.unpack_from("<%dh" % channels, blk, p)); p += 2 * channels
        s2 = list(struct.unpack_from("<%dh" % channels, blk, p)); p += 2 * channels
        frames = [s2[:], s1[:]]
        nib = []
        for byte in blk[p:]:
            nib.append(byte >> 4)
            nib.append(byte & 15)
        ch = 0
        cur = []
        for n in nib:
            c1, c2 = MS_COEF[pred[ch] if pred[ch] < 7 else 0]
            sn = n - 16 if n & 8 else n
            val = ((s1[ch] * c1 + s2[ch] * c2) >> 8) + sn * delta[ch]
            val = max(-32768, min(32767, val))
            s2[ch] = s1[ch]
            s1[ch] = val
            delta[ch] = max(16, (MS_ADAPT[n] * delta[ch]) >> 8)
            cur.append(val)
            ch += 1
            if ch == channels:
                frames.append(cur)
                cur = []
                ch = 0
        out.extend(frames[: samples_per_block])
    return np.array(out, dtype=np.int16).reshape(-1, channels)


def convert_wav(d):
    """Returns RIFF bytes Godot can import (PCM 8/16, loop in smpl)."""
    fmt = None
    data = None
    loop = None
    cue = None
    for cid, body in _chunks(d):
        if cid == b"fmt ":
            fmt = body
        elif cid == b"data":
            data = body
        elif cid == b"smpl" and len(body) >= 36:
            nloops = struct.unpack_from("<I", body, 28)[0]
            if nloops and len(body) >= 36 + 24:
                _, _, start, end, _, _ = struct.unpack_from("<6I", body, 36)
                loop = (start, end)
        elif cid == b"cue " and len(body) >= 28:
            cue = struct.unpack_from("<I", body, 4 + 20)[0]
    tag, ch, rate, _, align, bits = struct.unpack_from("<HHIIHH", fmt, 0)
    if tag == 2:
        spb = struct.unpack_from("<H", fmt, 20)[0]
        pcm = _msadpcm(data, ch, align, spb)
        data = pcm.tobytes()
        bits = 16
        tag = 1
    elif tag != 1:
        raise ValueError("unsupported wav tag %d" % tag)
    nframes = len(data) // (ch * bits // 8)
    if loop is None and cue is not None:
        loop = (cue, nframes - 1)
    out = bytearray()
    fmtb = struct.pack("<HHIIHH", 1, ch, rate, rate * ch * bits // 8, ch * bits // 8, bits)
    chunks = [(b"fmt ", fmtb), (b"data", data)]
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / rate), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, loop[0], max(loop[0], min(loop[1], nframes - 1)), 0, 0)
        chunks.append((b"smpl", smpl))
    for cid, body in chunks:
        out += cid + struct.pack("<I", len(body)) + body
        if len(body) & 1:
            out += b"\0"
    return b"RIFF" + struct.pack("<I", len(out) + 4) + b"WAVE" + bytes(out), (loop is not None)


def export(fs, snd, out_root):
    """snd: path under sound/ (e.g. 'vehicles/v8/first.wav'). Returns rel path or None."""
    snd = snd.lower().replace("\\", "/").lstrip("*#@)^<>")
    src = "sound/" + snd
    out = os.path.join(out_root, "sound", snd)
    if os.path.exists(out):
        return "sound/" + snd
    d = fs.read(src)
    if d is None:
        print("  !! missing sound", snd)
        return None
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if snd.endswith(".wav"):
        try:
            d, _ = convert_wav(d)
        except Exception as e:  # noqa
            print("  !! wav", snd, e)
            return None
    with open(out, "wb") as f:
        f.write(d)
    return "sound/" + snd
