import { BaseApp } from "@zeppos/zml/base-app";

// BaseApp z biblioteki zml uruchamia kanał komunikacji zegarek <-> telefon (Side Service w aplikacji Zepp).
// Parametr startu (budzik, launchApp) trafia do onCreate - ekran zdjęcia odczyta go z globalData.
App(
  BaseApp({
    globalData: { launch: "" },
    onCreate(params) {
      this.globalData.launch = params || "";
    },
    onDestroy() {},
  })
);
