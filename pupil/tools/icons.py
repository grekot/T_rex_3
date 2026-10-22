"""Gładkie ikony: każda funkcja rysuje na płótnie 48 x 48 px (układ projektu) i zwraca
listę (kształty z obrysem, detale). Obrys ciemny, jak przy postaciach."""
from draw import ell, poly, tube, rrect

OUT = (24, 20, 30)
W = (252, 250, 244)


def meal():
    meat = (206, 122, 62)
    return [tube([(12, 38), (20, 30)], 4, 4, W), ell(8, 40, 4.5, 4.5, W), ell(13, 43, 4.5, 4.5, W), ell(28, 20, 15, 12, meat, rot=-40)], [
        ell(23, 16, 5, 3, (232, 160, 100), rot=-40)
    ]


def snack():
    pink = (250, 112, 164)
    return [rrect(22, 24, 26, 46, 2, W), ell(24, 17, 14, 14, pink)], [
        tube([(14, 17), (18, 10), (26, 9), (31, 14), (28, 21), (22, 21), (20, 16), (24, 14)], 2.2, 2.2, W, n=60)
    ]


def light():
    yellow = (255, 214, 72)
    grey = (150, 152, 164)
    return [ell(24, 19, 14, 15, yellow), rrect(18, 30, 30, 42, 3, grey)], [
        ell(19, 14, 4, 6, (255, 246, 200), rot=20),
        rrect(18, 34, 30, 35.5, 1, (110, 112, 124)),
        rrect(18, 38, 30, 39.5, 1, (110, 112, 124)),
    ]


def play():
    red = (240, 82, 72)
    blue = (70, 140, 240)
    return [ell(24, 24, 19, 19, W)], [
        poly([(24, 24), (24, 5), (11, 10)], red),
        poly([(24, 24), (43, 24), (40, 12)], blue),
        poly([(24, 24), (24, 43), (37, 38)], red),
        poly([(24, 24), (5, 24), (8, 36)], blue),
        ell(24, 24, 3, 3, (250, 220, 80)),
    ]


def medicine():
    red = (236, 72, 84)
    return [tube([(14, 34), (34, 14)], 9, 9, red)], [
        tube([(14, 34), (24, 24)], 9, 9, W),
        ell(30, 16, 3, 2, (255, 170, 170), rot=-45),
    ]


def clean():
    wood = (176, 114, 64)
    straw = (250, 206, 84)
    return [tube([(40, 6), (24, 26)], 2.6, 2.6, wood), poly([(18, 22), (30, 30), (22, 44), (6, 38)], straw)], [
        tube([(14, 30), (10, 40)], 1, 1, (210, 160, 50)),
        tube([(20, 32), (16, 42)], 1, 1, (210, 160, 50)),
        rrect(15, 22, 31, 27, 2, (220, 90, 70)),
    ]


def scold():
    red = (236, 62, 72)
    return [rrect(5, 6, 43, 34, 9, W), poly([(12, 30), (12, 44), (24, 32)], W)], [
        rrect(21.5, 10, 26.5, 24, 2.5, red),
        ell(24, 29, 2.8, 2.8, red),
    ]


def stats():
    return [rrect(6, 28, 15, 42, 2, (96, 206, 128)), rrect(19.5, 18, 28.5, 42, 2, (255, 192, 64)), rrect(33, 8, 42, 42, 2, (96, 164, 244))], []


def heart(color=(240, 72, 92)):
    return [ell(16, 18, 10, 10, color), ell(32, 18, 10, 10, color), poly([(7, 22), (24, 42), (41, 22), (24, 16)], color)], [
        ell(13, 15, 3, 4, (255, 200, 210), rot=30)
    ]


def heart_empty():
    shapes, _ = heart((52, 50, 60))
    return shapes, []


def poop():
    brown = (156, 98, 52)
    return [ell(24, 38, 18, 7, brown), ell(24, 29, 13, 6, brown), ell(24, 21, 8, 5, brown), tube([(24, 17), (28, 10), (24, 8)], 3, 1.5, brown)], [
        ell(18, 36, 3, 1.5, (196, 138, 86)),
        ell(20, 27, 2.5, 1.2, (196, 138, 86)),
    ]


def skull():
    k = (64, 58, 76)
    return [ell(24, 21, 16, 15, W), rrect(15, 28, 33, 41, 4, W)], [
        ell(18, 22, 4.5, 5, k),
        ell(30, 22, 4.5, 5, k),
        poly([(24, 27), (21.5, 32), (26.5, 32)], k),
        rrect(19, 36, 21, 41, 1, k),
        rrect(23, 36, 25, 41, 1, k),
        rrect(27, 36, 29, 41, 1, k),
    ]


def alert():
    y = (255, 202, 40)
    return [rrect(19, 4, 29, 32, 5, y), ell(24, 40, 5.5, 5.5, y)], []


def arrow():
    o = (255, 172, 40)
    return [poly([(6, 18), (26, 18), (26, 8), (44, 24), (26, 40), (26, 30), (6, 30)], o)], []


def ball():
    shapes, det = play()
    return shapes, det


ICONS = {
    "meal": meal,
    "snack": snack,
    "light": light,
    "play": play,
    "medicine": medicine,
    "clean": clean,
    "scold": scold,
    "stats": stats,
    "heart": heart,
    "heart_empty": heart_empty,
    "poop": poop,
    "skull": skull,
    "alert": alert,
    "arrow": arrow,
    "ball": ball,
}
