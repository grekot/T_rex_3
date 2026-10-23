const fs = require("fs");
const path = require("path");
const OUT = process.env.ZEUS_CAPTURE;
const copy = fs.copyFileSync;
const append = fs.appendFileSync;
function log(t) {
  try {
    append(path.join(OUT, "_log.txt"), t + "\n");
  } catch (e) {}
}
function grab(p) {
  try {
    p = String(p);
    if (!/zpm-/.test(p) || !/\.js$/.test(p)) return;
    const m = p.match(/zpm-[^\\/]+[\\/]dist[\\/]gt\.r-ZPS-480x480[\\/]device[\\/](.*\.js)$/);
    log((m ? "M " : "- ") + p + " exists=" + fs.existsSync(p));
    if (!m) return;
    copy(p, path.join(OUT, m[1].replace(/[\\/]/g, "_")));
  } catch (e) {
    log("ERR " + e);
  }
}
const o1 = fs.writeFileSync;
fs.writeFileSync = function (p, ...r) {
  const res = o1.call(this, p, ...r);
  grab(p);
  return res;
};
const o2 = fs.writeFile;
fs.writeFile = function (p, d, ...r) {
  const cb = r.pop();
  return o2.call(this, p, d, ...r, function (...a) {
    grab(p);
    if (typeof cb === "function") cb.apply(this, a);
  });
};
const o3 = fs.promises.writeFile;
fs.promises.writeFile = function (p, ...r) {
  return o3.call(this, p, ...r).then((v) => {
    grab(p);
    return v;
  });
};
