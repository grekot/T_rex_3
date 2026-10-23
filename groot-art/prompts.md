# Prompty dla Grok Imagine (grok.com/imagine, tryb „Obraz”, „Jakość”, proporcje 1:1)

Grafika to fan-art do prywatnego użytku (aplikacja tylko na własny zegarek, nie do sklepu).
Styl: realistyczny render 3D jak w filmie (użytkownik wybrał go zamiast kreskówki;
pierwsze kreskówkowe próby leżą w `_kreskowka/`).

Każdy arkusz zaczynaj od nowej strony grok.com/imagine (prompt w tej samej rozmowie traktuje
poprzednie obrazy jako punkt wyjścia). Grok z subskrypcją daje 4 warianty naraz. Skrypt w
przeglądarce zapisuje je w Pobranych jako `grootv_<nazwa>_<k>.jpg` (link z `download` do
obrazków `data:`, posortowanych od lewej). Potem w `groot/`:

```
python tools/grab_art.py <nazwa> --show   # warianty obok siebie -> groot-art/_warianty.png
python tools/grab_art.py <nazwa> <k>      # wybrany wariant -> groot-art/<nazwa>_sheet.jpg
python tools/import_art.py <nazwa>
python tools/preview_art.py <nazwa>       # podgląd w groot-art/_podglad.png
```

Bez subskrypcji Grok dał jeden obraz, potem tylko okno z planami.

## STYL (początek każdego promptu postaci)

Character sheet for a smartwatch game. Photorealistic 3D CGI render exactly like in the Marvel movie Guardians of the Galaxy, detailed realistic bark and wood texture, soft studio lighting, isolated on a pure solid white background. Show the SAME character 4 times in a 2x2 grid, same size and same position in each cell, three-quarter view facing RIGHT, full body: top-left calm neutral, top-right very happy laughing with open mouth, bottom-left sad with one tear, bottom-right sleeping with closed eyes. No text, no letters, no ground shadow, no frames.

## Postaci (dopisz po STYLU: "Character: ...")

Doniczka tylko na krótki początek, jak w filmach: patyczek na start i maluch (Kiełek, Pąk, Żołądź) -
tańczący patyczek z końca 1. części. Od dziecka (Baby Groot z 2. części) chodzi sam, bez doniczki.

Limit: tryb „Jakość” ma pulę zapytań w oknie 18 h (POST /rest/media/imagine/quota_info, `imagePro`);
po jej wyczerpaniu Grok po cichu nic nie zwraca - pomagają dokupione kredyty.

| forma | opis |
|---|---|
| kielek | tiny Twig Groot from the end of Guardians of the Galaxy (2014): a thin little brown twig with a tiny cute wooden face with small dark eyes, two thin twig arms and one tiny green leaf on top, standing in the soil of a small terracotta clay flower pot. |
| grocik | Baby Groot from Guardians of the Galaxy Vol. 2, about 10 inches tall, small brown bark body with a big head, big round dark eyes, a few small green leaves sprouting from his head, standing on his own two little feet, no flower pot. |
| nastek | Teen Groot from Avengers: Infinity War, slim lanky brown bark body, big dark eyes, small green leaves on his head, standing on his own feet, a bit moody teenage look. |
| groot | adult Groot from Guardians of the Galaxy (2014), tall strong broad-shouldered brown bark tree body, long arms, kind eyes, small green leaves and twigs on his head and shoulders, standing. |
| mszak | adult Groot-like tree creature, bulky stocky brown bark body covered with thick patches of green moss and a few small mushrooms, kind eyes, small green leaves on his head, standing. |
| pak | tiny Twig Groot-like sprout: a thin little light brown twig with a tiny cute wooden face with small dark eyes, two thin twig arms and one small pink flower bud on top, standing in the soil of a small pink ceramic flower pot. |
| kwiatus | a Baby Groot-like tree creature like in Guardians of the Galaxy Vol. 2, about 10 inches tall, small light brown bark body with a big head, big round dark eyes, small pink blossoms and green leaves sprouting from his head, standing on his own two little feet, no flower pot. |
| wisienka | a Teen Groot-like tree creature, slim lanky light brown bark body, big dark eyes, a cluster of pink cherry blossoms and two small red cherries on his head, standing on his own feet. |
| sakura | an adult Groot-like tree creature, tall strong light brown bark body, kind eyes, a big fluffy crown of pink cherry blossoms on his head and shoulders, standing. |
| jablon | an adult Groot-like tree creature, sturdy brown bark body, kind eyes, a crown of green leaves with several small red apples on his head and shoulders, standing. |
| zoladz | tiny Twig Groot-like sprout: a thin little brown twig with a tiny cute wooden face with small dark eyes, two thin twig arms, wearing a small acorn cap on its head with one tiny orange leaf, standing in the soil of a small orange ceramic flower pot. |
| rudzik | a Baby Groot-like tree creature like in Guardians of the Galaxy Vol. 2, about 10 inches tall, small reddish-brown bark body with a big head, big round dark eyes, small orange and red autumn maple leaves sprouting from his head, standing on his own two little feet, no flower pot. |
| klonik | a Teen Groot-like tree creature, slim lanky reddish-brown bark body, big dark eyes, a few red and orange maple leaves on his head, standing on his own feet. |
| klon | an adult Groot-like tree creature, tall strong reddish-brown bark body, kind eyes, a big crown of bright red and orange maple leaves on his head and shoulders, standing. |
| debisz | an adult Groot-like tree creature, stocky broad dark brown oak bark body, kind eyes, a crown of golden-brown oak leaves and acorns on his head and shoulders, standing. |
| suchar | a dried-out wilted Baby Groot-like tree creature like in Guardians of the Galaxy Vol. 2, about 10 inches tall, pale grey-brown cracked dry bark, a big head, droopy tired eyes, a few dry curled brown leaves on his head, standing on his own two little feet, no flower pot. |
| kolczak | a grumpy Teen Groot-like tree creature, twisted gnarled dark bark body covered with small sharp thorns, heavy grumpy brows, a few dark green holly leaves on his head, standing on his own feet. |
| prochniak | a grumpy old adult Groot-like tree creature, bulky grey rotten hollow bark with deep cracks, two bracket mushrooms growing on his side, heavy grumpy brows, no leaves, standing. |

## Zajęcia na ekranie głównym (arkusz `<forma>_act`)

Character sheet for a smartwatch game. Photorealistic 3D CGI render exactly like in the Marvel movie Guardians of the Galaxy, detailed realistic bark and wood texture, soft studio lighting, isolated on a pure solid white background. Show the SAME character 4 times in a 2x2 grid, same size in each cell, full body, facing RIGHT: top-left dancing happily with both arms up, top-right holding out an open hand with a small flower growing from the palm, bottom-left playing a handheld video game console, bottom-right surrounded by a few small glowing yellow firefly spores floating in the air. No text, no letters, no ground shadow, no frames, no grid lines. Character: ...

(opis postaci jak wyżej, bez końcowego "standing"; zaniedbanym: „dancing grumpily/clumsily”,
Sucharowi „a small wilted flower”)

## Doniczki na start (`pots`, jeden obraz, 3 doniczki obok siebie)

Three flower pots side by side in one row, evenly spaced with clear white gaps between them, photorealistic 3D CGI render like in the Marvel movie Guardians of the Galaxy, soft studio lighting, isolated on a pure solid white background, no ground shadow, no text: left a terracotta clay pot, middle a pink ceramic pot, right a bright orange ceramic pot. Each pot is filled with dark soil with one small bare brown wooden twig stick standing upright in it, like the tiny twig Groot was regrown from at the end of the movie, with no face. Same size, upright, front view.

## Rekwizyty gier (`props`, 4x4)

Game item sheet for a smartwatch game. Photorealistic 3D CGI render objects, soft studio lighting, isolated on a pure solid white background. A 4x4 grid of 16 separate items, each item centered in its own cell with plenty of empty white space around it, all items about the same visual size, nothing touching. Row 1: a shiny red apple with a leaf, a grey rock, a brown acorn with a cap, a blue fish facing right. Row 2: a small terracotta flower pot filled with soil, a yellow beehive, a red and white ball, a wooden log lying horizontally. Row 3: a round green fruit tree with red apples, a red balloon with a short string, a white pearl in an open pink seashell, a wooden treasure chest with gold. Row 4: a red flag on a short pole, a shiny golden star, a red and white fishing bobber, a small tree stump. No text, no letters, no numbers, no ground shadows, no frames, no grid lines.

Kolejność musi zostać (PROPS w import_art.py; żołądź trafia do `bone*` i `egg_small`, doniczka do `nest`).

## Ikony akcji (`icons`, 2 rzędy po 4)

Game icon sheet for a smartwatch game. Photorealistic 3D CGI render objects, soft studio lighting, isolated on a pure solid white background. 8 separate items in 2 rows of 4, each centered with plenty of empty white space around it, all about the same visual size, nothing touching. Row 1: a green metal watering can, a small burlap sack of plant fertilizer, a glowing yellow crescent moon, a green plastic garden spray bottle. Row 2: a garden rake, a fallen orange autumn leaf, a small green aphid bug, a clear blue water drop. No text, no letters, no ground shadows, no frames, no grid lines.

Kolejność musi zostać (ICONS w import_art.py: konewka, nawóz, księżyc, oprysk, grabie,
opadły liść = `poop`, mszyca = `skull`, kropla = `drop`/`meal`).
