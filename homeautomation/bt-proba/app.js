import { BaseApp } from "@zeppos/zml/base-app";

// BaseApp uruchamia kanał zegarek <-> telefon: pomiar sprawdza, czy działa on razem z połączeniem do ESP32
App(
  BaseApp({
    globalData: {},
    onCreate() {},
    onDestroy() {},
  })
);
