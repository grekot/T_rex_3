"""Ikony pixel art 12 x 12 (akcje, serca, kupa, czaszka...).

Znaki jak w forms.py: . przezroczyste, O obrys, pozostałe litery wg palety ikony.
"""

ICONS = {}


def icon(iid, palette, rows):
    rows = [r for r in rows.strip("\n").split("\n")]
    w = max(len(r) for r in rows)
    rows = [r.ljust(w, ".") for r in rows]
    ICONS[iid] = {"palette": palette, "rows": rows}


OUT = (18, 16, 22)

icon(
    "meal",
    {"O": OUT, "B": (205, 120, 60), "D": (160, 85, 40), "W": (245, 238, 220)},
    """
............
......OOOO..
.....OBBBBO.
....OBBBBDBO
....OBBBDDBO
...OBBBBDBO.
...OBBBDBO..
..OWOODOO...
.OWWO.OO....
OWWO........
.OO.........
............
""",
)

icon(
    "snack",
    {"O": OUT, "A": (250, 110, 160), "B": (255, 235, 240), "W": (240, 230, 210)},
    """
...OOOOO....
..OAABBAO...
.OABBAABBO..
.OBAAAABAO..
.OBABBAABO..
.OAABBAABO..
..OBAABAO...
...OOOOO....
.....OWO....
.....OWO....
.....OWO....
.....OOO....
""",
)

icon(
    "light",
    {"O": OUT, "A": (255, 214, 70), "W": (255, 250, 210), "B": (150, 150, 160)},
    """
....OOOO....
...OAAAAO...
..OAWWAAAO..
..OAWAAAAO..
..OAAAAAAO..
..OAAAAAAO..
...OAAAAO...
....OAAO....
....OBBO....
....OBBO....
.....OO.....
............
""",
)

icon(
    "play",
    {"O": OUT, "A": (240, 80, 70), "W": (250, 250, 250), "B": (70, 140, 240)},
    """
....OOOO....
..OOAAWWOO..
.OAAAAWWBBO.
.OAAAAWBBBO.
OWWWWAWBBBBO
OWWWWWWWWWWO
OBBBBWAAAAAO
OBBBBWAAAAAO
.OBBBWAAAAO.
.OBBWWAAAAO.
..OOWWAAOO..
....OOOO....
""",
)

icon(
    "medicine",
    {"O": OUT, "A": (235, 70, 80), "W": (250, 250, 250), "L": (255, 150, 150)},
    """
............
.......OOO..
......OALAO.
.....OAAAAAO
....OAAAAAO.
...OWWAAAO..
..OWWWWWO...
.OWWWWWO....
.OWWWWO.....
..OWWO......
...OO.......
............
""",
)

icon(
    "clean",
    {"O": OUT, "B": (170, 110, 60), "A": (250, 205, 80), "D": (210, 160, 50)},
    """
.........OO.
........OBO.
.......OBO..
......OBO...
.....OBO....
....OBO.....
..OOOOO.....
.OAAAAAO....
OAADAADAO...
OADAADAO....
.OAOAOO.....
..O.O.......
""",
)

icon(
    "scold",
    {"O": OUT, "W": (250, 250, 250), "A": (235, 60, 70)},
    """
.OOOOOOOOOO.
OWWWWAAWWWWO
OWWWWAAWWWWO
OWWWWAAWWWWO
OWWWWAAWWWWO
OWWWWWWWWWWO
OWWWWAAWWWWO
.OOWOOOOOOO.
..OWO.......
..OO........
............
............
""",
)

icon(
    "stats",
    {"O": OUT, "A": (90, 200, 120), "B": (255, 190, 60), "C": (90, 160, 240)},
    """
............
.........OOO
.........OCO
.........OCO
.....OOO.OCO
.....OBO.OCO
.....OBO.OCO
.OOO.OBO.OCO
.OAO.OBO.OCO
.OAO.OBO.OCO
.OOO.OOO.OOO
OOOOOOOOOOOO
""",
)

icon(
    "heart",
    {"O": OUT, "A": (240, 70, 90), "W": (255, 200, 210)},
    """
............
.OOO....OOO.
OAAAO..OAAAO
OAWAAOOAAAAO
OAWAAAAAAAAO
OAAAAAAAAAAO
.OAAAAAAAAO.
..OAAAAAAO..
...OAAAAO...
....OAAO....
.....OO.....
............
""",
)

icon(
    "heart_empty",
    {"O": (80, 76, 86), "A": (40, 38, 44), "W": (40, 38, 44)},
    ICONS["heart"]["rows"] and "\n".join(ICONS["heart"]["rows"]),
)

icon(
    "poop",
    {"O": OUT, "B": (150, 95, 50), "D": (115, 70, 35), "W": (190, 130, 75)},
    """
............
............
.....OO.....
....OBWO....
...OOBBBO...
..OBWBBDBO..
..OOOBBBDO..
.OBWBBBBBDO.
OBBBBBBBBBDO
OOOOOOOOOOOO
............
............
""",
)

icon(
    "skull",
    {"O": OUT, "W": (235, 235, 240), "K": (60, 55, 70)},
    """
...OOOOOO...
..OWWWWWWO..
.OWWWWWWWWO.
.OWKKWWKKWO.
.OWKKWWKKWO.
.OWWWWWWWWO.
..OWWKKWWO..
...OWWWWO...
...OWOWOWO..
....OOOOO...
............
............
""",
)

icon(
    "alert",
    {"O": OUT, "A": (255, 200, 40)},
    """
....OOOO....
....OAAO....
....OAAO....
....OAAO....
....OAAO....
....OAAO....
....OOOO....
............
....OOOO....
....OAAO....
....OOOO....
............
""",
)

icon(
    "arrow",  # w prawo, w lewo = odbicie
    {"O": OUT, "A": (255, 170, 40)},
    """
.....OO.....
.....OAO....
.....OAAO...
OOOOOOAAAO..
OAAAAAAAAAO.
OAAAAAAAAAAO
OAAAAAAAAAO.
OOOOOOAAAO..
.....OAAO...
.....OAO....
.....OO.....
............
""",
)

icon(
    "ball",
    {"O": OUT, "A": (240, 80, 70), "W": (250, 250, 250)},
    """
..OOOO..
.OAAWWO.
OAAAWWWO
OWWWAAAO
OWWWAAAO
OAAAWWWO
.OAAWWO.
..OOOO..
""",
)

icon(
    "lock",
    {"O": (70, 70, 80), "A": (110, 110, 125)},
    """
...OOOO...
..OAAAAO..
..OA..AO..
..OA..AO..
.OOOOOOOO.
.OAAAAAAO.
.OAAOOAAO.
.OAAOOAAO.
.OAAAAAAO.
.OOOOOOOO.
""",
)
