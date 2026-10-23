// Wspólne klocki interfejsu. Wszystkie współrzędne w px projektu 480 (px() przelicza
// na inne okrągłe zegarki).
import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { back } from "@zos/router";
import { showToast } from "@zos/interaction";

export const COLOR = {
  text: 0xffffff,
  grey: 0x8a8a96,
  accent: 0xffc85a,
  orange: 0xffaa28,
  pill: 0x26262e,
  pillOn: 0x4a3a1c,
  good: 0x6ee08a,
  bad: 0xff6a6a,
  night: 0x060918,
};

// Klatki Groota: duże (HOME) na ekranie głównym, mniejsze (SPRITE) w grach
export function spriteSrc(form, frame) {
  return "pet/" + form + "/" + frame + ".png";
}

export function gameSprite(form, frame) {
  return "pets/" + form + "/" + frame + ".png";
}

function textProps(o) {
  return {
    x: px(o.x),
    y: px(o.y),
    w: px(o.w),
    h: px(o.h),
    text: o.text || "",
    text_size: px(o.size || 26),
    color: o.color === undefined ? COLOR.text : o.color,
    align_h: o.left ? hmUI.align.LEFT : hmUI.align.CENTER_H,
    align_v: hmUI.align.CENTER_V,
    text_style: o.wrap ? hmUI.text_style.WRAP : hmUI.text_style.NONE,
  };
}

// Napis, który można potem zmieniać: label.set("tekst", kolor?)
export function label(o) {
  const props = textProps(o);
  const w = hmUI.createWidget(hmUI.widget.TEXT, props);
  let last = props.text + "/" + props.color;
  let visible = true;
  return {
    widget: w,
    set(text, color) {
      const c = color === undefined ? props.color : color;
      const key = text + "/" + c;
      if (key === last) return;
      last = key;
      w.setProperty(hmUI.prop.MORE, { ...props, text, color: c });
    },
    show(v) {
      if (v === visible) return;
      visible = v;
      w.setProperty(hmUI.prop.VISIBLE, v);
    },
  };
}

// Obrazek w lewym górnym rogu (x, y); move/show zmieniają go bez tworzenia nowego
export function image(src, x, y) {
  const w = hmUI.createWidget(hmUI.widget.IMG, { x: px(x), y: px(y), src });
  const st = { src, x, y, visible: true };
  return {
    widget: w,
    set(nsrc, nx, ny) {
      const sx = nx === undefined ? st.x : nx;
      const sy = ny === undefined ? st.y : ny;
      if (nsrc === st.src && sx === st.x && sy === st.y) return;
      st.src = nsrc;
      st.x = sx;
      st.y = sy;
      w.setProperty(hmUI.prop.MORE, { x: px(sx), y: px(sy), src: nsrc });
    },
    show(v) {
      if (v === st.visible) return;
      st.visible = v;
      w.setProperty(hmUI.prop.VISIBLE, v);
    },
  };
}

export function rect(x, y, w, h, color, radius) {
  return hmUI.createWidget(hmUI.widget.FILL_RECT, {
    x: px(x),
    y: px(y),
    w: px(w),
    h: px(h),
    radius: px(radius || 0),
    color,
  });
}

export function onTap(widgets, fn) {
  widgets.forEach((w) => w.addEventListener(hmUI.event.CLICK_UP, fn));
}

// Przycisk-pigułka z napisem
export function button(o, fn) {
  const bg = rect(o.x, o.y, o.w, o.h, o.color || COLOR.pill, o.h / 2);
  const txt = label({ x: o.x, y: o.y, w: o.w, h: o.h, text: o.text, size: o.size || 26, color: o.textColor });
  onTap([bg, txt.widget], fn);
  return { bg, txt };
}

export function toast(text) {
  if (!text) return;
  try {
    showToast({ content: text });
  } catch (e) {}
}

export function goBack() {
  try {
    back();
  } catch (e) {}
}

// "1 dzień", "2 dni", "5 dni"
export function daysText(n) {
  return n === 1 ? "1 dzień" : n + " dni";
}
