// Czy lista miejsc jest przykryta innym ekranem (zapis, nawigacja)?
// Ekran pod spodem żyje dalej po push(), a widgety tworzone z jego timerów i odpowiedzi
// telefonu lądują na ekranie, który akurat widać - wtedy lista nie może się przerysować.
function data() {
  try {
    return getApp()._options.globalData;
  } catch (e) {
    return {};
  }
}

export function setCovered(covered) {
  data().covered = covered;
}

export function isCovered() {
  return !!data().covered;
}
