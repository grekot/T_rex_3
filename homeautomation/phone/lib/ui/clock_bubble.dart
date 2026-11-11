// Dymki zegara (pkt 10.2 „Dymki i ciekawostki”): okno składania dymku (Set `bubble` - wiadomość z ekranu zegara
// i akcja automatyki) oraz wybór czasu spotkania (Set `meeting`).

import 'package:flutter/material.dart';

import '../models/clock.dart';
import '../models/json_utils.dart';
import 'app_icons.dart';

/// Odpowiedzi proponowane pod polem „Odpowiedź”.
const _replies = ['Idę!', 'OK', 'Za chwilę', 'Dzięki!'];

/// Składa dymek; zwraca obiekt `bubble` albo null (Anuluj). [automation] - pole `id` na wierzchu (do wyzwalacza
/// „Odpowiedź z dymka”), [ids] - id już użyte w automatykach tego zegara.
Future<Json?> showBubbleDialog(
  BuildContext context, {
  Json? initial,
  bool automation = false,
  Set<String> ids = const {},
}) => showDialog<Json>(
  context: context,
  builder: (_) => _BubbleDialog(initial: initial, automation: automation, ids: ids),
);

class _BubbleDialog extends StatefulWidget {
  const _BubbleDialog({this.initial, required this.automation, required this.ids});

  final Json? initial;
  final bool automation;
  final Set<String> ids;

  @override
  State<_BubbleDialog> createState() => _BubbleDialogState();
}

class _BubbleDialogState extends State<_BubbleDialog> {
  late final Json _b = widget.initial ?? const {};
  late final _text = TextEditingController(text: _b['text'] as String? ?? '');
  late final _title = TextEditingController(text: _b['title'] as String? ?? '');
  late final _reply = TextEditingController(text: _b['reply'] as String? ?? '');
  late final _id = TextEditingController(text: _b['id'] as String? ?? '');
  late String _icon = clockBubbleIcons.contains(_b['icon']) ? _b['icon'] as String : 'chat';
  late String? _sound = clockBubbleSounds.containsKey(_b['sound']) ? _b['sound'] as String : null;
  late bool _high = _b['prio'] == 'high';
  late int _ttl = (_b['ttlS'] as num?)?.toInt() ?? 60;
  late int _wait = (_b['waitMin'] as num?)?.toInt() ?? 30;
  bool _tried = false;

  @override
  void dispose() {
    _text.dispose();
    _title.dispose();
    _reply.dispose();
    _id.dispose();
    super.dispose();
  }

  String? get _idError => _id.text.trim().isEmpty ? null : clockBubbleIdError(_id.text.trim());

  bool get _valid =>
      clockBubbleTextError(_text.text) == null &&
      clockBubbleTitleError(_title.text.trim()) == null &&
      clockBubbleReplyError(_reply.text.trim()) == null &&
      _idError == null;

  void _save() {
    if (!_valid) {
      setState(() => _tried = true);
      return;
    }
    final title = _title.text.trim(), reply = _reply.text.trim(), id = _id.text.trim();
    Navigator.pop(context, <String, dynamic>{
      'text': _text.text.trim(),
      if (title.isNotEmpty) 'title': title,
      if (_icon != 'chat') 'icon': _icon,
      if (_sound != null) 'sound': _sound,
      if (_ttl != 60) 'ttlS': _ttl,
      if (_wait != 30) 'waitMin': _wait,
      if (reply.isNotEmpty) 'reply': reply,
      if (_high) 'prio': 'high',
      if (id.isNotEmpty) 'id': id,
    });
  }

  Widget _idField() => TextField(
    key: const Key('bubbleId'),
    controller: _id,
    decoration: InputDecoration(
      labelText: 'Id dymku (opcjonalnie)',
      hintText: 'np. obiad',
      helperText: widget.automation ? 'Ten sam id podmienia treść; po nim rozpoznasz odpowiedź' : null,
      errorText: _tried ? _idError : null,
    ),
    onChanged: (_) => setState(() {}),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.automation ? 'Dymek na zegarze' : 'Wiadomość na zegar'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('bubbleText'),
              controller: _text,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Treść',
                hintText: 'np. Obiad gotowy!',
                errorText: _tried ? clockBubbleTextError(_text.text) : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: const Key('bubbleTitle'),
              controller: _title,
              decoration: InputDecoration(
                labelText: 'Tytuł (opcjonalnie)',
                errorText: _tried ? clockBubbleTitleError(_title.text.trim()) : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Text('Ikona', style: t.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final k in clockBubbleIcons)
                  ChoiceChip(
                    key: Key('bubbleIcon-$k'),
                    tooltip: appIcon(k)?.label ?? k,
                    label: Icon(appIcon(k)?.icon ?? Icons.chat_bubble_outline, size: 20),
                    selected: _icon == k,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _icon = k),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('bubbleReply'),
              controller: _reply,
              decoration: InputDecoration(
                labelText: 'Odpowiedź środkowym przyciskiem (opcjonalnie)',
                errorText: _tried ? clockBubbleReplyError(_reply.text.trim()) : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final r in _replies) ActionChip(label: Text(r), onPressed: () => setState(() => _reply.text = r)),
              ],
            ),
            if (widget.automation) ...[
              _idField(),
              if (widget.ids.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final id in widget.ids)
                      ActionChip(label: Text(id), onPressed: () => setState(() => _id.text = id)),
                  ],
                ),
            ],
            SwitchListTile(
              key: const Key('bubbleHigh'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Ważny'),
              subtitle: const Text('Także w czasie spotkania, kolor alarmowy, domyślnie dźwięk alarmu'),
              value: _high,
              onChanged: (v) => setState(() => _high = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dźwięk'),
              trailing: DropdownButton<String?>(
                key: const Key('bubbleSound'),
                value: _sound,
                items: [
                  DropdownMenuItem(value: null, child: Text(_high ? 'domyślny (alarm)' : 'domyślny (dzwonek)')),
                  for (final MapEntry(key: k, value: l) in clockBubbleSounds.entries)
                    DropdownMenuItem(value: k, child: Text(l)),
                ],
                onChanged: (v) => setState(() => _sound = v),
              ),
            ),
            ExpansionTile(
              key: const Key('bubbleMore'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Więcej'),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Na ekranie'),
                  trailing: DropdownButton<int>(
                    key: const Key('bubbleTtl'),
                    value: _ttl,
                    items: [
                      for (final v in {15, 30, 60, 120, 300, 600, 1800, 3600, _ttl})
                        DropdownMenuItem(value: v, child: Text(v < 60 ? '$v s' : '${v ~/ 60} min')),
                    ],
                    onChanged: (v) => setState(() => _ttl = v ?? 60),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Czeka (noc, spotkanie)'),
                  trailing: DropdownButton<int>(
                    key: const Key('bubbleWait'),
                    value: _wait,
                    items: [
                      for (final v in {0, 5, 15, 30, 60, 120, 240, 720, _wait})
                        DropdownMenuItem(
                          value: v,
                          child: Text(v == 0 ? 'tylko teraz' : (v < 60 ? '$v min' : '${v ~/ 60} h')),
                        ),
                    ],
                    onChanged: (v) => setState(() => _wait = v ?? 30),
                  ),
                ),
                if (!widget.automation) _idField(),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          key: const Key('bubbleSend'),
          onPressed: _save,
          child: Text(widget.automation ? 'Gotowe' : 'Wyślij'),
        ),
      ],
    );
  }
}

/// Czas spotkania: liczba minut albo `true` (do wyłączenia); null = Anuluj.
Future<Object?> showMeetingDialog(BuildContext context) => showDialog<Object>(
  context: context,
  builder: (ctx) => SimpleDialog(
    title: const Text('Spotkanie'),
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Text('Zwykłe dymki czekają, ciekawostki przepadają, radio się wycisza.'),
      ),
      for (final m in clockMeetingMinutes)
        SimpleDialogOption(
          key: Key('meeting-$m'),
          onPressed: () => Navigator.pop(ctx, m),
          child: Text(m < 60 ? '$m min' : (m % 60 == 0 ? '${m ~/ 60} h' : '${m ~/ 60} h ${m % 60} min')),
        ),
      SimpleDialogOption(
        key: const Key('meeting-on'),
        onPressed: () => Navigator.pop(ctx, true),
        child: const Text('Do wyłączenia'),
      ),
    ],
  ),
);
