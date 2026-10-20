import 'package:flutter/material.dart';

import '../data/korona_data.dart';
import '../data/peaks.dart';
import '../data/stats.dart';
import 'format.dart';
import 'peaks_map.dart';
import 'widgets.dart';

enum _Show { all, climbed, todo }

enum _Sort { height, name, date }

/// Lista szczytów jednej grupy: postęp, wyszukiwanie, filtr zdobyte / do zdobycia, warianty
class GroupScreen extends StatefulWidget {
  const GroupScreen({super.key, required this.data, required this.progress});

  final KoronaData data;
  final GroupProgress progress;

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  _Show _show = _Show.all;
  _Sort _sort = _Sort.height;
  String _query = '';

  KoronaData get data => widget.data;
  GroupProgress get progress => widget.progress;

  List<Peak> _filtered(List<Peak> peaks) {
    final q = _fold(_query.trim());
    final out = peaks.where((p) {
      final climbed = data.climbOf(p.id) != null;
      if (_show == _Show.climbed && !climbed) return false;
      if (_show == _Show.todo && climbed) return false;
      return q.isEmpty || _fold(p.name).contains(q) || _fold(p.range).contains(q);
    }).toList();
    switch (_sort) {
      case _Sort.height:
        out.sort(PeakCatalog.byHeight);
      case _Sort.name:
        out.sort((a, b) => _fold(a.name).compareTo(_fold(b.name)));
      case _Sort.date:
        // Najnowsze zdobycia na górze, niezdobyte na końcu od najwyższego
        out.sort((a, b) {
          final da = data.climbOf(a.id)?.date, db = data.climbOf(b.id)?.date;
          if (da == null && db == null) return PeakCatalog.byHeight(a, b);
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final main = _filtered(progress.main);
    final variants = _filtered(progress.variants);
    // Pasmo pokazujemy tylko, gdy grupa ma szczyty z różnych pasm (np. KGP, a nie Tatry)
    final showRange = progress.main.map((p) => p.range).toSet().length > 1;
    final items = <Object>[
      ...main,
      if (variants.isNotEmpty) 'Warianty - rozpoznawane, nie liczą się do ${progress.counted}',
      ...variants,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(progress.group.name),
        actions: [
          IconButton(
            tooltip: 'Mapa grupy',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(progress.group.name)),
                body: PeaksMap(data: data, groupId: progress.group.id),
              ),
            )),
          ),
          PopupMenuButton<_Sort>(
            tooltip: 'Sortuj',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _Sort.height, child: Text('Od najwyższego')),
              PopupMenuItem(value: _Sort.name, child: Text('Alfabetycznie')),
              PopupMenuItem(value: _Sort.date, child: Text('Data zdobycia')),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProgressLine(climbed: progress.climbed, counted: progress.counted, big: true),
                  const SizedBox(height: 12),
                  if (progress.main.length > 12)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Szukaj szczytu',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  SegmentedButton<_Show>(
                    segments: [
                      const ButtonSegment(value: _Show.all, label: Text('Wszystkie')),
                      ButtonSegment(value: _Show.climbed, label: Text('Zdobyte ${progress.climbed}')),
                      ButtonSegment(
                        value: _Show.todo,
                        label: Text('Zostało ${(progress.counted - progress.climbed).clamp(0, 1 << 30)}'),
                      ),
                    ],
                    selected: {_show},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _show = s.first),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          if (items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('Brak szczytów')),
            ),
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text(item, style: Theme.of(context).textTheme.titleSmall),
                );
              }
              return PeakTile(data: data, peak: item as Peak, showRange: showRange);
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${peaksCount(progress.main.length)} w grupie'
                '${progress.group.counted != null && progress.group.counted != progress.main.length ? ', do postępu liczy się ${progress.counted}' : ''}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bez polskich znaków i wielkości liter - „sniezka” znajduje „Śnieżka”
String _fold(String s) {
  const from = 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ';
  const to = 'acelnoszzACELNOSZZ';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase();
}
