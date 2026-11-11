#!/usr/bin/env python3
"""AshenOS: собирает цветовую схему KDE из темы, оттенка и уровня окраски фона.

mkscheme.py THEME ACCENT TINT OUT.colors
  THEME  — id из /usr/share/ashenos/themes.psv (obsidian, gruvbox, ...)
  ACCENT — auto | orange | red | ... | #rrggbb
  TINT   — 0 / 1 / 2 (как «Окраска фона» в Параметрах)
Печатает акцентный цвет в виде r,g,b — его пишут в kdeglobals AccentColor.
"""
import sys

TABLE = "/usr/share/ashenos/themes.psv"
TINTS = {
    "orange": "#ff8a3d", "red": "#ff5c5c", "pink": "#ff6fae", "yellow": "#f5c84b",
    "green": "#59c27a", "teal": "#2ec4b6", "blue": "#5aa8ff", "purple": "#b48cff",
    "white": "#f2f2f4",
}
LEVEL = [0.0, 0.07, 0.16]


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, k):
    a, b = rgb(a), rgb(b)
    return "#%02x%02x%02x" % tuple(round(x + (y - x) * k) for x, y in zip(a, b))


def c(h):
    return ",".join(str(v) for v in rgb(h))


def lum(h):
    r, g, b = (v / 255 for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def main():
    tid, acc_in, lvl, out = sys.argv[1], sys.argv[2].lower(), int(sys.argv[3] or 0), sys.argv[4]
    rows = {}
    for line in open(TABLE, encoding="utf-8"):
        p = line.strip().split("|")
        if len(p) >= 11:
            rows[p[0]] = dict(name=p[1], bg=p[2], surface=p[3], text=p[4], accent=p[5], dots=p[6:11])
    T = rows.get(tid) or rows["obsidian"]
    if acc_in in ("", "auto", "theme"):
        acc = T["accent"] or T["dots"][0]
    elif acc_in.startswith("#") and len(acc_in) == 7:
        acc = acc_in
    else:
        acc = TINTS.get(acc_in, T["accent"] or "#ff9a4d")
    K = LEVEL[max(0, min(2, lvl))]
    bg = mix(T["bg"], acc, K)
    surf = mix(T["surface"], acc, K * 1.2)
    btn = mix(surf, T["text"], 0.08)
    alt = mix(surf, T["text"], 0.04)
    text = T["text"] if T["text"] != "#4fe3ff" else "#e6f7ff"
    dim = mix(text, bg, 0.42)
    sel_fg = "#111114" if lum(acc) > 0.5 else "#f6f6f8"
    neg, neu, pos = T["dots"][4], T["dots"][2], T["dots"][3]

    def block(name, back, alt_):
        return f"""[Colors:{name}]
BackgroundNormal={c(back)}
BackgroundAlternate={c(alt_)}
ForegroundNormal={c(text)}
ForegroundInactive={c(dim)}
ForegroundActive={c(acc)}
ForegroundLink={c(acc)}
ForegroundVisited={c(mix(acc, text, .35))}
ForegroundNegative={c(neg)}
ForegroundNeutral={c(neu)}
ForegroundPositive={c(pos)}
DecorationFocus={c(acc)}
DecorationHover={c(mix(acc, text, .3))}

"""
    s = f"""[General]
ColorScheme=AshenOS
Name=AshenOS · {T['name']}
shadeSortColumn=true

[ColorEffects:Inactive]
ChangeSelectionColor=true
Enable=false

"""
    s += block("Window", bg, mix(bg, text, .03))
    s += block("View", mix(bg, "#000000", .35), mix(bg, text, .03))
    s += block("Button", btn, alt)
    s += block("Header", surf, alt)
    s += block("Tooltip", surf, alt)
    s += block("Complementary", bg, surf)
    s += f"""[Colors:Selection]
BackgroundNormal={c(acc)}
BackgroundAlternate={c(mix(acc, bg, .3))}
ForegroundNormal={c(sel_fg)}
ForegroundInactive={c(mix(sel_fg, acc, .4))}
ForegroundActive={c(sel_fg)}
ForegroundLink={c(sel_fg)}
ForegroundVisited={c(sel_fg)}
ForegroundNegative={c(neg)}
ForegroundNeutral={c(neu)}
ForegroundPositive={c(pos)}
DecorationFocus={c(acc)}
DecorationHover={c(acc)}

[WM]
activeBackground={c(surf)}
activeForeground={c(text)}
activeBlend={c(surf)}
inactiveBackground={c(bg)}
inactiveForeground={c(dim)}
inactiveBlend={c(bg)}
"""
    open(out, "w", encoding="utf-8").write(s)
    print(c(acc))


if __name__ == "__main__":
    main()
