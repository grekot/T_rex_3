"""Postaci Pupila w gładkim stylu: płótno 168 x 168 px, dinozaury patrzą w prawo,
stopy na wysokości ok. 158 px.

Każda forma ma paletę i funkcję build(P) zwracającą:
  back   - kształty za ciałem (dalsze nogi, płyty, skrzydła) - z obrysem
  body   - sylwetka (wspólny obrys jak naklejka)
  detail - bez obrysu: brzuch, plamy, pazurki
  face   - gdzie są oko, usta, policzek (miny rysuje gen_assets.py)
"""
from draw import ell, poly, tube, rrect, shade, mix

FORMS = {}


def form(fid, body, light, dark, accent, build):
    P = {
        "B": body,
        "L": light,
        "D": dark,
        "A": accent,
        "F": shade(body, 0.78),  # dalsze kończyny
        "O": shade(body, 0.30),  # obrys
        "W": (250, 248, 240),
    }
    FORMS[fid] = {"P": P, "build": build}


def spots(pts, r, color):
    return [ell(x, y, r * k, r * k * 0.8, color) for x, y, k in pts]


# --- jajo ------------------------------------------------------------------------
def egg(P):
    return {
        "back": [],
        "body": [ell(84, 98, 50, 60, P["B"])],
        "detail": spots([(64, 70, 1.0), (102, 92, 1.3), (70, 120, 0.9), (110, 130, 0.7), (92, 58, 0.6)], 9, P["D"])
        + [ell(66, 66, 8, 14, P["W"], rot=20)],
        "face": None,
    }


form("egg", (247, 238, 210), (255, 252, 240), (120, 196, 96), (120, 196, 96), egg)


# --- maluch ----------------------------------------------------------------------
def pisklak(P):
    return {
        "back": [ell(96, 150, 13, 8, P["F"])],
        "body": [
            tube([(46, 124), (28, 132), (16, 124)], 12, 4, P["B"]),
            ell(76, 116, 42, 36, P["B"]),
            ell(98, 84, 38, 33, P["B"]),
            ell(66, 151, 14, 8, P["B"]),
            ell(112, 120, 7, 10, P["B"], rot=-20),
        ],
        "detail": [ell(86, 124, 24, 20, P["L"])] + spots([(66, 70, 1.0), (54, 88, 0.8), (80, 60, 0.6)], 6, P["D"]),
        "face": {"eye": (110, 76, 10), "mouth": ("smile", 116, 130, 96), "cheek": (104, 96)},
    }


form("pisklak", (126, 214, 112), (226, 247, 176), (90, 172, 82), (255, 200, 80), pisklak)


# --- dzieci ----------------------------------------------------------------------
def tupek(P):
    return {
        "back": [ell(92, 140, 13, 15, P["F"]), ell(98, 155, 14, 6, P["F"])],
        "body": [
            tube([(54, 126), (30, 144), (10, 134)], 14, 4, P["B"]),
            ell(74, 112, 30, 34, P["B"], rot=-12),
            tube([(88, 92), (100, 76)], 16, 14, P["B"]),
            ell(108, 64, 32, 25, P["B"], rot=-5),
            ell(70, 136, 15, 17, P["B"]),
            ell(72, 154, 16, 6, P["B"]),
            tube([(98, 104), (110, 112)], 5, 4, P["B"]),
        ],
        "detail": [ell(88, 116, 15, 24, P["L"], rot=-15)]
        + spots([(64, 92, 1.0), (54, 108, 0.8), (90, 54, 0.7), (40, 132, 0.6)], 6, P["D"]),
        "face": {"eye": (118, 56, 9), "mouth": ("smile", 118, 136, 76), "cheek": (112, 74)},
    }


form("tupek", (96, 200, 122), (226, 243, 174), (66, 156, 94), (250, 180, 60), tupek)


def gapcio(P):
    return {
        "back": [ell(102, 152, 14, 7, P["F"])],
        "body": [
            tube([(42, 124), (22, 134), (12, 126)], 12, 4, P["B"]),
            ell(82, 106, 46, 46, P["B"]),
            ell(66, 153, 15, 7, P["B"]),
            ell(118, 122, 7, 10, P["B"], rot=-25),
            tube([(80, 62), (76, 48), (82, 40)], 4, 2.5, P["A"]),
            tube([(90, 62), (94, 50), (102, 46)], 4, 2.5, P["A"]),
        ],
        "detail": [ell(88, 122, 28, 24, P["L"])] + spots([(60, 82, 1.0), (52, 104, 0.8), (70, 70, 0.6)], 7, P["D"]),
        "face": {"eye": (108, 90, 9), "mouth": ("smile", 112, 128, 112), "cheek": (104, 108)},
    }


form("gapcio", (236, 164, 92), (252, 224, 176), (196, 116, 64), (150, 96, 64), gapcio)


# --- nastolatki ------------------------------------------------------------------
def rogal(P):
    ivory = (250, 240, 214)
    return {
        "back": [rrect(52, 128, 68, 158, 7, P["F"]), rrect(100, 128, 116, 158, 7, P["F"])],
        "body": [
            ell(112, 82, 24, 30, P["D"], rot=-20),  # kryza
            tube([(36, 106), (16, 114), (6, 108)], 13, 3, P["B"]),
            ell(74, 112, 48, 30, P["B"]),
            ell(124, 102, 26, 21, P["B"], rot=10),
            rrect(36, 126, 52, 158, 7, P["B"]),
            rrect(84, 126, 100, 158, 7, P["B"]),
            tube([(124, 86), (134, 70), (148, 62)], 5, 1.5, ivory),
            tube([(146, 100), (152, 92), (158, 86)], 4, 1.2, ivory),
        ],
        "detail": [ell(76, 128, 36, 10, P["L"])]
        + spots([(60, 98, 1.0), (82, 92, 0.9), (44, 108, 0.7), (100, 100, 0.6)], 6, P["L"])
        + [ell(104, 68, 5, 5, P["A"]), ell(98, 82, 5, 5, P["A"]), ell(110, 58, 4, 4, P["A"])],
        "face": {"eye": (130, 94, 7.5), "mouth": ("smile", 132, 148, 112), "cheek": (128, 108)},
    }


form("rogal", (96, 164, 232), (196, 228, 250), (64, 112, 196), (250, 238, 200), rogal)


def kolec(P):
    plates = []
    for x, y, h in ((44, 90, 16), (62, 80, 22), (82, 78, 24), (102, 84, 20), (118, 96, 14)):
        plates.append(poly([(x - 10, y + 10), (x, y - h), (x + 10, y + 10)], P["A"]))
    return {
        "back": plates + [rrect(50, 126, 66, 158, 7, P["F"]), rrect(102, 126, 118, 158, 7, P["F"])],
        "body": [
            tube([(34, 112), (16, 104), (4, 92)], 12, 3, P["B"]),
            ell(78, 112, 50, 30, P["B"]),
            tube([(118, 116), (132, 120)], 13, 11, P["B"]),
            ell(140, 120, 17, 12, P["B"]),
            rrect(36, 124, 52, 158, 7, P["B"]),
            rrect(88, 124, 104, 158, 7, P["B"]),
            tube([(10, 98), (2, 86)], 2.5, 1, P["W"]),
            tube([(14, 102), (10, 88)], 2.5, 1, P["W"]),
        ],
        "detail": [ell(80, 128, 38, 9, P["L"])] + spots([(62, 104, 1.0), (86, 100, 0.9), (104, 108, 0.7)], 6, P["D"]),
        "face": {"eye": (144, 115, 6), "mouth": ("smile", 146, 156, 126), "cheek": (140, 124)},
    }


form("kolec", (156, 204, 86), (224, 242, 166), (114, 164, 62), (244, 124, 62), kolec)


def lobuz(P):
    return {
        "back": [tube([(86, 116), (90, 132), (86, 152)], 7, 5, P["F"]), ell(92, 155, 11, 5, P["F"])],
        "body": [
            tube([(52, 108), (26, 104), (4, 92)], 13, 2, P["B"]),
            ell(76, 104, 34, 20, P["B"], rot=-18),
            tube([(98, 94), (112, 72)], 12, 10, P["B"]),
            ell(124, 64, 25, 15, P["B"], rot=5),
            ell(74, 118, 14, 16, P["B"]),
            tube([(76, 126), (72, 152)], 7, 5, P["B"]),
            ell(78, 155, 12, 5, P["B"]),
            tube([(100, 96), (112, 108)], 4, 3, P["B"]),
            tube([(114, 50), (108, 40), (112, 32)], 4, 2, P["A"]),
            tube([(122, 50), (120, 38), (126, 32)], 4, 2, P["A"]),
        ],
        "detail": [ell(90, 108, 12, 16, P["L"], rot=-30), tube([(84, 154), (90, 150)], 2, 1, P["W"])]
        + spots([(70, 94, 1.0), (52, 102, 0.8), (34, 102, 0.6)], 5, P["D"]),
        "face": {"eye": (128, 58, 7), "mouth": ("jaw", 124, 148, 72), "cheek": (124, 70)},
    }


form("lobuz", (164, 116, 224), (222, 204, 250), (124, 84, 184), (250, 96, 126), lobuz)


# --- dorośli ---------------------------------------------------------------------
def rex(P):
    return {
        "back": [ell(86, 124, 18, 22, P["F"]), ell(90, 154, 18, 6, P["F"])],
        "body": [
            tube([(44, 118), (20, 136), (2, 128)], 20, 4, P["B"]),
            ell(68, 102, 40, 38, P["B"], rot=-25),
            tube([(88, 78), (104, 58)], 22, 20, P["B"]),
            ell(120, 44, 36, 24, P["B"], rot=-4),
            ell(124, 60, 32, 12, P["B"], rot=-4),
            ell(66, 124, 22, 24, P["B"]),
            ell(64, 154, 20, 7, P["B"]),
            tube([(102, 92), (114, 102)], 5, 4, P["B"]),
        ],
        "detail": [ell(90, 102, 16, 30, P["L"], rot=-28)]
        + spots([(54, 86, 1.0), (44, 104, 0.8), (70, 74, 0.7), (100, 34, 0.6)], 7, P["D"])
        + [poly([(52 + i * 12, 70 - i * 9), (58 + i * 12, 58 - i * 9), (64 + i * 12, 72 - i * 9)], P["A"]) for i in range(3)],
        "face": {"eye": (126, 34, 7.5), "mouth": ("jaw", 106, 154, 62), "cheek": (124, 50), "brow": True},
    }


form("rex", (76, 182, 96), (232, 232, 156), (48, 136, 74), (252, 212, 64), rex)


def szyjek(P):
    return {
        "back": [rrect(46, 128, 60, 158, 7, P["F"]), rrect(90, 128, 104, 158, 7, P["F"])],
        "body": [
            tube([(28, 124), (12, 134), (2, 144)], 12, 3, P["B"]),
            ell(64, 120, 44, 28, P["B"]),
            tube([(92, 108), (114, 70), (126, 28)], 15, 9, P["B"]),
            ell(136, 24, 19, 12, P["B"]),
            rrect(30, 126, 44, 158, 7, P["B"]),
            rrect(74, 126, 88, 158, 7, P["B"]),
        ],
        "detail": [ell(66, 136, 32, 8, P["L"]), tube([(98, 112), (116, 72), (124, 36)], 5, 3, P["L"])]
        + spots([(50, 106, 1.0), (72, 102, 0.9), (88, 112, 0.6), (112, 80, 0.5)], 6, P["D"]),
        "face": {"eye": (140, 19, 5.5), "mouth": ("smile", 142, 154, 30), "cheek": (138, 28)},
    }


form("szyjek", (122, 202, 222), (212, 240, 246), (82, 152, 182), (250, 200, 120), szyjek)


def ptero(P):
    wing = shade(P["B"], 0.85)
    return {
        "back": [
            poly([(78, 82), (14, 66), (24, 84), (36, 108), (80, 110)], wing),
            poly([(92, 82), (158, 74), (146, 92), (132, 112), (92, 110)], wing),
        ],
        "body": [
            tube([(80, 124), (76, 150)], 4, 3, P["B"]),
            tube([(92, 124), (96, 150)], 4, 3, P["B"]),
            ell(86, 100, 18, 28, P["B"]),
            ell(100, 58, 18, 15, P["B"]),
            poly([(86, 50), (64, 34), (92, 44)], P["A"]),
            poly([(110, 54), (154, 62), (110, 66)], P["A"]),
        ],
        "detail": [ell(88, 106, 11, 18, P["L"]), ell(74, 152, 7, 3, P["W"]), ell(98, 152, 7, 3, P["W"])]
        + [tube([(78, 84), (22, 70)], 1.5, 1, P["D"]), tube([(92, 84), (150, 77)], 1.5, 1, P["D"])],
        "face": {"eye": (104, 54, 6.5), "mouth": ("beak", 110, 152, 62), "cheek": (100, 64)},
    }


form("ptero", (236, 144, 84), (250, 214, 166), (194, 100, 58), (250, 226, 110), ptero)


def burczek(P):
    spikes = [poly([(x - 9, y + 8), (x, y - 10), (x + 9, y + 8)], P["A"]) for x, y in ((56, 70), (76, 60), (98, 60), (118, 68))]
    return {
        "back": spikes + [ell(110, 154, 18, 8, P["F"])],
        "body": [
            tube([(34, 124), (16, 134), (8, 126)], 12, 4, P["B"]),
            ell(84, 110, 58, 48, P["B"]),
            ell(62, 155, 18, 8, P["B"]),
            ell(134, 118, 8, 11, P["B"], rot=-25),
        ],
        "detail": [ell(92, 126, 40, 28, P["L"])] + spots([(52, 92, 1.0), (40, 112, 0.8), (64, 80, 0.7)], 7, P["D"]),
        "face": {"eye": (122, 88, 7.5), "mouth": ("smile", 124, 142, 112), "cheek": (118, 104), "brow": True, "grumpy": True},
    }


form("burczek", (152, 142, 174), (214, 208, 226), (112, 102, 134), (232, 124, 92), burczek)


# --- warianty: przeskalowane i przemalowane kształty ----------------------------
GROUND = (84, 158)


def _scale_shape(sh, k, ox, oy):
    from draw import Shape

    kw = dict(sh.kw)

    def P(x, y):
        return (ox + (x - ox) * k, oy + (y - oy) * k)

    if sh.kind == "ell":
        kw["cx"], kw["cy"] = P(kw["cx"], kw["cy"])
        kw["rx"] *= k
        kw["ry"] *= k
    elif sh.kind == "poly":
        kw["pts"] = [P(x, y) for x, y in kw["pts"]]
    elif sh.kind == "tube":
        kw["pts"] = [P(x, y) for x, y in kw["pts"]]
        kw["r0"] *= k
        kw["r1"] *= k
    elif sh.kind == "rrect":
        kw["x0"], kw["y0"] = P(kw["x0"], kw["y0"])
        kw["x1"], kw["y1"] = P(kw["x1"], kw["y1"])
        kw["r"] *= k
    return Shape(sh.kind, sh.color, **kw)


def scaled(build, k):
    """Ta sama postać w skali k; stopy zostają na ziemi (GROUND)."""
    ox, oy = GROUND

    def b(P):
        parts = build(P)
        out = {key: [_scale_shape(sh, k, ox, oy) for sh in parts[key]] for key in ("back", "body", "detail")}
        f = parts["face"]
        if f:
            def Pt(x, y):
                return (ox + (x - ox) * k, oy + (y - oy) * k)

            nf = dict(f)
            ex, ey, er = f["eye"]
            nf["eye"] = Pt(ex, ey) + (er * max(k, 0.85),)  # oczy maleją wolniej - młode mają duże oczy
            kind, x0, x1, y = f["mouth"]
            nx0, ny = Pt(x0, y)
            nx1, _ = Pt(x1, y)
            nf["mouth"] = (kind, nx0, nx1, ny)
            nf["cheek"] = Pt(*f["cheek"])
            out["face"] = nf
        else:
            out["face"] = None
        return out

    return b


# jajka pozostałych linii (ten sam kształt, inne kolory)
form("eggh", (206, 228, 250), (240, 248, 255), (84, 146, 228), (84, 146, 228), egg)
form("eggf", (255, 230, 196), (255, 246, 230), (240, 128, 64), (240, 128, 64), egg)

# drapieżniki: Allo - dorosły, dobra opieka (Rex w paski, rdzawy)
def allo(P):
    parts = rex(P)
    parts["detail"] = [d for d in parts["detail"] if d.kind != "poly"]  # bez złotych kolców
    parts["detail"] += [tube([(46 + i * 14, 84 - i * 8), (54 + i * 14, 104 - i * 8)], 3, 2, P["D"]) for i in range(4)]
    parts["detail"] += [tube([(108, 22), (116, 18), (124, 20)], 3, 2, P["A"])]  # grzebień nad okiem
    return parts


form("allo", (214, 120, 70), (246, 214, 170), (160, 80, 44), (250, 196, 90), allo)

# roślinożercy: Kropek (maluch), Rożek (młody Rogal)
form("kropek", (110, 176, 238), (214, 236, 252), (70, 128, 206), (255, 220, 110), pisklak)


form("rozek", (126, 196, 240), (214, 238, 252), (84, 146, 214), (250, 238, 200), scaled(rogal, 0.78))


# latające: Piórko (maluch ze skrzydełkami), Pterek (młody), Lotek (nastolatek), Mewa (dorosły)
def piorko(P):
    parts = pisklak(P)
    wing = mix(P["B"], P["A"], 0.45)
    parts["back"] = [ell(52, 76, 28, 12, wing, rot=-55), ell(42, 90, 22, 10, wing, rot=-30)] + parts["back"]
    parts["detail"] = [d for d in parts["detail"] if not (d.kind == "ell" and d.color == P["D"])]
    parts["detail"] += [poly([(96, 52), (86, 40), (102, 48)], P["A"])]
    return parts


form("piorko", (246, 160, 92), (252, 224, 186), (206, 112, 60), (255, 214, 96), piorko)
form("pterek", (240, 170, 104), (252, 226, 190), (200, 120, 70), (255, 222, 120), scaled(ptero, 0.74))
form("lotek", (96, 188, 196), (206, 238, 240), (60, 140, 152), (255, 206, 96), scaled(ptero, 0.88))
form("mewa", (226, 230, 238), (250, 252, 255), (150, 160, 180), (252, 196, 72), ptero)

# zaniedbany nastolatek: Mruk (mniejszy, bury Burczek)
form("mruk", (150, 124, 104), (210, 192, 176), (110, 90, 74), (200, 120, 80), scaled(burczek, 0.82))
