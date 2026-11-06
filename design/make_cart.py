#!/usr/bin/env python3
"""Erzeugt die Layer des BuyFood-App-Icons (SVG, 1024x1024, transparent) – ohne eingebackene
Highlights/Schatten, die erledigt Liquid Glass. Aufruf: python3 make_cart.py <ausgabeordner>"""
import math, os, sys

out = sys.argv[1] if len(sys.argv) > 1 else "layers"
os.makedirs(out, exist_ok=True)

def rounded(points, r):
    """Geschlossener Pfad mit gerundeten Ecken (quadratische Kurven)."""
    n = len(points); d = []
    for i in range(n):
        p0, p1, p2 = points[i - 1], points[i], points[(i + 1) % n]
        def toward(a, b, dist):
            L = math.dist(a, b); t = min(dist, L / 2) / L
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        a, b = toward(p1, p0, r), toward(p1, p2, r)
        d.append(("M" if i == 0 else "L") + f"{a[0]:.1f} {a[1]:.1f}")
        d.append(f"Q{p1[0]:.1f} {p1[1]:.1f} {b[0]:.1f} {b[1]:.1f}")
    return " ".join(d) + " Z"

def slot(cx, cy, w, h):
    r = h / 2
    return (f"M{cx-w/2+r:.1f} {cy-h/2:.1f} H{cx+w/2-r:.1f} A{r} {r} 0 0 1 {cx+w/2-r:.1f} {cy+h/2:.1f} "
            f"H{cx-w/2+r:.1f} A{r} {r} 0 0 1 {cx-w/2+r:.1f} {cy-h/2:.1f} Z")

def circle(cx, cy, r):
    return f"M{cx-r} {cy} A{r} {r} 0 1 0 {cx+r} {cy} A{r} {r} 0 1 0 {cx-r} {cy} Z"

# --- Geometrie (lokal), danach leicht gedreht für die Schräglage ---
F = [(230, 340), (780, 340), (715, 610), (295, 610)]            # Vorderseite Korb
dx, dy = 85, -70                                                  # Tiefe
B = [(x + dx, y + dy) for x, y in F]
TOP = [F[0], F[1], B[1], B[0]]                                    # Korbinneres (von oben)
SIDE = [F[1], B[1], B[2], F[2]]                                   # rechte Seitenwand

TRANSFORM = "translate(512 512) rotate(-10) scale(1.1) translate(-480 -520)"

def svg(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f"<defs>{defs}</defs><g transform=\"{TRANSFORM}\">{body}</g></svg>")

def grad(id_, c1, c2, x1=0, y1=0, x2=1, y2=1, mid=None):
    m = f'<stop offset="0.5" stop-color="{mid}"/>' if mid else ""
    return (f'<linearGradient id="{id_}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">'
            f'<stop offset="0" stop-color="{c1}"/>{m}<stop offset="1" stop-color="{c2}"/></linearGradient>')

# Layer 1: Tiefe (Rückwand, Inneres, Seitenwand, hintere Räder)
depth_defs = (grad("inner", "#0C7C8A", "#0A4AA0", 0, 0, 1, 0) + grad("side", "#0E9A8C", "#1546B8", 0, 0, 0.6, 1)
              + grad("back", "#0A5F86", "#0A3D8F") + grad("wheelb", "#127E9E", "#1B45B0"))
depth = (f'<path d="{rounded(B, 26)}" fill="url(#back)"/>'
         f'<path d="{rounded(F, 30)}" fill="url(#back)"/>'
         f'<path d="{rounded(TOP, 14)}" fill="url(#inner)"/>'
         f'<path d="{rounded(SIDE, 20)}" fill="url(#side)"/>'
         f'<path d="{circle(432, 700, 50)} {circle(432, 700, 18)}" fill="url(#wheelb)" fill-rule="evenodd"/>'
         f'<path d="{circle(772, 702, 50)} {circle(772, 702, 18)}" fill="url(#wheelb)" fill-rule="evenodd"/>')
open(f"{out}/cart-depth.svg", "w").write(svg(depth_defs, depth))

# Layer 2: Rahmen (Griff, Chassis, vordere Räder)
frame_defs = grad("frame", "#25B5D6", "#2459D8", 0, 0, 1, 1)
frame = (f'<path d="M95 238 L208 238 L292 662 L742 662" fill="none" stroke="url(#frame)" stroke-width="46" '
         f'stroke-linecap="round" stroke-linejoin="round"/>'
         f'<path d="{circle(360, 748, 60)} {circle(360, 748, 21)}" fill="url(#frame)" fill-rule="evenodd"/>'
         f'<path d="{circle(702, 748, 60)} {circle(702, 748, 21)}" fill="url(#frame)" fill-rule="evenodd"/>')
open(f"{out}/cart-frame.svg", "w").write(svg(frame_defs, frame))

# Layer 3: Korb vorne mit Gitterschlitzen
def edge_x(y):  # linke/rechte Kante der Vorderseite bei y
    t = (y - 340) / 270
    return 230 + 65 * t, 780 - 65 * t
slots = ""
for y in (400, 462, 524):
    l, r = edge_x(y)
    slots += " " + slot((l + r) / 2, y, (r - l) - 110, 26)
body_defs = grad("body", "#3DEBA0", "#1D70F2", 0.0, 0.0, 1, 1, mid="#25BFC8")
body = f'<path d="{rounded(F, 30)}{slots}" fill="url(#body)" fill-rule="evenodd"/>'
open(f"{out}/cart-body.svg", "w").write(svg(body_defs, body))

# Komplett (für das Login-Bild)
all_defs = depth_defs + frame_defs + body_defs
open(f"{out}/cart-all.svg", "w").write(svg(all_defs, depth + frame + body))
print("ok")
