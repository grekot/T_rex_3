// Logika listy zakupów po stronie zegarka - czyste funkcje, testy w test/shopping.test.mjs.
//
// Format danych przesyłanych z telefonu (krótkie klucze, bo idzie przez Bluetooth):
//   list: { id, name, o: 1 moja | 0 cudza, s: liczba osób z dostępem, items: [item] }
//   item: { id, n: nazwa, c: 0|1 kupione, t: dodano (ms), k: odhaczono (ms) | 0 }
//
// Operacje wykonane na zegarku czekają w kolejce, aż telefon je potwierdzi (działa offline):
//   { id, t: "toggle",  l, i, c: 0|1, at }
//   { id, t: "addItem", l, i, n, at }
//   { id, t: "delItem", l, i, at }
//   { id, t: "addList", l, n, at }
//   { id, t: "delList", l, at }      - usunięcie własnej listy
//   { id, t: "leaveList", l, at }    - wypisanie się z cudzej (udostępnionej) listy
// Telefon wykonuje je po kolei i zwraca listę id potwierdzonych operacji.

const FAR = 8640000000000000;
const ID_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

// Identyfikator jak w Firestore (20 znaków) - nowe listy i produkty dostają go już na zegarku
export function newId(rnd = Math.random) {
  let id = "";
  for (let i = 0; i < 20; i++) id += ID_CHARS.charAt(Math.floor(rnd() * ID_CHARS.length));
  return id;
}

export function compactItem(doc) {
  return {
    id: doc.id,
    n: doc.name || "",
    c: doc.checked ? 1 : 0,
    t: doc.createdAt || 0,
    k: doc.checkedAt || 0,
  };
}

export function compactList(doc, itemDocs, uid) {
  const members = Array.isArray(doc.members) ? doc.members : [];
  return {
    id: doc.id,
    name: doc.name || "",
    o: !doc.ownerId || doc.ownerId === uid ? 1 : 0,
    s: members.length,
    items: (itemDocs || []).map(compactItem),
  };
}

// Listy bez pola "o" (starsze dane w pamięci zegarka) traktujemy jak własne
export function isOwn(list) {
  return list.o !== 0;
}

export function isShared(list) {
  return (list.s || 0) > 1;
}

// Najpierw do kupienia (w kolejności dodania), potem kupione (ostatnio odhaczone wyżej).
// Brak daty = zapis jeszcze nie dotarł na serwer = najnowszy.
export function sortItems(items) {
  const todo = items.filter((i) => !i.c).sort((a, b) => (a.t || FAR) - (b.t || FAR));
  const done = items.filter((i) => i.c).sort((a, b) => (b.k || FAR) - (a.k || FAR));
  return todo.concat(done);
}

export function counts(list) {
  const total = list.items.length;
  const done = list.items.filter((i) => i.c).length;
  return { total, done, todo: total - done };
}

export function findList(lists, listId) {
  for (let i = 0; i < lists.length; i++) {
    if (lists[i].id === listId) return lists[i];
  }
  return null;
}

// "  Mleko  2% " i "mleko 2%" to ten sam produkt
export function normalizeName(name) {
  return String(name || "")
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

export function cleanName(name) {
  return String(name || "")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, 100);
}

// --- tworzenie operacji ---

export function toggleOp(listId, item, at, rnd) {
  return { id: newId(rnd), t: "toggle", l: listId, i: item.id, c: item.c ? 0 : 1, at };
}

export function addItemOp(listId, name, at, rnd) {
  return { id: newId(rnd), t: "addItem", l: listId, i: newId(rnd), n: cleanName(name), at };
}

export function delItemOp(listId, itemId, at, rnd) {
  return { id: newId(rnd), t: "delItem", l: listId, i: itemId, at };
}

export function addListOp(name, at, rnd) {
  return { id: newId(rnd), t: "addList", l: newId(rnd), n: cleanName(name), at };
}

export function delListOp(listId, at, rnd) {
  return { id: newId(rnd), t: "delList", l: listId, at };
}

export function leaveListOp(listId, at, rnd) {
  return { id: newId(rnd), t: "leaveList", l: listId, at };
}

// Własną listę usuwamy, z cudzej się wypisujemy
export function removeListOp(list, at, rnd) {
  return isOwn(list) ? delListOp(list.id, at, rnd) : leaveListOp(list.id, at, rnd);
}

// --- kolejka ---

// Dodaje operację do kolejki. Starsze odhaczenia tego samego produktu są zbędne
// (liczy się ostatni stan); usunięcie produktu/listy unieważnia ich odhaczenia.
// Dodawania nie kasujemy nawet przy usunięciu - mogło już być w drodze do telefonu,
// a telefon i tak wykona "dodaj, potem usuń" po kolei.
export function queueOp(pending, op) {
  let rest = pending;
  if (op.t === "toggle" || op.t === "delItem") {
    rest = rest.filter((p) => !(p.t === "toggle" && p.l === op.l && p.i === op.i));
  } else if (op.t === "delList" || op.t === "leaveList") {
    rest = rest.filter((p) => !(p.t === "toggle" && p.l === op.l));
  }
  return rest.concat([op]);
}

// Usuwa z kolejki operacje potwierdzone przez telefon
export function removeApplied(pending, appliedIds) {
  const done = {};
  (appliedIds || []).forEach((id) => {
    done[id] = true;
  });
  return pending.filter((p) => !done[p.id]);
}

// Nakłada kolejkę na dane z telefonu (bez modyfikowania wejścia) - tak widzi to użytkownik
export function applyOps(lists, ops) {
  if (!ops.length) return lists;
  let out = lists.map((l) => ({ ...l, items: l.items.slice() }));
  ops.forEach((op) => {
    if (op.t === "addList") {
      if (!findList(out, op.l)) out.push({ id: op.l, name: op.n, o: 1, s: 1, items: [] });
      return;
    }
    if (op.t === "delList" || op.t === "leaveList") {
      out = out.filter((l) => l.id !== op.l);
      return;
    }
    const list = findList(out, op.l);
    if (!list) return;
    if (op.t === "addItem") {
      if (!list.items.some((i) => i.id === op.i)) list.items.push({ id: op.i, n: op.n, c: 0, t: op.at, k: 0 });
    } else if (op.t === "delItem") {
      list.items = list.items.filter((i) => i.id !== op.i);
    } else if (op.t === "toggle") {
      list.items = list.items.map((i) => (i.id === op.i ? { ...i, c: op.c ? 1 : 0, k: op.c ? op.at : 0 } : i));
    }
  });
  return out;
}

// --- dodawanie produktu z zegarka ---

// Co zrobić z wpisaną nazwą: dodać, przywrócić kupiony (odznaczyć) albo nic (już jest na liście)
export function planAdd(list, name) {
  const key = normalizeName(name);
  if (!key) return { action: "empty" };
  for (let i = 0; i < list.items.length; i++) {
    const item = list.items[i];
    if (normalizeName(item.n) === key) {
      return item.c ? { action: "uncheck", item } : { action: "exists", item };
    }
  }
  return { action: "add" };
}

// Podpowiedzi produktów: nazwy ze wszystkich list i z historii zegarka,
// bez tych, które już czekają na zakup na tej liście. Najpierw najczęstsze.
export function suggestions(lists, listId, history, limit = 30) {
  const target = findList(lists, listId);
  const onList = {};
  if (target) {
    target.items.forEach((i) => {
      if (!i.c) onList[normalizeName(i.n)] = true;
    });
  }
  const score = {};
  const label = {};
  const bump = (name, points) => {
    const key = normalizeName(name);
    if (!key || onList[key]) return;
    score[key] = (score[key] || 0) + points;
    if (!label[key]) label[key] = cleanName(name);
  };
  lists.forEach((l) => l.items.forEach((i) => bump(i.n, l.id === listId ? 2 : 1)));
  (history || []).forEach((name) => bump(name, 1));
  return Object.keys(score)
    .sort((a, b) => score[b] - score[a] || (a < b ? -1 : 1))
    .slice(0, limit)
    .map((k) => label[k]);
}

// Historia nazw wpisanych na zegarku (najnowsze na początku, bez powtórzeń)
export function rememberName(history, name, limit = 50) {
  const key = normalizeName(name);
  if (!key) return history;
  return [cleanName(name)].concat((history || []).filter((n) => normalizeName(n) !== key)).slice(0, limit);
}

// Podpowiedzi nazw nowej listy: typowe sklepy, bez nazw już istniejących list
export const SHOP_NAMES = ["Zakupy", "Biedronka", "Lidl", "Żabka", "Kaufland", "Auchan", "Rossmann", "Apteka", "Castorama", "Leroy Merlin"];

export function listNameSuggestions(lists) {
  const taken = {};
  lists.forEach((l) => {
    taken[normalizeName(l.name)] = true;
  });
  return SHOP_NAMES.filter((n) => !taken[normalizeName(n)]);
}
