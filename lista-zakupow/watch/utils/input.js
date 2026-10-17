// Wpisywanie tekstu na zegarku: systemowa klawiatura Zepp OS 4 (pisanie albo dyktowanie).
import { createKeyboard, deleteKeyboard, inputType } from "@zos/ui";

export function canType() {
  return typeof createKeyboard === "function" && !!inputType;
}

// onDone(tekst) dostaje wpisany tekst; anulowanie (gest w prawo) nic nie robi.
// Zwraca false, gdy klawiatura jest niedostępna.
export function askText(voice, onDone) {
  if (!canType()) return false;
  const close = () => {
    try {
      deleteKeyboard();
    } catch (e) {}
  };
  createKeyboard({
    inputType: voice && inputType.VOICE !== undefined ? inputType.VOICE : inputType.CHAR,
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
