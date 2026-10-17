import 'models.dart';

/// Kolejność jak na zegarku: najpierw do kupienia (w kolejności dodania),
/// potem kupione (ostatnio odhaczone na górze).
/// Elementy bez daty (zapis jeszcze nie dotarł na serwer) traktujemy jak najnowsze.
List<ShoppingItem> sortItems(Iterable<ShoppingItem> items) {
  final far = DateTime.utc(9999);
  final todo = items.where((i) => !i.checked).toList()
    ..sort((a, b) => (a.createdAt ?? far).compareTo(b.createdAt ?? far));
  final done = items.where((i) => i.checked).toList()
    ..sort((a, b) => (b.checkedAt ?? far).compareTo(a.checkedAt ?? far));
  return [...todo, ...done];
}

List<ShoppingList> sortLists(Iterable<ShoppingList> lists) {
  final far = DateTime.utc(9999);
  return lists.toList()..sort((a, b) => (a.createdAt ?? far).compareTo(b.createdAt ?? far));
}

/// Porównanie nazw produktów bez wielkości liter i zbędnych spacji ("  Mleko " == "mleko").
String normalizeName(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Co zrobić z nowo wpisanym produktem, gdy podobny już jest na liście.
enum AddDecision { add, alreadyOnList, uncheckExisting }

class AddPlan {
  const AddPlan(this.decision, [this.existing]);
  final AddDecision decision;
  final ShoppingItem? existing;
}

AddPlan planAdd(String name, Iterable<ShoppingItem> current) {
  final key = normalizeName(name);
  for (final item in current) {
    if (normalizeName(item.name) == key) {
      return item.checked
          ? AddPlan(AddDecision.uncheckExisting, item)
          : AddPlan(AddDecision.alreadyOnList, item);
    }
  }
  return const AddPlan(AddDecision.add);
}
