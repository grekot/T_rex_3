// Wpisywanie nazwy na zegarku: systemowa klawiatura Zepp OS 4 (pisanie albo dyktowanie).
import { createKeyboard, deleteKeyboard, inputType } from "@zos/ui";

export function canType() {
  return typeof createKeyboard === "function" && !!inputType;
}

// onDone(tekst); anulowanie (gest w prawo) nic nie robi. false = klawiatura niedostępna.
export function askText(onDone) {
  if (!canType()) return false;
  const close = () => {
    try {
      deleteKeyboard();
    } catch (e) {}
  };
  createKeyboard({
    inputType: inputType.CHAR,
    text: "",
    onComplete: (_, result) => {
      close();
      const text = result && typeof result.data === "string" ? result.data : "";
      if (text.trim()) onDone(text);
    },
    onCancel: () => close(),
  });
  return true;
}
