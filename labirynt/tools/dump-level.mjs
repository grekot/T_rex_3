// Wypisuje poziom jako JSON - dla tools/gen_assets.py (podgląd do README).
// Użycie: node tools/dump-level.mjs <numer poziomu>
import { buildLevel, cellCenter } from "../utils/maze.js";

const lv = buildLevel(Number(process.argv[2] || 1));
console.log(
  JSON.stringify({
    size: lv.size,
    walls: lv.walls,
    holes: lv.holePoints,
    goal: lv.goalPoint,
    start: lv.startPoint,
    pathPoints: lv.path.map((i) => cellCenter(lv.size, i)),
  })
);
