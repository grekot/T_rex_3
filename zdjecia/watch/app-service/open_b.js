// Sposób B: przycisk „Pokaż” uruchamia tę usługę, a ona otwiera ekran zdjęcia przez launchApp.
import { launchApp } from "@zos/router";
import { getPackageInfo } from "@zos/app";
import { notify } from "@zos/notification";
import { PHOTO_PAGE, openParam } from "../utils/notify.js";

AppService({
  onInit(param) {
    try {
      launchApp({ appId: getPackageInfo().appId, url: PHOTO_PAGE, native: false, params: openParam(param) });
    } catch (e) {
      try {
        notify({ title: "Zdjęcia: sposób B", content: "launchApp: " + String((e && e.message) || e), actions: [], vibrate: 0 });
      } catch (e2) {}
    }
  },
  onDestroy() {},
});
