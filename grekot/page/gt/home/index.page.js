import * as hmUI from "@zos/ui";
import { log as Logger } from "@zos/utils";
import {
  RING_STYLE,
  RING_STOPS,
  RING_SEGMENTS,
  INNER_RING_STYLE,
  NAME_SHADOW_STYLE,
  NAME_STYLE,
  BAR_STYLE,
  SUBTITLE_STYLE,
} from "zosLoader:./index.page.[pf].layout.js";

const logger = Logger.getLogger("grekot");

// Liniowa interpolacja dwóch kolorów 0xRRGGBB, t w zakresie 0..1
function mixColor(a, b, t) {
  const ch = (c, shift) => (c >> shift) & 0xff;
  const lerp = (shift) => Math.round(ch(a, shift) + (ch(b, shift) - ch(a, shift)) * t);
  return (lerp(16) << 16) | (lerp(8) << 8) | lerp(0);
}

// Kolor w punkcie t (0..1) gradientu złożonego z wielu przystanków
function gradientAt(stops, t) {
  const pos = t * (stops.length - 1);
  const i = Math.min(Math.floor(pos), stops.length - 2);
  return mixColor(stops[i], stops[i + 1], pos - i);
}

// Pierścień z gradientem rysowany jako wiele krótkich łuków
function drawGradientRing(style, stops, segments) {
  const span = (style.end_angle - style.start_angle) / segments;
  for (let i = 0; i < segments; i++) {
    const start = style.start_angle + i * span;
    hmUI.createWidget(hmUI.widget.ARC, {
      ...style,
      start_angle: start,
      // +1° zakładki, żeby między segmentami nie było szczelin
      end_angle: start + span + 1,
      color: gradientAt(stops, (i + 0.5) / segments),
    });
  }
}

Page({
  onInit() {
    logger.debug("page onInit invoked");
  },
  build() {
    logger.debug("page build invoked");
    drawGradientRing(RING_STYLE, RING_STOPS, RING_SEGMENTS);
    hmUI.createWidget(hmUI.widget.ARC, INNER_RING_STYLE);
    hmUI.createWidget(hmUI.widget.TEXT, NAME_SHADOW_STYLE);
    hmUI.createWidget(hmUI.widget.TEXT, NAME_STYLE);
    hmUI.createWidget(hmUI.widget.FILL_RECT, BAR_STYLE);
    hmUI.createWidget(hmUI.widget.TEXT, SUBTITLE_STYLE);
  },
  onDestroy() {
    logger.debug("page onDestroy invoked");
  },
});
