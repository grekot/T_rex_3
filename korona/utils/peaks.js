// Korona Gór Polski - 28 szczytów według listy Klubu Zdobywców KGP (stan 2026, bez zmian od 1997/98)
// + kilka wariantów (inne wierzchołki tego samego pasma), które aplikacja też rozpoznaje.
//
// Wysokości: z listy KGP (Wikipedia „Korona Gór Polski”).
// Współrzędne: węzeł natural=peak z OpenStreetMap (osm = id węzła, © współtwórcy OpenStreetMap, ODbL),
// pobrane 2026-10-20 przez Overpass API i Nominatim. Szczegóły w README.
//
// Pola: id, name, h (m n.p.m.), range (pasmo), lat, lon, osm, border (wierzchołek graniczny),
// variantOf (tylko warianty: id szczytu z listy, którego pasmo reprezentują), note.

export const LIST_NAME = "Korona Gór Polski";
export const LIST_SHORT = "KGP";

export const PEAKS = [
  { id: "rysy", name: "Rysy", h: 2499, range: "Tatry", lat: 49.1795756, lon: 20.0881081, osm: 4366169405, border: true },
  { id: "babia", name: "Babia Góra", h: 1725, range: "Beskid Żywiecki", lat: 49.5730231, lon: 19.5293303, osm: 477984782, border: true, note: "Wierzchołek Diablak" },
  { id: "sniezka", name: "Śnieżka", h: 1603, range: "Karkonosze", lat: 50.7360326, lon: 15.7396072, osm: 1850303773, border: true },
  { id: "snieznik", name: "Śnieżnik", h: 1423, range: "Masyw Śnieżnika", lat: 50.2074081, lon: 16.847424, osm: 26863429, border: true },
  { id: "tarnica", name: "Tarnica", h: 1346, range: "Bieszczady", lat: 49.0747705, lon: 22.726323, osm: 1347929065 },
  { id: "turbacz", name: "Turbacz", h: 1310, range: "Gorce", lat: 49.5428239, lon: 20.1113839, osm: 26864983 },
  { id: "radziejowa", name: "Radziejowa", h: 1266, range: "Beskid Sądecki", lat: 49.4493044, lon: 20.6041221, osm: 1198299196 },
  { id: "skrzyczne", name: "Skrzyczne", h: 1257, range: "Beskid Śląski", lat: 49.6845736, lon: 19.0302741, osm: 26864701 },
  { id: "mogielica", name: "Mogielica", h: 1171, range: "Beskid Wyspowy", lat: 49.6553199, lon: 20.2766736, osm: 1236685520 },
  { id: "wysokakopa", name: "Wysoka Kopa", h: 1126, range: "Góry Izerskie", lat: 50.85, lon: 15.4202778, osm: 707906070 },
  { id: "rudawiec", name: "Rudawiec", h: 1106, range: "Góry Bialskie", lat: 50.2448039, lon: 16.9768585, osm: 1793427200, border: true },
  { id: "orlica", name: "Orlica", h: 1084, range: "Góry Orlickie", lat: 50.3532494, lon: 16.3606287, osm: 2418877544, border: true },
  { id: "wysoka", name: "Wysoka", h: 1050, range: "Pieniny", lat: 49.3802606, lon: 20.5555018, osm: 615627232, border: true, note: "Wysokie Skałki" },
  { id: "wielkasowa", name: "Wielka Sowa", h: 1015, range: "Góry Sowie", lat: 50.6802778, lon: 16.4855556, osm: 458891184 },
  { id: "lackowa", name: "Lackowa", h: 997, range: "Beskid Niski", lat: 49.4265468, lon: 21.1024789, osm: 4366115862, border: true },
  { id: "kowadlo", name: "Kowadło", h: 989, range: "Góry Złote", lat: 50.2644312, lon: 17.0132176, osm: 2421373077, border: true },
  { id: "jagodna", name: "Jagodna", h: 977, range: "Góry Bystrzyckie", lat: 50.2524573, lon: 16.5644186, osm: 2418865417 },
  { id: "skalnik", name: "Skalnik", h: 945, range: "Rudawy Janowickie", lat: 50.8084793, lon: 15.9000581, osm: 1219704819 },
  { id: "waligora", name: "Waligóra", h: 936, range: "Góry Kamienne", lat: 50.6808246, lon: 16.2780881, osm: 2470310941 },
  { id: "czupel", name: "Czupel", h: 931, range: "Beskid Mały", lat: 49.767881, lon: 19.1610286, osm: 3046822323 },
  { id: "szczeliniec", name: "Szczeliniec Wielki", h: 919, range: "Góry Stołowe", lat: 50.4848143, lon: 16.3410065, osm: 492775426 },
  { id: "lubomir", name: "Lubomir", h: 904, range: "Beskid Makowski", lat: 49.7668805, lon: 20.0596718, osm: 2845608415 },
  { id: "biskupia", name: "Biskupia Kopa", h: 889, range: "Góry Opawskie", lat: 50.2566949, lon: 17.4285752, osm: 991934327, border: true },
  { id: "chelmiec", name: "Chełmiec", h: 850, range: "Góry Wałbrzyskie", lat: 50.7795495, lon: 16.2109745, osm: 428725380 },
  { id: "klodzka", name: "Kłodzka Góra", h: 765, range: "Góry Bardzkie", lat: 50.45167, lon: 16.7532205, osm: 529512640 },
  { id: "skopiec", name: "Skopiec", h: 724, range: "Góry Kaczawskie", lat: 50.9439267, lon: 15.8847061, osm: 4593556759 },
  { id: "sleza", name: "Ślęża", h: 718, range: "Masyw Ślęży", lat: 50.8640875, lon: 16.7074963, osm: 349062696 },
  { id: "lysica", name: "Łysica", h: 614, range: "Góry Świętokrzyskie", lat: 50.8916162, lon: 20.8965979, osm: 1844240120 },

  // Warianty - nie liczą się do 28, ale aplikacja je rozpoznaje i zapisuje
  { id: "borowa", name: "Borowa", h: 853, range: "Góry Wałbrzyskie", lat: 50.7228665, lon: 16.3044645, osm: 2479069436, variantOf: "chelmiec", note: "Faktycznie najwyższa w Górach Wałbrzyskich" },
  { id: "szeroka", name: "Szeroka Góra", h: 766, range: "Góry Bardzkie", lat: 50.4536637, lon: 16.7584602, osm: 1997912845, variantOf: "klodzka", note: "Wg nowych pomiarów wyższa od Kłodzkiej Góry" },
  { id: "okole", name: "Okole", h: 725, range: "Góry Kaczawskie", lat: 50.9807356, lon: 15.8179415, osm: 2090686556, variantOf: "skopiec", note: "Wg pomiarów z 2021 r. wyższe od Skopca" },
  { id: "agata", name: "Agata", h: 614, range: "Góry Świętokrzyskie", lat: 50.8890736, lon: 20.905947, osm: 1844339192, variantOf: "lysica", note: "Wschodni, najwyższy wierzchołek Łysicy" },
  { id: "postawna", name: "Postawna", h: 1117, range: "Góry Złote", lat: 50.2217821, lon: 17.0111503, osm: 1890147175, variantOf: "rudawiec", note: "Na pierwszej liście z 1997 r." },
  { id: "trzykorony", name: "Trzy Korony", h: 982, range: "Pieniny", lat: 49.4138332, lon: 20.4142155, osm: 253737989, variantOf: "wysoka", note: "Na pierwszej liście z 1997 r." },
];

export const OFFICIAL = PEAKS.filter((p) => !p.variantOf);
export const VARIANTS = PEAKS.filter((p) => p.variantOf);

export function findPeak(id) {
  for (let i = 0; i < PEAKS.length; i++) if (PEAKS[i].id === id) return PEAKS[i];
  return null;
}
