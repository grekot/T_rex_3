// Kalendarz domu (pkt 11): wywóz śmieci, urodziny i ważne daty rodziny w `homes/{h}/calendar`. Lista po najbliższym
// terminie, edycja z wieloma datami naraz (harmonogram gminy) i „przypomnij dzień wcześniej” (powiadomienie z huba).

import 'package:flutter/material.dart';

import '../data/calendar_store.dart';
import '../models/calendar.dart';
import '../models/dashboard.dart' show newLocalId;
import '../models/output_schedule.dart' show dayShort;
import 'widgets.dart' show listPadding;

String _dm(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

String _dmy(DateTime d) => '${_dm(d)}.${d.year}';

/// „dziś”, „jutro”, „za 3 dni”, „pt 12.11”.
String _when(DateTime d, DateTime today) {
  final n = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  return switch (n) {
    0 => 'dziś',
    1 => 'jutro',
    < 7 => 'za $n dni · ${dayShort(d.weekday).toLowerCase()} ${_dm(d)}',
    _ => '${dayShort(d.weekday).toLowerCase()} ${_dm(d)}${d.year == today.year ? '' : '.${d.year}'}',
  };
}

IconData calendarIcon(CalendarEntry e) => switch (e.kind) {
  CalendarKind.waste => switch (e.icon) {
    'glass' => Icons.wine_bar_outlined,
    'paper' => Icons.description_outlined,
    'bio' => Icons.eco_outlined,
    'bulky' => Icons.chair_outlined,
    'plastic' => Icons.recycling,
    _ => Icons.delete_outline,
  },
  CalendarKind.birthday => Icons.cake_outlined,
  CalendarKind.date => Icons.event_outlined,
};

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key, required this.store, this.clock = DateTime.now});

  final CalendarStore store;
  final DateTime Function() clock;

  Future<void> _edit(BuildContext context, [CalendarEntry? e]) async {
    final r = await Navigator.of(context).push<_EditResult>(
      MaterialPageRoute(
        builder: (_) => CalendarEditScreen(initial: e, clock: clock),
      ),
    );
    if (r == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (r.delete) {
        await store.remove(r.entry.id);
      } else {
        await store.save(r.entry);
      }
    } on Object catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('Nie udało się zapisać w chmurze ($err).')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kalendarz domu')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('calAdd'),
        icon: const Icon(Icons.add),
        label: const Text('Dodaj'),
        onPressed: () => _edit(context),
      ),
      body: StreamBuilder<List<CalendarEntry>>(
        stream: store.watch(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Nie udało się wczytać kalendarza (${snap.error}).', textAlign: TextAlign.center),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final today = clock();
          final items = [for (final e in snap.data!) (e: e, next: e.next(today))]
            ..sort((a, b) {
              if (a.next == null || b.next == null) return a.next == null ? (b.next == null ? 0 : 1) : -1;
              return a.next!.compareTo(b.next!);
            });
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Wywóz śmieci, urodziny i ważne daty domu. Hub przypomni dzień wcześniej, a zegarek pokaże '
                  'najbliższe wpisy.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: listPadding(context, const EdgeInsets.only(bottom: 88)),
            children: [
              for (final (:e, :next) in items)
                ListTile(
                  key: Key('cal-${e.id}'),
                  leading: Icon(calendarIcon(e)),
                  title: Text(e.title),
                  subtitle: Text(_subtitle(e, next, today)),
                  trailing: e.notify ? const Icon(Icons.notifications_active_outlined, size: 20) : null,
                  onTap: () => _edit(context, e),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _subtitle(CalendarEntry e, DateTime? next, DateTime today) {
    if (next == null) return e.dates.isEmpty ? 'minęło' : 'wszystkie daty minęły';
    final age = e.ageOn(next);
    final more = e.dates.where((d) => d.isAfter(next)).length;
    return [
      _when(next, today),
      if (age != null) 'kończy $age ${_years(age)}',
      if (e.dates.isNotEmpty && more > 0) 'potem jeszcze $more',
      if (e.dates.isEmpty && e.kind == CalendarKind.date && e.repeat != 'none') calendarRepeats[e.repeat]!,
    ].join(' · ');
  }

  static String _years(int n) {
    if (n == 1) return 'rok';
    final last = n % 10, last2 = n % 100;
    return last >= 2 && last <= 4 && (last2 < 12 || last2 > 14) ? 'lata' : 'lat';
  }
}

typedef _EditResult = ({CalendarEntry entry, bool delete});

/// Wpis kalendarza: rodzaj, nazwa, ikona wywozu, daty (lista albo jedna z powtarzaniem), przypomnienie.
class CalendarEditScreen extends StatefulWidget {
  const CalendarEditScreen({super.key, this.initial, this.clock = DateTime.now});

  final CalendarEntry? initial;
  final DateTime Function() clock;

  @override
  State<CalendarEditScreen> createState() => _CalendarEditScreenState();
}

class _CalendarEditScreenState extends State<CalendarEditScreen> {
  late CalendarEntry _e =
      widget.initial ?? CalendarEntry(id: newLocalId('c'), title: '', kind: CalendarKind.waste, notify: true);
  late final _title = TextEditingController(text: _e.title);
  List<String> _problems = const [];

  bool get _isNew => widget.initial == null;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _set(CalendarEntry e) => setState(() {
    _e = e;
    _problems = const [];
  });

  Future<DateTime?> _pick(DateTime? initial, {bool past = false}) {
    final today = widget.clock();
    return showDatePicker(
      context: context,
      initialDate: initial ?? today,
      firstDate: past ? DateTime(1900) : DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5, 12, 31),
    );
  }

  Future<void> _addDate() async {
    final d = await _pick(_e.dates.lastOrNull?.add(const Duration(days: 14)));
    if (d != null) _set(_e.copyWith(dates: ({..._e.dates, d}.toList()..sort())));
  }

  /// Kilka dat naraz - wklejony harmonogram gminy.
  Future<void> _paste() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _PasteDialog());
    if (text == null || !mounted) return;
    final r = parseDateList(text, widget.clock());
    _set(_e.copyWith(dates: ({..._e.dates, ...r.dates}.toList()..sort())));
    if (r.bad.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nie rozpoznano: ${r.bad.join(', ')}')));
    }
  }

  void _save() {
    final e = _e.copyWith(title: _title.text.trim());
    final p = e.problems();
    if (p.isNotEmpty) {
      setState(() => _problems = p);
      return;
    }
    Navigator.pop(context, (entry: e, delete: false));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = widget.clock();
    final past = _e.dates.where((d) => d.isBefore(DateTime(today.year, today.month, today.day))).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nowy wpis' : 'Wpis kalendarza'),
        actions: [
          if (!_isNew)
            IconButton(
              key: const Key('calDelete'),
              tooltip: 'Usuń',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.pop(context, (entry: _e, delete: true)),
            ),
          TextButton(key: const Key('calSave'), onPressed: _save, child: const Text('Zapisz')),
        ],
      ),
      body: ListView(
        padding: listPadding(context, const EdgeInsets.all(16)),
        children: [
          if (_isNew) ...[
            SegmentedButton<CalendarKind>(
              showSelectedIcon: false,
              segments: [for (final k in CalendarKind.values) ButtonSegment(value: k, label: Text(k.label))],
              selected: {_e.kind},
              onSelectionChanged: (v) => _set(_e.copyWith(kind: v.single)),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            key: const Key('calTitle'),
            controller: _title,
            maxLength: calendarMaxTitle,
            decoration: InputDecoration(
              labelText: switch (_e.kind) {
                CalendarKind.waste => 'Nazwa (np. Plastik)',
                CalendarKind.birthday => 'Czyje urodziny',
                CalendarKind.date => 'Nazwa',
              },
            ),
          ),
          if (_e.kind == CalendarKind.waste) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final MapEntry(key: k, value: label) in wasteIcons.entries)
                  ChoiceChip(
                    key: Key('calIcon-$k'),
                    avatar: Icon(calendarIcon(_e.copyWith(icon: k)), size: 18),
                    label: Text(label),
                    selected: _e.icon == k,
                    onSelected: (on) {
                      if (on && _title.text.trim().isEmpty) _title.text = label;
                      _set(on ? _e.copyWith(icon: k) : _e.copyWith(clearIcon: true));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Daty wywozu (${_e.dates.length}/$calendarMaxDates)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final d in _e.dates)
                  InputChip(
                    key: Key('calDate-${calendarDate(d)}'),
                    label: Text(d.year == today.year ? _dm(d) : _dmy(d)),
                    onDeleted: () => _set(_e.copyWith(dates: [..._e.dates]..remove(d))),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: const Key('calAddDate'),
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('Dodaj datę'),
                  onPressed: _addDate,
                ),
                TextButton.icon(
                  key: const Key('calPaste'),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Wiele dat naraz'),
                  onPressed: _paste,
                ),
                if (past > 0)
                  TextButton.icon(
                    key: const Key('calDropPast'),
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: Text('Usuń minione ($past)'),
                    onPressed: () => _set(
                      _e.copyWith(
                        dates: [
                          for (final d in _e.dates)
                            if (!d.isBefore(DateTime(today.year, today.month, today.day))) d,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ] else ...[
            ListTile(
              key: const Key('calDate'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                _e.date == null
                    ? (_e.kind == CalendarKind.birthday ? 'Data urodzenia' : 'Wybierz datę')
                    : _dmy(_e.date!),
              ),
              subtitle: _e.kind == CalendarKind.birthday && _e.date != null
                  ? Text('Wiek liczony z roku urodzenia (${_e.ageOn(today) ?? 0} teraz)')
                  : null,
              onTap: () async {
                final d = await _pick(_e.date, past: true);
                if (d != null) _set(_e.copyWith(date: d));
              },
            ),
            if (_e.kind == CalendarKind.date)
              DropdownButtonFormField<String>(
                key: const Key('calRepeat'),
                initialValue: _e.repeat,
                decoration: const InputDecoration(labelText: 'Powtarzanie'),
                items: [
                  for (final MapEntry(key: k, value: v) in calendarRepeats.entries)
                    DropdownMenuItem(value: k, child: Text(v)),
                ],
                onChanged: (v) => _set(_e.copyWith(repeat: v)),
              ),
          ],
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('calNotify'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Przypomnij dzień wcześniej'),
            subtitle: const Text('Powiadomienie od huba o godzinie z ustawień huba (domyślnie 19:00)'),
            value: _e.notify,
            onChanged: (v) => _set(_e.copyWith(notify: v)),
          ),
          for (final p in _problems)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                p,
                key: const Key('calProblem'),
                style: TextStyle(color: cs.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wiele dat naraz (harmonogram gminy) - tekst do [parseDateList].
class _PasteDialog extends StatefulWidget {
  const _PasteDialog();

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Wiele dat naraz'),
    content: TextField(
      key: const Key('calPasteText'),
      controller: _ctl,
      autofocus: true,
      maxLines: 6,
      decoration: const InputDecoration(
        hintText: '12.11, 26.11, 10.12\nalbo: 7 stycznia, 21 stycznia 2027',
        helperText: 'Oddziel przecinkami albo nowymi wierszami. Bez roku - najbliższa data.',
        helperMaxLines: 2,
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
      FilledButton(
        key: const Key('calPasteOk'),
        onPressed: () => Navigator.pop(context, _ctl.text),
        child: const Text('Dodaj'),
      ),
    ],
  );
}
