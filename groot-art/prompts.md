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

## Rekwizyty gier (`props`, 4x4, motyw Strażników Galaktyki)

Game item sheet for a smartwatch game. Photorealistic 3D CGI render objects in the style of the Marvel movie Guardians of the Galaxy, soft studio lighting, isolated on a pure solid white background. A 4x4 grid of 16 separate items, each item centered in its own cell with plenty of empty white space around it, all items about the same visual size, nothing touching. Row 1: a shiny metal spaceship engine part gear with bolts, a grey cratered asteroid rock, a red metal head fin implant like Yondu's, a glowing blue alien fish facing right. Row 2: a glowing round spaceship landing pad seen from above, a yellow beehive, the Orb (a small silver metal sphere with a golden band), a long metal spaceship girder lying horizontally. Row 3: a round green fruit tree with red apples, a glowing blue energy sphere, a glowing purple Infinity Stone gem, a small orange and blue Milano spaceship seen from above facing right. Row 4: a small signal beacon with a red light on a short pole, a shiny golden star, a red and white fishing bobber, a broken metal cargo crate. No text, no letters, no numbers, no ground shadows, no frames, no grid lines.

Kolejność musi zostać (PROPS w import_art.py; nazwy plików zostały z Pupila: rock = asteroida,
bone_big = płetwa, nest = lądowisko, ball/orb = Orb, log = belka, balloon = kula energii,
pearl = kamień, egg_small = Milano, flag/beacon = nadajnik, stump = skrzynia).

## Ikony 2 (`icons2`, 2 rzędy po 3)

Game icon sheet for a smartwatch game. Photorealistic 3D CGI render objects in the style of the Marvel movie Guardians of the Galaxy, soft studio lighting, isolated on a pure solid white background. 6 separate items in 2 rows of 3, each centered with plenty of empty white space around it, all about the same visual size, nothing touching. Row 1: a bright glowing yellow star sun with rays, a pink and white ice cream cone with a waffle, a shiny red apple with a leaf. Row 2: a retro orange and silver cassette walkman with orange headphones, a glowing red arrow like Yondu's yaka arrow pointing right, a round black bomb with a glowing red button on top. No text, no letters, no ground shadows, no frames, no grid lines.

Słońce i lody to karmienie od etapu dziecka, jabłko spada w grze z drzewem.

## Rocket (`rocket`, rywal w Wyścigu z Rocketem)

Photorealistic 3D CGI render exactly like in the Marvel movie Guardians of the Galaxy: Rocket Raccoon running fast to the right, full body, side view, in his orange flight suit, determined grin, isolated on a pure solid white background, no ground shadow, no text.

## Tła ekranu głównego (`bg_<scena>`, jedno ujęcie 1:1)

Początek każdego: "Background art for a round smartwatch game screen. Photorealistic 3D CGI render exactly like in the Marvel movie Guardians of the Galaxy." Koniec: "Empty scene, no characters, no people, no plants, no text. Centered square composition, eye level view." Podłoga albo blat w dolnej jednej trzeciej (tam stoi Groot). Import przyciemnia (BG_DAY, BG_NIGHT, winieta).

| scena | etap | opis |
|---|---|---|
| kokpit | patyczek, maluch | Interior of the Milano spaceship cockpit: a flat metal console shelf runs across the lower third of the picture, a big cockpit window behind it shows stars and a colorful nebula, soft blue and orange control lights. |
| poklad | dziecko | Inside the Milano spaceship: a metal deck floor in the lower third of the picture, walls with pipes, cables, small blue and orange lights and hanging cargo nets, a round porthole with stars. |
| kacik | nastolatek | A messy teenager's corner inside a spaceship: metal floor in the lower third of the picture, an old arcade-style video game console with a glowing screen against the wall, scattered blankets, a cassette tape walkman, posters, cables and small neon lights, a small porthole with stars. |
| knowhere | dorosły | Knowhere, the mining colony inside a giant severed celestial head floating in space: a rocky ground with metal walkways in the lower third of the picture, colorful neon shop lights, the huge ancient skull rising behind, stars and nebula in the sky. |
| ladownia | zaniedbane | A dark dusty neglected cargo hold of an old spaceship: dirty metal floor in the lower third of the picture, rusty crates, broken flickering lamp, cobwebs, a cracked porthole with dim stars, gloomy grey-green light. |

## Ikony akcji (`icons`, 2 rzędy po 4)

Game icon sheet for a smartwatch game. Photorealistic 3D CGI render objects, soft studio lighting, isolated on a pure solid white background. 8 separate items in 2 rows of 4, each centered with plenty of empty white space around it, all about the same visual size, nothing touching. Row 1: a green metal watering can, a small burlap sack of plant fertilizer, a glowing yellow crescent moon, a green plastic garden spray bottle. Row 2: a garden rake, a fallen orange autumn leaf, a small green aphid bug, a clear blue water drop. No text, no letters, no ground shadows, no frames, no grid lines.

Kolejność musi zostać (ICONS w import_art.py: konewka, nawóz, księżyc, oprysk, grabie,
opadły liść = `poop`, mszyca = `skull`, kropla = `drop`/`meal`).

## Planety podróży Milano i statek Ravagerów (Gemini, 23.10.2026)

Kredyty Groka się skończyły, a planety i statek to nie postacie – zrobione w Gemini („Generate an image
(square 1:1): …”, opis bez nazw z filmu). Chrome przestał zapisywać pobrania – obejście: przycisk
„Kopiuj obraz” w Gemini (prawdziwe kliknięcie) i `python tools/grab_art.py <nazwa> --clip`.
Wysyłanie promptu: `insertText` do `rich-textarea .ql-editor`, potem klik `button[aria-label*="Wyślij"]`
(Enter bywa ignorowany).

Początek: "Background art for a smartwatch game screen, photorealistic 3D CGI render like a Marvel space movie." Koniec: "Empty scene, no characters, no people, no text. Centered square composition, eye level view."

| plik | planeta | opis |
|---|---|---|
| bg_xandar | Xandar | A gleaming futuristic alien capital city on a distant planet: white and gold round towers and domes, a plaza with smooth stone ground in the lower third of the picture, blue sky with a big ringed planet. |
| bg_contraxia | Contraxia | A snowy icy alien pleasure planet at night: frozen ground with snow in the lower third of the picture, glowing pink, purple and blue neon buildings and signs in the distance, falling snow, dark starry sky. |
| bg_berhert | Berhert | A dense green alien forest planet: a mossy clearing in the lower third of the picture, giant strange trees with glowing blue fungi, a crashed small orange and blue spaceship half hidden among the trees, soft misty daylight. |
| bg_ego | planeta Ego | A colorful living fantasy planet: a garden path of smooth pale stone in the lower third of the picture, giant pastel flowers and fractal golden spires, a shining golden palace in the distance, floating glowing bubbles, rainbow pink and teal sky. |
| bg_nidavellir | Nidavellir | A colossal ancient dwarf star forge in deep space: a dark metal platform in the lower third of the picture, a gigantic ring structure around a dying glowing star behind it, molten sparks and orange forge light, starry black space. |
| ravager | statek | Photorealistic 3D CGI render like a Marvel space movie: one small rusty red and dark grey space pirate starfighter with angular wings and glowing orange engines, seen from the front and slightly above, isolated on a pure solid white background, no ground shadow, no text, the ship fills the center of the picture. |

Knowhere używa tła `bg_knowhere` (dorosły).
