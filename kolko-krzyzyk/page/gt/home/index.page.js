import * as hmUI from "@zos/ui";
import { Vibrator, VIBRATOR_SCENE_SHORT_MIDDLE } from "@zos/sensor";
import { log as Logger } from "@zos/utils";
import { EMPTY, X, O, other, newBoard, findWinner, isFull, bestMove } from "../../../utils/game";
import {
  cellRect,
  CELL_STYLE,
  MARK_STYLE,
  SCORE_STYLE,
  STATUS_STYLE,
  HINT_STYLE,
  ERROR_STYLE,
  COLOR_CELL,
  COLOR_X,
  COLOR_O,
  COLOR_X_WIN,
  COLOR_O_WIN,
  COLOR_GREY,
  COLOR_TEXT,
} from "zosLoader:./index.page.[pf].layout.js";

const logger = Logger.getLogger("kolko-krzyzyk");

// Krótka pauza przed ruchem zegarka, żeby gra nie wyglądała na "natychmiastową"
const WATCH_DELAY_MS = 450;

const MODE_WATCH = "watch"; // gracz (X) kontra zegarek (O)
const MODE_TWO = "two";     // dwie osoby na jednym zegarku

Page({
  state: {
    board: newBoard(),
    current: X,
    starter: X,
    mode: MODE_WATCH,
    over: false,
    locked: false,
    destroyed: false,
    score: { [X]: 0, [O]: 0, draws: 0 },
    cells: [],
    marks: [],
    scoreText: null,
    statusText: null,
    hintText: null,
    vibrator: null,
  },

  onInit() {
    logger.debug("page onInit invoked");
  },

  build() {
    logger.debug("page build invoked");
    try {
      this.buildBoard();
    } catch (e) {
      // Zamiast czarnego ekranu pokaż, co poszło nie tak
      logger.error("build failed: " + e);
      hmUI.createWidget(hmUI.widget.TEXT, { ...ERROR_STYLE, text: "Błąd: " + e });
    }
  },

  onDestroy() {
    logger.debug("page onDestroy invoked");
    this.state.destroyed = true;
    try {
      if (this.state.vibrator) this.state.vibrator.stop();
    } catch (e) {}
  },

  buildBoard() {
    const s = this.state;

    s.scoreText = hmUI.createWidget(hmUI.widget.TEXT, SCORE_STYLE);
    s.scoreText.addEventListener(hmUI.event.CLICK_UP, () => this.toggleMode());

    for (let i = 0; i < 9; i++) {
      const rect = cellRect(i);
      const cell = hmUI.createWidget(hmUI.widget.FILL_RECT, { ...rect, ...CELL_STYLE });
      const mark = hmUI.createWidget(hmUI.widget.TEXT, { ...rect, ...MARK_STYLE });
      const onTap = () => this.onCellTap(i);
      cell.addEventListener(hmUI.event.CLICK_UP, onTap);
      mark.addEventListener(hmUI.event.CLICK_UP, onTap);
      s.cells.push(cell);
      s.marks.push(mark);
    }

    s.statusText = hmUI.createWidget(hmUI.widget.TEXT, STATUS_STYLE);
    s.statusText.addEventListener(hmUI.event.CLICK_UP, () => {
      if (s.over) this.newRound();
    });
    s.hintText = hmUI.createWidget(hmUI.widget.TEXT, HINT_STYLE);

    this.newRound();
  },

  newRound() {
    const s = this.state;
    s.board = newBoard();
    s.over = false;
    s.locked = false;
    s.current = s.starter;
    for (let i = 0; i < 9; i++) {
      this.setMark(i, EMPTY);
      this.setCellColor(i, COLOR_CELL);
    }
    this.refreshScore();
    this.refreshStatus(null);
    this.maybeWatchMove();
  },

  onCellTap(i) {
    const s = this.state;
    if (s.over) {
      this.newRound();
      return;
    }
    if (s.locked || s.board[i] !== EMPTY) return;
    this.play(i);
  },

  play(i) {
    const s = this.state;
    s.board[i] = s.current;
    this.setMark(i, s.current);

    const win = findWinner(s.board);
    if (win) {
      this.finish(win);
      return;
    }
    if (isFull(s.board)) {
      this.finish(null);
      return;
    }
    s.current = other(s.current);
    this.refreshStatus(null);
    this.maybeWatchMove();
  },

  maybeWatchMove() {
    const s = this.state;
    if (s.mode !== MODE_WATCH || s.current !== O || s.over) return;
    s.locked = true;
    this.refreshStatus(null);
    // setTimeout jest w Zepp OS funkcją globalną (moduł @zos/timer nie istnieje w API 3.0)
    setTimeout(() => {
      if (s.destroyed || s.over) return;
      s.locked = false;
      const move = bestMove(s.board, O);
      if (move >= 0) this.play(move);
    }, WATCH_DELAY_MS);
  },

  finish(win) {
    const s = this.state;
    s.over = true;
    s.locked = false;
    if (win) {
      s.score[win.player]++;
      const color = win.player === X ? COLOR_X_WIN : COLOR_O_WIN;
      win.line.forEach((i) => this.setCellColor(i, color));
      this.vibrate();
    } else {
      s.score.draws++;
    }
    // W kolejnej rundzie zaczyna druga strona
    s.starter = other(s.starter);
    this.refreshScore();
    this.refreshStatus(win);
  },

  toggleMode() {
    const s = this.state;
    s.mode = s.mode === MODE_WATCH ? MODE_TWO : MODE_WATCH;
    s.score = { [X]: 0, [O]: 0, draws: 0 };
    s.starter = X;
    this.newRound();
  },

  refreshScore() {
    const s = this.state;
    const left = s.mode === MODE_WATCH ? "TY" : "X";
    const right = s.mode === MODE_WATCH ? "ZEGAREK" : "O";
    this.setText(s.scoreText, SCORE_STYLE, left + " " + s.score[X] + " : " + s.score[O] + " " + right, COLOR_TEXT);
  },

  refreshStatus(win) {
    const s = this.state;
    let text;
    let color = COLOR_TEXT;
    let hint = "";

    if (s.over) {
      hint = "stuknij, by zagrać";
      if (!win) {
        text = "Remis";
      } else if (s.mode === MODE_WATCH) {
        text = win.player === X ? "Wygrana!" : "Zegarek wygrał";
      } else {
        text = win.player === X ? "Wygrał X" : "Wygrało O";
      }
      if (win) color = win.player === X ? COLOR_X : COLOR_O;
    } else if (s.locked) {
      text = "Zegarek myśli...";
      color = COLOR_O;
    } else {
      if (s.mode === MODE_WATCH) {
        text = "Twój ruch (X)";
      } else {
        text = s.current === X ? "Ruch gracza X" : "Ruch gracza O";
      }
      color = s.current === X ? COLOR_X : COLOR_O;
    }

    this.setText(s.statusText, STATUS_STYLE, text, color);
    this.setText(s.hintText, HINT_STYLE, hint, COLOR_GREY);
  },

  setMark(i, player) {
    const text = player === X ? "X" : player === O ? "O" : "";
    const color = player === X ? COLOR_X : COLOR_O;
    this.setText(this.state.marks[i], { ...cellRect(i), ...MARK_STYLE }, text, color);
  },

  setCellColor(i, color) {
    this.state.cells[i].setProperty(hmUI.prop.MORE, { ...cellRect(i), ...CELL_STYLE, color });
  },

  setText(widget, style, text, color) {
    widget.setProperty(hmUI.prop.MORE, { ...style, text, color });
  },

  // Wibracja jest dodatkiem - tworzona dopiero przy pierwszej wygranej,
  // a każdy błąd jest ignorowany, żeby nie zepsuć gry.
  vibrate() {
    const s = this.state;
    try {
      if (!s.vibrator) {
        s.vibrator = new Vibrator();
        s.vibrator.setMode(VIBRATOR_SCENE_SHORT_MIDDLE);
      }
      s.vibrator.start();
    } catch (e) {
      logger.debug("wibracje niedostępne: " + e);
    }
  },
});
