// Testy logiki gry: `node test/game.test.mjs` (albo `npm test`). Nie wymagają zegarka.
import assert from "node:assert/strict";
import { EMPTY, X, O, newBoard, findWinner, isFull, bestMove, other } from "../utils/game.js";

const _ = EMPTY;

// wykrywanie wygranej
assert.equal(findWinner(newBoard()), null);
assert.deepEqual(findWinner([X, X, X, _, O, O, _, _, _]), { player: X, line: [0, 1, 2] });
assert.deepEqual(findWinner([O, X, _, O, X, _, O, _, X]), { player: O, line: [0, 3, 6] });
assert.deepEqual(findWinner([X, O, O, _, X, _, _, _, X]), { player: X, line: [0, 4, 8] });
assert.deepEqual(findWinner([O, X, X, X, O, _, _, _, O]), { player: O, line: [0, 4, 8] });
assert.equal(isFull([X, O, X, X, O, O, O, X, X]), true);
assert.equal(isFull([X, O, X, X, _, O, O, X, X]), false);

// wygrana ma pierwszeństwo przed blokiem
assert.equal(bestMove([O, O, _, X, X, _, _, _, _], O), 2);
// blokuje zagrożenie przeciwnika
assert.equal(bestMove([X, X, _, O, _, _, _, _, _], O), 2);
assert.equal(bestMove([X, _, _, X, O, _, _, _, _], O), 6);
// bierze środek, gdy wolny
assert.equal(bestMove([X, _, _, _, _, _, _, _, _], O), 4);
// potem róg
const corner = bestMove([_, _, _, _, X, _, _, _, _], O);
assert.ok([0, 2, 6, 8].includes(corner), "spodziewany róg, dostałem " + corner);
// pełna plansza
assert.equal(bestMove([X, O, X, X, O, O, O, X, X], O), -1);

// symulacja: losowy X kontra zegarek O
function randomMove(board, rnd) {
  const empty = [];
  board.forEach((c, i) => c === EMPTY && empty.push(i));
  return empty[Math.floor(rnd() * empty.length)];
}
let seed = 12345;
const rnd = () => {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x80000000;
};

const stats = { [X]: 0, [O]: 0, draw: 0 };
for (let g = 0; g < 2000; g++) {
  const board = newBoard();
  let current = g % 2 === 0 ? X : O;
  for (;;) {
    const move = current === X ? randomMove(board, rnd) : bestMove(board, O, rnd);
    assert.equal(board[move], EMPTY, "ruch na zajęte pole");
    board[move] = current;
    const win = findWinner(board);
    if (win) { stats[win.player]++; break; }
    if (isFull(board)) { stats.draw++; break; }
    current = other(current);
  }
}
console.log("losowy X vs zegarek O (2000 gier):", { X: stats[X], O: stats[O], remis: stats.draw });
assert.ok(stats[O] > stats[X] * 5, "zegarek powinien wyraźnie wygrywać z losowym graczem");

// zegarek kontra zegarek - nie może się wysypać
const ai = { [X]: 0, [O]: 0, draw: 0 };
for (let g = 0; g < 500; g++) {
  const board = newBoard();
  let current = g % 2 === 0 ? X : O;
  for (;;) {
    const move = bestMove(board, current, rnd);
    board[move] = current;
    const win = findWinner(board);
    if (win) { ai[win.player]++; break; }
    if (isFull(board)) { ai.draw++; break; }
    current = other(current);
  }
}
console.log("zegarek vs zegarek (500 gier):", { X: ai[X], O: ai[O], remis: ai.draw });
console.log("WSZYSTKIE TESTY OK");
