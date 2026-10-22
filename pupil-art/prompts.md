# Prompty dla Gemini (Utwórz obraz)

Każdą formę generuj **w nowej rozmowie** (w tej samej rozmowie Gemini kopiuje poprzednią
postać). Wklej STYL + opis postaci. Pobrany obraz zapisz w Pobranych, potem w `pupil/`:

```
python tools/grab_gemini.py <forma>
python tools/import_art.py <forma>
python tools/preview_art.py <forma>   # podgląd w pupil-art/_podglad.png
```

Arkusze leżą tu, poza `pupil/`, bo `zeus build` pakuje cały folder aplikacji do `.ip-package`.

Wskazówki: zaznacz narzędzie „Utwórz obraz” (bez niego Gemini często odpisuje, że nie umie
generować obrazów; wtedy w tej samej rozmowie „Generate this image now using the image
generation tool.”). Minę obróconą w lewo import_art.py sam odwraca; formom z długim ogonem
lub szerokimi skrzydłami wpisz w TAIL_KEEP, żeby nie obcinać ich w kadrze.

Gotowe: wszystkie 18 form i jajka (eggs).

## STYL (początek każdego promptu)

Character sheet for a smartwatch tamagotchi game. Flat vector cartoon sticker style, thick dark outline, simple soft cel shading, pure solid white background. Show the SAME character 4 times in a 2x2 grid, same size and same position in each cell, side view facing RIGHT, full body: top-left calm neutral, top-right very happy laughing with open mouth and pink blush, bottom-left sad with one tear, bottom-right sleeping with closed eyes. No text, no letters, no zZ, no ground shadow, no frames.

## Postaci (dopisz po STYLU: "Character: ...")

| forma | opis |
|---|---|
| lobuz | a cute chibi teenage velociraptor, slim purple body leaning slightly forward, pale lavender belly, a few darker purple spots, a small crest of bright pink feathers on the head, long thin tail, small clawed arms, long legs, cheeky mischievous look, small pointy teeth. |
| rex | a cute chibi adult Tyrannosaurus rex, big chunky green body, pale yellow belly, darker green spots, a row of small golden spikes along the back, big head with a confident smile and small teeth, tiny arms, strong legs, thick tail. |
| allo | a cute chibi adult Allosaurus, rusty orange-brown body with darker brown stripes on the back, cream belly, two small bony ridges above the eyes, big head, tiny arms, strong legs, long tail. |
| kropek | a tiny newborn baby dinosaur hatchling, very round chubby egg-shaped body with no neck, light blue skin with darker blue spots, pale blue belly, very big round eyes, tiny stubby feet, short stubby tail, a small piece of white eggshell on its head. |
| rozek | a cute chibi child triceratops, small chubby light blue body on four short legs, pale belly, a small rounded frill, three tiny stubby ivory horns, big eyes, short tail. |
| rogal | a cute chibi teenage triceratops, blue body on four sturdy legs, pale blue belly, a big frill with a darker blue edge and white dots, two ivory brow horns and a small nose horn, short tail. |
| szyjek | a cute chibi adult Brachiosaurus, long neck, light teal-blue body on four sturdy pillar legs, pale belly, darker blue spots on the back, small head with a gentle smile, short tail. |
| kolec | a cute chibi adult Stegosaurus, lime green body on four legs, pale yellow belly, a row of rounded orange plates along the back, small head held low, spiky tail with white spikes. |
| piorko | a tiny newborn baby pterosaur hatchling, very round chubby body, orange skin, cream belly, two tiny wings, a small yellow beak and a little yellow crest, very big eyes, a small piece of white eggshell on its head. |
| pterek | a cute chibi child pterosaur standing on two legs, small orange body, cream belly, small wings half open, short yellow beak, small crest, big eyes. |
| lotek | a cute chibi teenage pterosaur standing on two legs, turquoise teal body, pale belly, medium wings partly spread, yellow beak, yellow crest. |
| ptero | a cute chibi adult Pteranodon standing on two legs, orange body, cream belly, big brown membrane wings spread wide, long pointed yellow beak, long crest pointing back. |
| mewa | a cute chibi adult pterosaur standing on two legs, white and light grey body like a seagull, grey wings spread, yellow beak, small grey crest. |
| gapcio | a clumsy chubby child dinosaur, orange round potato-shaped body, cream belly, a small tuft of brown hair on top of its head, short arms, short legs, small tail, slightly sleepy goofy look. |
| mruk | a grumpy chubby teenage dinosaur, round greyish-brown body, light belly, a row of small orange spikes on the back, heavy grumpy eyebrows, short legs, short tail. |
| burczek | a grumpy fat adult dinosaur, big round lavender-grey body, pale belly, a row of coral orange spikes on the back, heavy grumpy eyebrows, short stubby legs, short tail. |

## Jajka (jeden obraz, 3 jajka obok siebie)

Zapisz jako `eggs` (`python tools/grab_gemini.py eggs`, `python tools/import_art.py eggs`).

Three cute cartoon dinosaur eggs side by side in one row, flat vector sticker style, thick dark outline, soft cel shading, pure solid white background, no text: left a cream egg with green spots, middle a light blue egg with darker blue spots, right a peach egg with orange spots. Same size, upright.
