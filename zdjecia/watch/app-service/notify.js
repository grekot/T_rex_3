// Usługa jednorazowa (budzik systemowy): powiadomienie „Zobacz to” z przyciskiem „Pokaż”.
// Usługa ma 600 ms, bez ekranu i bez timerów - tylko wybór zdjęcia i powiadomienie.
import { notify } from "@zos/notification";
import { notificationFor } from "../utils/notify.js";

function report(title, content) {
  try {
    notify({ title, content, actions: [], vibrate: 0 });
  } catch (e) {}
}

AppService({
  onInit(param) {
    let n;
    try {
      n = notificationFor(param, Math.random);
      const id = notify(n);
      // 0 = system odrzucił powiadomienie (np. sposób A z ekranem zamiast usługi w przycisku)
      if (!id) report("Zdjęcia: powiadomienie odrzucone", "System nie przyjął przycisku do: " + n.actions[0].file);
    } catch (e) {
      report("Zdjęcia: błąd powiadomienia", String((e && e.message) || e));
    }
  },
  onDestroy() {},
});
