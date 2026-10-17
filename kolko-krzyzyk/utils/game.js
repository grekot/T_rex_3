// Czysta logika gry - bez UI, dzięki temu da się ją przetestować w Node.

export const EMPTY = 0;
export const X = 1;
export const O = 2;

// Wszystkie trójki pól dające wygraną (indeksy 0..8, wiersz po wierszu)
export const LINES = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], // wiersze
  [0, 3, 6], [1, 4, 7], [2, 5, 8], // kolumny
  [0, 4, 8], [2, 4, 6],            // przekątne
];

export function newBoard() {
  return [EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY];
}

export function other(player) {
  return player === X ? O : X;
}

// Zwraca { player, line } albo null, gdy nikt jeszcze nie wygrał
export function findWinner(board) {
  for (const line of LINES) {
    const [a, b, c] = line;
    if (board[a] !== EMPTY && board[a] === board[b] && board[a] === board[c]) {
      return { player: board[a], line };
    }
  }
  return null;
}

export function isFull(board) {
  return board.indexOf(EMPTY) === -1;
}

export function emptyCells(board) {
  const cells = [];
  for (let i = 0; i < 9; i++) {
    if (board[i] === EMPTY) cells.push(i);
  }
  return cells;
}

function winsWith(board, cell, player) {
  const copy = board.slice();
  copy[cell] = player;
  const win = findWinner(copy);
  return win !== null && win.player === player;
}

function pick(list, rnd) {
  return list[Math.floor(rnd() * list.length)];
}

// Ruch zegarka: wygraj > zablokuj > środek > róg > cokolwiek.
// Celowo nie przewiduje "widełek", żeby dało się go pokonać.
export function bestMove(board, me, rnd = Math.random) {
  const empty = emptyCells(board);
  if (empty.length === 0) return -1;

  const winning = empty.filter((c) => winsWith(board, c, me));
  if (winning.length) return pick(winning, rnd);

  const blocking = empty.filter((c) => winsWith(board, c, other(me)));
  if (blocking.length) return pick(blocking, rnd);

  if (board[4] === EMPTY) return 4;

  const corners = [0, 2, 6, 8].filter((c) => board[c] === EMPTY);
  if (corners.length) return pick(corners, rnd);

  return pick(empty, rnd);
}
