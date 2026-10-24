"""VTF (Valve Texture Format) decoder -> PIL.Image (largest mip, frame 0, face 0)."""
import io
import struct

import numpy as np
from PIL import Image

# image format ids from the SDK's ImageFormat enum
RGBA8888, ABGR8888, RGB888, BGR888, RGB565, I8, IA88, P8, A8 = range(9)
RGB888_BLUESCREEN, BGR888_BLUESCREEN, ARGB8888, BGRA8888 = 9, 10, 11, 12
DXT1, DXT3, DXT5, BGRX8888, BGR565, BGRX5551, BGRA4444 = 13, 14, 15, 16, 17, 18, 19
DXT1_ONEBITALPHA, BGRA5551, UV88, UVWQ8888, RGBA16161616F, RGBA16161616, UVLX8888 = 20, 21, 22, 23, 24, 25, 26

BPP = {
    RGBA8888: 4, ABGR8888: 4, RGB888: 3, BGR888: 3, RGB565: 2, I8: 1, IA88: 2, P8: 1, A8: 1,
    RGB888_BLUESCREEN: 3, BGR888_BLUESCREEN: 3, ARGB8888: 4, BGRA8888: 4, BGRX8888: 4,
    BGR565: 2, BGRX5551: 2, BGRA4444: 2, BGRA5551: 2, UV88: 2, UVWQ8888: 4,
    RGBA16161616F: 8, RGBA16161616: 8, UVLX8888: 4,
}
TEXTUREFLAGS_ENVMAP = 0x4000


def _size(fmt, w, h):
    if fmt in (DXT1, DXT1_ONEBITALPHA):
        return max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 8
    if fmt in (DXT3, DXT5):
        return max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 16
    return w * h * BPP[fmt]


def _dds(fmt, w, h, payload):
    fourcc = {DXT1: b"DXT1", DXT1_ONEBITALPHA: b"DXT1", DXT3: b"DXT3", DXT5: b"DXT5"}[fmt]
    hdr = struct.pack(
        "<4sIIIIIII44sII4sIIIIIIIIII",
        b"DDS ", 124, 0x81007, h, w, len(payload), 0, 0, b"\0" * 44,
        32, 0x4, fourcc, 0, 0, 0, 0, 0, 0x1000, 0, 0, 0, 0,
    )
    return Image.open(io.BytesIO(hdr + payload)).convert("RGBA")


def _half_to_float(a):
    return a.view(np.float16).astype(np.float32)


def decode(data, frame=0):
    """Returns (PIL RGBA image, info dict) for one animation frame of the top mip."""
    sig = data[:4]
    if sig != b"VTF\0":
        raise ValueError("not a VTF")
    vmaj, vmin, hdr_size = struct.unpack_from("<III", data, 4)
    w, h, flags, frames, first_frame = struct.unpack_from("<HHIHH", data, 16)
    reflectivity = struct.unpack_from("<fff", data, 32)
    fmt = struct.unpack_from("<i", data, 52)[0]
    mips = data[56]
    lr_fmt = struct.unpack_from("<i", data, 57)[0]
    lr_w, lr_h = data[61], data[62]
    depth = 1
    if vmin >= 2:
        depth = max(1, struct.unpack_from("<H", data, 63)[0])
    faces = 1
    if flags & TEXTUREFLAGS_ENVMAP:
        faces = 6 if (vmin >= 5 or first_frame == 0xFFFF) else 7
    hi_off = None
    if vmin >= 3:
        nres = struct.unpack_from("<I", data, 68)[0]
        for i in range(nres):
            tag, rflags, roff = struct.unpack_from("<3sBI", data, 80 + i * 8)
            if tag == b"\x30\0\0":
                hi_off = roff
    if hi_off is None:
        lr_size = _size(lr_fmt, lr_w, lr_h) if lr_fmt >= 0 and lr_w else 0
        hi_off = hdr_size + lr_size
    # data runs smallest mip -> largest
    off = hi_off
    for m in range(mips - 1, 0, -1):
        mw, mh = max(1, w >> m), max(1, h >> m)
        off += _size(fmt, mw, mh) * frames * faces * depth
    n = _size(fmt, w, h)
    off += min(frame, max(frames - 1, 0)) * n * faces * depth
    raw = data[off : off + n]
    img = to_image(fmt, w, h, raw)
    info = dict(width=w, height=h, flags=flags, format=fmt, frames=frames, reflectivity=reflectivity)
    return img, info


def to_image(fmt, w, h, raw):
    if fmt in (DXT1, DXT1_ONEBITALPHA, DXT3, DXT5):
        return _dds(fmt, w, h, raw)
    a = np.frombuffer(raw, dtype=np.uint8)
    if fmt == RGBA8888:
        px = a.reshape(h, w, 4)
    elif fmt == ABGR8888:
        px = a.reshape(h, w, 4)[:, :, ::-1]
    elif fmt == ARGB8888:
        px = a.reshape(h, w, 4)[:, :, [1, 2, 3, 0]]
    elif fmt == BGRA8888:
        px = a.reshape(h, w, 4)[:, :, [2, 1, 0, 3]]
    elif fmt in (BGRX8888,):
        p = a.reshape(h, w, 4)[:, :, [2, 1, 0, 3]].copy()
        p[:, :, 3] = 255
        px = p
    elif fmt in (RGB888, RGB888_BLUESCREEN):
        p = a.reshape(h, w, 3)
        px = np.dstack([p, np.full((h, w), 255, np.uint8)])
    elif fmt in (BGR888, BGR888_BLUESCREEN):
        p = a.reshape(h, w, 3)[:, :, ::-1]
        px = np.dstack([p, np.full((h, w), 255, np.uint8)])
    elif fmt in (I8, P8):
        p = a.reshape(h, w)
        px = np.dstack([p, p, p, np.full((h, w), 255, np.uint8)])
    elif fmt == A8:
        p = a.reshape(h, w)
        px = np.dstack([np.full((h, w, 3), 255, np.uint8), p])
    elif fmt == IA88:
        p = a.reshape(h, w, 2)
        px = np.dstack([p[:, :, 0], p[:, :, 0], p[:, :, 0], p[:, :, 1]])
    elif fmt in (UV88,):
        p = a.reshape(h, w, 2)
        px = np.dstack([p[:, :, 0], p[:, :, 1], np.full((h, w), 255, np.uint8), np.full((h, w), 255, np.uint8)])
    elif fmt in (UVWQ8888, UVLX8888):
        px = a.reshape(h, w, 4)
    elif fmt in (RGB565, BGR565):
        v = np.frombuffer(raw, dtype="<u2").reshape(h, w).astype(np.uint32)
        r = ((v >> 11) & 31) * 255 // 31
        g = ((v >> 5) & 63) * 255 // 63
        b = (v & 31) * 255 // 31
        if fmt == BGR565:
            r, b = b, r
        px = np.dstack([r, g, b, np.full((h, w), 255)]).astype(np.uint8)
    elif fmt == BGRA4444:
        v = np.frombuffer(raw, dtype="<u2").reshape(h, w).astype(np.uint32)
        b = (v & 15) * 17
        g = ((v >> 4) & 15) * 17
        r = ((v >> 8) & 15) * 17
        al = ((v >> 12) & 15) * 17
        px = np.dstack([r, g, b, al]).astype(np.uint8)
    elif fmt in (BGRA5551, BGRX5551):
        v = np.frombuffer(raw, dtype="<u2").reshape(h, w).astype(np.uint32)
        b = (v & 31) * 255 // 31
        g = ((v >> 5) & 31) * 255 // 31
        r = ((v >> 10) & 31) * 255 // 31
        al = ((v >> 15) & 1) * 255 if fmt == BGRA5551 else np.full((h, w), 255)
        px = np.dstack([r, g, b, al]).astype(np.uint8)
    elif fmt == RGBA16161616F:
        f = _half_to_float(np.frombuffer(raw, dtype="<u2")).reshape(h, w, 4)
        f = np.clip(f[:, :, :3], 0, None)
        f = f / (1.0 + f)  # simple tonemap for LDR preview
        px = np.dstack([(np.clip(f, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8), np.full((h, w), 255, np.uint8)])
    elif fmt == RGBA16161616:
        v = np.frombuffer(raw, dtype="<u2").reshape(h, w, 4)
        px = (v >> 8).astype(np.uint8)
    else:
        raise ValueError("unsupported VTF format %d" % fmt)
    return Image.fromarray(np.ascontiguousarray(px), "RGBA")
