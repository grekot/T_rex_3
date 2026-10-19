// Sposób C: przycisk „Pokaż” uruchamia tę usługę, a ona ustawia budzik za 1 s z adresem ekranu zdjęcia
// (budzik może budzić ekrany - to jedyna droga opisana w dokumentacji).
import { set } from "@zos/alarm";
import { getPackageInfo } from "@zos/app";
import { notify } from "@zos/notification";
import { PHOTO_PAGE, openParam } from "../utils/notify.js";

AppService({
  onInit(param) {
    try {
      const id = set({ appid: getPackageInfo().appId, url: PHOTO_PAGE, delay: 1, param: openParam(param) });
      if (!id) throw new Error("budzik nie został ustawiony (0)");
    } catch (e) {
      try {
        notify({ title: "Zdjęcia: sposób C", content: "budzik: " + String((e && e.message) || e), actions: [], vibrate: 0 });
      } catch (e2) {}
    }
  },
  onDestroy() {},
});
