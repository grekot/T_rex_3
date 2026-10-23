import { BaseApp } from "@zeppos/zml/base-app";

// BaseApp z biblioteki zml uruchamia kanał komunikacji zegarek <-> telefon (synchronizacja pomiarów)
App(
  BaseApp({
    globalData: {},
    onCreate() {},
    onDestroy() {},
  })
);
