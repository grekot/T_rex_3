import * as hmUI from "@zos/ui";
import { LocalStorage } from "@zos/storage";
import { onGesture, offGesture, GESTURE_LEFT, GESTURE_RIGHT } from "@zos/interaction";
import { log as Logger } from "@zos/utils";
import { BasePage } from "@zeppos/zml/base-page";
import {
  formatCompact,
  plural,
  withUnit,
  formatTime,
  formatDuration,
  relativeDay,
  shorten,
} from "../../../utils/format";
import {
  TITLE_STYLE,
  CHANNEL_STYLE,
  COUNT_STYLE,
  LABEL_STYLE,
  DETAILS_STYLE,
  VIDEO_TITLE_STYLE,
  VIDEO_COUNT_STYLE,
  VIDEO_LABEL_STYLE,
  STATUS_STYLE,
  STAT_ICONS,
  statIconProps,
  statTextStyle,
  dotProps,
  COLOR_GREY,
  COLOR_ORANGE,
  COLOR_RED,
  COLOR_VALUE,
} from "zosLoader:./index.page.[pf].layout.js";

const logger = Logger.getLogger("youtube-subs");

// Automatyczne odświeżanie, gdy aplikacja jest otwarta
const REFRESH_MS = 5 * 60 * 1000;
const CACHE_KEY = "yt_stats";

// Ekrany przełączane przesunięciem palca w lewo/prawo
const SCREEN_CHANNEL = 0;
const SCREEN_VIDEO = 1;
const SCREEN_SHORT = 2;
const SCREENS = 3;
const HEADERS = ["YouTube", "OSTATNI FILM", "OSTATNI SHORT"];

// Komórki siatki ikon na ekranie filmu
const STAT_LIKES = 0;
const STAT_COMMENTS = 1;
const STAT_DATE = 2;
const STAT_DURATION = 3;

const storage = new LocalStorage();

Page(
  BasePage({
    state: {
      stats: null,
      loading: false,
      timer: null,
      screen: SCREEN_CHANNEL,
      header: null,
      channelSet: [],
      videoSet: [],
      channel: null,
      count: null,
      label: null,
      details: null,
      vTitle: null,
      vCount: null,
      vLabel: null,
      statTexts: [],
      status: null,
      dots: [],
    },

    onInit() {
      logger.debug("page onInit invoked");
      this.state.stats = this.loadCache();
    },

    build() {
      logger.debug("page build invoked");
      const s = this.state;

      s.header = hmUI.createWidget(hmUI.widget.TEXT, TITLE_STYLE);

      // ekran kanału
      s.channel = hmUI.createWidget(hmUI.widget.TEXT, CHANNEL_STYLE);
      s.count = hmUI.createWidget(hmUI.widget.TEXT, COUNT_STYLE);
      s.label = hmUI.createWidget(hmUI.widget.TEXT, LABEL_STYLE);
      s.details = hmUI.createWidget(hmUI.widget.TEXT, DETAILS_STYLE);
      s.channelSet = [s.channel, s.count, s.label, s.details];

      // ekran filmu / shorta
      s.vTitle = hmUI.createWidget(hmUI.widget.TEXT, VIDEO_TITLE_STYLE);
      s.vCount = hmUI.createWidget(hmUI.widget.TEXT, VIDEO_COUNT_STYLE);
      s.vLabel = hmUI.createWidget(hmUI.widget.TEXT, VIDEO_LABEL_STYLE);
      s.videoSet = [s.vTitle, s.vCount, s.vLabel];
      for (let i = 0; i < STAT_ICONS.length; i++) {
        const icon = hmUI.createWidget(hmUI.widget.IMG, statIconProps(i));
        const text = hmUI.createWidget(hmUI.widget.TEXT, statTextStyle(i));
        s.statTexts.push(text);
        s.videoSet.push(icon, text);
      }

      s.status = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);
      for (let i = 0; i < SCREENS; i++) {
        s.dots.push(hmUI.createWidget(hmUI.widget.CIRCLE, dotProps(i, SCREENS, i === SCREEN_CHANNEL)));
      }

      // Stuknięcie w dowolny tekst lub ikonę odświeża dane
      [s.header, ...s.channelSet, ...s.videoSet, s.status].forEach((w) =>
        w.addEventListener(hmUI.event.CLICK_UP, () => this.refresh())
      );

      // Przesunięcie w lewo: następny ekran; w prawo: poprzedni (na pierwszym - wyjście z aplikacji)
      onGesture({
        callback: (event) => {
          if (event === GESTURE_LEFT && s.screen < SCREENS - 1) {
            this.showScreen(s.screen + 1);
            return true;
          }
          if (event === GESTURE_RIGHT && s.screen > SCREEN_CHANNEL) {
            this.showScreen(s.screen - 1);
            return true;
          }
          return false;
        },
      });

      this.showScreen(SCREEN_CHANNEL);
      this.refresh();
      s.timer = setInterval(() => this.refresh(), REFRESH_MS);
    },

    onDestroy() {
      logger.debug("page onDestroy invoked");
      if (this.state.timer) clearInterval(this.state.timer);
      try {
        offGesture();
      } catch (e) {}
    },

    // Telefon sam przysyła dane po zmianie ustawień
    onCall(req) {
      if (req && req.type === "STATS") this.applyResult(req.result);
    },

    showScreen(index) {
      const s = this.state;
      s.screen = index;
      const showChannel = index === SCREEN_CHANNEL;
      s.channelSet.forEach((w) => w.setProperty(hmUI.prop.VISIBLE, showChannel));
      s.videoSet.forEach((w) => w.setProperty(hmUI.prop.VISIBLE, !showChannel));
      s.dots.forEach((d, i) => d.setProperty(hmUI.prop.MORE, dotProps(i, SCREENS, i === index)));
      this.render();
    },

    refresh() {
      const s = this.state;
      if (s.loading) return;
      s.loading = true;
      this.setStatus("Pobieram...", COLOR_GREY);
      this.request({ method: "GET_STATS", timeout: 25000 })
        .then((result) => this.applyResult(result))
        .catch((e) => {
          logger.debug("request failed: " + e);
          s.loading = false;
          this.setStatus("Brak połączenia z telefonem", COLOR_ORANGE);
        });
    },

    applyResult(result) {
      const s = this.state;
      s.loading = false;
      if (result && result.ok) {
        s.stats = result.stats;
        this.saveCache(result.stats);
        this.render();
      } else {
        this.render();
        this.setStatus(shorten((result && result.error) || "Nieznany błąd"), COLOR_ORANGE);
      }
    },

    render() {
      const s = this.state;
      const st = s.stats;
      this.setText(s.header, TITLE_STYLE, HEADERS[s.screen]);
      if (s.screen === SCREEN_CHANNEL) {
        this.renderChannel(st);
      } else if (s.screen === SCREEN_VIDEO) {
        this.renderVideo(st ? st.latestVideo : null, st ? st.videoError : null, "filmu");
      } else {
        this.renderVideo(st ? st.latestShort : null, st ? st.shortError : null, "shorta");
      }
      if (st) {
        this.setStatus("odświeżono " + formatTime(new Date(st.fetchedAt)), COLOR_GREY);
      } else {
        this.setStatus("stuknij, aby pobrać", COLOR_GREY);
      }
    },

    renderChannel(st) {
      const s = this.state;
      if (!st) {
        this.setText(s.channel, CHANNEL_STYLE, "Kanał YouTube");
        this.setText(s.count, COUNT_STYLE, "...");
        this.setText(s.label, LABEL_STYLE, "subskrybentów");
        this.setText(s.details, DETAILS_STYLE, "");
        return;
      }
      const hidden = st.subscribers === null;
      this.setText(s.channel, CHANNEL_STYLE, st.title || "Kanał YouTube");
      this.setText(s.count, COUNT_STYLE, hidden ? "ukryte" : formatCompact(st.subscribers));
      this.setText(
        s.label,
        LABEL_STYLE,
        hidden ? "subskrybentów" : plural(st.subscribers, "subskrybent", "subskrybentów", "subskrybentów")
      );
      this.setText(
        s.details,
        DETAILS_STYLE,
        withUnit(st.views, "wyświetlenie", "wyświetlenia", "wyświetleń") +
          "  |  " +
          withUnit(st.videos, "film", "filmy", "filmów")
      );
    },

    renderVideo(video, error, what) {
      const s = this.state;
      if (!video) {
        this.setText(s.vTitle, VIDEO_TITLE_STYLE, error ? shorten(error, 50) : "Brak danych o " + what);
        this.setText(s.vCount, VIDEO_COUNT_STYLE, "...");
        this.setText(s.vLabel, VIDEO_LABEL_STYLE, "wyświetleń");
        for (let i = 0; i < s.statTexts.length; i++) this.setStat(i, "-");
        return;
      }
      this.setText(s.vTitle, VIDEO_TITLE_STYLE, video.title || "(bez tytułu)");
      this.setText(s.vCount, VIDEO_COUNT_STYLE, formatCompact(video.views));
      this.setText(s.vLabel, VIDEO_LABEL_STYLE, plural(video.views, "wyświetlenie", "wyświetlenia", "wyświetleń"));
      // Autor może ukryć polubienia albo wyłączyć komentarze
      this.setStat(STAT_LIKES, video.likes === null ? "ukryte" : formatCompact(video.likes));
      this.setStat(STAT_COMMENTS, video.comments === null ? "wyłączone" : formatCompact(video.comments));
      if (video.live) {
        this.setStat(STAT_DATE, "NA ŻYWO", COLOR_RED);
      } else {
        this.setStat(STAT_DATE, relativeDay(video.publishedAt, Date.now()));
      }
      this.setStat(STAT_DURATION, formatDuration(video.durationSec));
    },

    setStat(index, text, color = COLOR_VALUE) {
      this.state.statTexts[index].setProperty(hmUI.prop.MORE, { ...statTextStyle(index), text, color });
    },

    setStatus(text, color) {
      this.state.status.setProperty(hmUI.prop.MORE, { ...STATUS_STYLE, text, color });
    },

    setText(widget, style, text) {
      widget.setProperty(hmUI.prop.MORE, { ...style, text });
    },

    loadCache() {
      try {
        const raw = storage.getItem(CACHE_KEY);
        return raw ? JSON.parse(raw) : null;
      } catch (e) {
        return null;
      }
    },

    saveCache(stats) {
      try {
        storage.setItem(CACHE_KEY, JSON.stringify(stats));
      } catch (e) {
        logger.debug("cache save failed: " + e);
      }
    },
  })
);
