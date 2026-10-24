"""Minimal Valve KeyValues text parser (VMT, scripts, $keyvalues blocks).

Result: list of (key, value) pairs where value is a str or a nested list.
Keys keep their original case; use kv_get() for case-insensitive lookups.
"""


def _tokens(text):
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n﻿":
            i += 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j + 1
        elif c == '"':
            j = i + 1
            buf = []
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n and text[j + 1] in '"\\':
                    j += 1
                buf.append(text[j])
                j += 1
            yield ("s", "".join(buf))
            i = j + 1
        elif c in "{}":
            yield (c, c)
            i += 1
        elif c == "[":
            # platform conditional like [$X360] - skip
            j = text.find("]", i)
            if j < 0:
                j = n
            yield ("cond", text[i + 1 : j])
            i = j + 1
        else:
            j = i
            while j < n and text[j] not in " \t\r\n{}\"":
                j += 1
            yield ("s", text[i:j])
            i = j


def parse(text):
    toks = list(_tokens(text))
    pos = 0

    def block():
        nonlocal pos
        out = []
        while pos < len(toks):
            t, v = toks[pos]
            if t == "}":
                pos += 1
                return out
            if t == "cond":
                pos += 1
                continue
            if t == "{":
                pos += 1
                out.append(("", block()))
                continue
            key = v
            pos += 1
            if pos >= len(toks):
                break
            t2, v2 = toks[pos]
            if t2 == "{":
                pos += 1
                out.append((key, block()))
            elif t2 == "s":
                pos += 1
                # conditional after value e.g. "$x" "1" [!$X360]
                skip = False
                if pos < len(toks) and toks[pos][0] == "cond":
                    cond = text_cond(toks[pos][1])
                    skip = not cond
                    pos += 1
                if not skip:
                    out.append((key, v2))
            else:
                pos += 1
        return out

    return block()


def text_cond(s):
    # we are a PC: [$X360]/[$PS3]/[$GAMECONSOLE] false, [!$X360] true, [$WIN32] true
    s = s.upper().strip()
    neg = s.startswith("!")
    name = s.lstrip("!").lstrip("$")
    truth = name in ("WIN32", "WINDOWS", "PC")
    return truth != neg


def kv_get(block, key, default=None):
    key = key.lower()
    for k, v in block:
        if k.lower() == key:
            return v
    return default


def kv_get_all(block, key):
    key = key.lower()
    return [v for k, v in block if k.lower() == key]


def to_dict(block):
    """Flatten first level to lowercase dict (last wins), nested -> dict."""
    d = {}
    for k, v in block:
        d[k.lower()] = to_dict(v) if isinstance(v, list) else v
    return d
