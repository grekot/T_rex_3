import { L } from "./layout";

// Grafika i współrzędne pochodzą z tools/gen_assets.py (layout.js jest generowany).
// Wszystkie widżety niżej odświeża system - tarcza nie ma własnych timerów.
// Tarcza używa globalnego hmUI z API 1.0 (app.json: apiVersion 1.0.0); przy API 3.0
// tego obiektu nie ma i zegarek pokazuje czarny ekran.

function imgs(dir, n, first = 0) {
  const out = [];
  for (let i = 0; i < n; i++) out.push(`${dir}/${i + first}.png`);
  return out;
}

const BIG = imgs("big", 10);
const MED = imgs("med", 10);
const SMALL = imgs("small", 10);
const TINY = imgs("tiny", 10);
const LARGE = imgs("large", 10);
const ROW2 = imgs("row2", 10);
const WEEK = imgs("week", 7, 1);
const AOD_BIG = imgs("aod/big", 10);
const AOD_MED = imgs("aod/med", 10);
const AOD_WEEK = imgs("aod/week", 7, 1);

// Jeden nieobsługiwany widżet lub typ danych nie może zgasić całej tarczy.
function make(widget, opts) {
  const id = hmUI.widget[widget];
  if (id === undefined) {
    console.log(`retro-lcd: brak widzetu ${widget}`);
    return null;
  }
  try {
    return hmUI.createWidget(id, opts);
  } catch (e) {
    console.log(`retro-lcd: ${widget} ${e}`);
    return null;
  }
}

function dataType(name) {
  const t = hmUI.data_type[name];
  if (t === undefined) console.log(`retro-lcd: brak data_type ${name}`);
  return t;
}

function buildTime(showLevel, digits, withSeconds) {
  const t = L.time;
  const opts = {
    hour_zero: 1,
    hour_startX: t.hourX,
    hour_startY: t.y,
    hour_array: digits,
    hour_space: t.space,
    hour_align: hmUI.align.LEFT,
    minute_zero: 1,
    minute_startX: t.minuteX,
    minute_startY: t.y,
    minute_array: digits,
    minute_space: t.space,
    minute_align: hmUI.align.LEFT,
    minute_follow: 0,
    show_level: showLevel,
  };
  if (withSeconds) {
    Object.assign(opts, {
      second_zero: 1,
      second_startX: t.secondX,
      second_startY: t.secondY,
      second_array: MED,
      second_space: t.secondSpace,
      second_align: hmUI.align.LEFT,
      second_follow: 0,
      am_x: t.ampmX,
      am_y: t.ampmY,
      am_sc_path: "time/am.png",
      am_tc_path: "time/am.png",
      am_en_path: "time/am.png",
      pm_x: t.ampmX,
      pm_y: t.ampmY,
      pm_sc_path: "time/pm.png",
      pm_tc_path: "time/pm.png",
      pm_en_path: "time/pm.png",
    });
  }
  make("IMG_TIME", opts);
}

function buildDate(showLevel, week, digits) {
  make("IMG_WEEK", {
    x: L.week.x,
    y: L.week.y,
    week_en: week,
    week_tc: week,
    week_sc: week,
    show_level: showLevel,
  });
  make("IMG_DATE", {
    day_startX: L.date.x,
    day_startY: L.date.y,
    day_zero: 1,
    day_space: L.date.space,
    day_align: hmUI.align.LEFT,
    day_follow: 0,
    day_en_array: digits,
    day_sc_array: digits,
    day_tc_array: digits,
    show_level: showLevel,
  });
}

function textImg(box, typeName, font, space, extra) {
  const type = dataType(typeName);
  if (type === undefined) return;
  make(
    "TEXT_IMG",
    Object.assign(
      {
        x: box.x,
        y: box.y,
        w: box.w,
        h: box.h,
        type,
        font_array: font,
        h_space: space,
        align_h: hmUI.align.RIGHT,
        show_level: hmUI.show_level.ONLY_NORMAL,
      },
      extra || {},
    ),
  );
}

function imgLevel(pos, typeName, images) {
  const type = dataType(typeName);
  if (type === undefined) return;
  make("IMG_LEVEL", {
    x: pos.x,
    y: pos.y,
    image_array: images,
    image_length: images.length,
    type,
    show_level: hmUI.show_level.ONLY_NORMAL,
  });
}

function click(box, typeName) {
  const type = dataType(typeName);
  if (type === undefined) return;
  make("IMG_CLICK", {
    x: box.x,
    y: box.y,
    w: box.w,
    h: box.h,
    src: "click.png",
    type,
    show_level: hmUI.show_level.ONLY_NORMAL,
  });
}

function buildNormal() {
  const NORMAL = hmUI.show_level.ONLY_NORMAL;
  const sp = L.space;

  make("IMG", { x: 0, y: 0, w: 480, h: 480, src: "bg.png", show_level: NORMAL });

  buildTime(NORMAL, BIG, true);
  buildDate(NORMAL, WEEK, MED);

  const st = L.status;
  const status = [
    [st.bell, "CLOCK", "status/bell.png"],
    [st.bt, "DISCONNECT", "status/bt.png"],
    [st.dnd, "DISTURB", "status/dnd.png"],
  ];
  for (const [pos, name, src] of status) {
    const type = hmUI.system_status[name];
    if (type !== undefined) make("IMG_STATUS", { x: pos.x, y: pos.y, type, src, show_level: NORMAL });
  }

  // Kroki + pasek celu
  textImg(L.steps.text, "STEP", SMALL, sp.small);
  imgLevel(L.steps.bar, "STEP", imgs("bar", 11));

  // Tętno + kalorie
  textImg(L.heart.text, "HEART", SMALL, sp.small, { invalid_image: "small/none.png" });
  textImg(L.cal.text, "CAL", TINY, sp.tiny);

  // Pogoda: ikona, temperatura, max / min
  const w = L.weather;
  imgLevel(w.icon, "WEATHER_CURRENT", imgs("weather", 29));
  const tempExtra = {
    negative_image: "large/minus.png",
    invalid_image: "large/none.png",
    unit_sc: "large/unit_c.png",
    unit_tc: "large/unit_c.png",
    unit_en: "large/unit_c.png",
    imperial_unit_sc: "large/unit_f.png",
    imperial_unit_tc: "large/unit_f.png",
    imperial_unit_en: "large/unit_f.png",
  };
  textImg(w.temp, "WEATHER_CURRENT", LARGE, sp.large, tempExtra);
  // max / min stoją tuż za nadrukowanymi strzałkami ▲ ▼, więc wyrównanie do lewej
  const tinyTemp = {
    negative_image: "row2/minus.png",
    invalid_image: "row2/none.png",
    align_h: hmUI.align.LEFT,
  };
  textImg(w.hi, "WEATHER_HIGH", ROW2, sp.row2, tinyTemp);
  textImg(w.lo, "WEATHER_LOW", ROW2, sp.row2, tinyTemp);

  // Wysokość n.p.m. + ciśnienie (barometr)
  const m = "large/unit_m.png";
  const ft = "large/unit_ft.png";
  textImg(L.altitude.text, "ALTITUDE", LARGE, sp.large, {
    unit_sc: m,
    unit_tc: m,
    unit_en: m,
    imperial_unit_sc: ft,
    imperial_unit_tc: ft,
    imperial_unit_en: ft,
    negative_image: "large/minus.png",
    invalid_image: "large/none.png",
  });
  const hpa = "row2/unit_hpa.png";
  textImg(L.pressure.text, "ALTIMETER", ROW2, sp.row2, {
    unit_sc: hpa,
    unit_tc: hpa,
    unit_en: hpa,
    imperial_unit_sc: hpa,
    imperial_unit_tc: hpa,
    imperial_unit_en: hpa,
    invalid_image: "row2/none.png",
  });

  // Bateria na górze: ikona + procent
  imgLevel(L.battery.icon, "BATTERY", imgs("battery", 6));
  const pct = "tiny/unit_pct.png";
  textImg(L.battery.text, "BATTERY", TINY, sp.tiny, {
    unit_sc: pct,
    unit_tc: pct,
    unit_en: pct,
    align_h: hmUI.align.LEFT,
  });

  // Godzina najbliższego budzika obok dzwonka - dot_image służy jako dwukropek
  textImg(L.alarm, "ALARM_CLOCK", ROW2, sp.row2, { dot_image: "row2/colon.png", invalid_image: "row2/blank.png" });

  // Stuknięcie w pole otwiera odpowiednią aplikację systemową
  click(L.steps.click, "STEP");
  click(L.heart.click, "HEART");
  click(w.click, "WEATHER_CURRENT");
  click(L.altitude.click, "ALTIMETER");
}

function buildAod() {
  const AOD = hmUI.show_level.ONAL_AOD;
  make("IMG", { x: L.aod.frameX, y: L.aod.frameY, src: "aod/frame.png", show_level: AOD });
  make("IMG", { x: L.time.colonX, y: L.time.y, src: "aod/colon.png", show_level: AOD });
  buildTime(AOD, AOD_BIG, false);
  buildDate(AOD, AOD_WEEK, AOD_MED);
}

WatchFace({
  build() {
    buildNormal();
    buildAod();
  },
});
