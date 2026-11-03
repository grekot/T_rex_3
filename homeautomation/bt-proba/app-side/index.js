// Side Service: odpowiada od razu, żeby zmierzyć samą drogę zegarek <-> telefon
import { BaseSideService } from "@zeppos/zml/base-side";

AppSideService(
  BaseSideService({
    onInit() {},
    onRequest(req, res) {
      res(null, { ok: true });
    },
    onRun() {},
    onDestroy() {},
  })
);
