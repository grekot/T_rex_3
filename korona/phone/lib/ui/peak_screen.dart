import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/climbs.dart';
import '../data/korona_data.dart';
import '../data/peaks.dart';
import 'format.dart';
import 'peaks_map.dart';
import 'widgets.dart';

/// Szczegóły szczytu z listy ([peak]) albo własnego, dodanego na zegarku ([custom])
class PeakScreen extends StatelessWidget {
  const PeakScreen({super.key, required this.data, this.peak, this.custom})
      : assert((peak == null) != (custom == null));

  final KoronaData data;
  final Peak? peak;
  final CustomPeak? custom;

  String get _name => peak?.name ?? custom!.name;
  double get _lat => peak?.lat ?? custom!.lat;
  double get _lon => peak?.lon ?? custom!.lon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = peak;
    final climb = p == null ? null : data.climbOf(p.id);
    final date = climb?.date ?? custom?.date;
    final gps = climb?.gps ?? custom?.gps ?? false;
    final base = p == null ? null : data.catalog.byId[p.variantOf];
    final variants = p == null ? const <Peak>[] : data.catalog.variantsOf(p.id);
    final subtitle = [
      if (p != null) '${formatHeight(p.h)} n.p.m.',
      if (p != null && p.range.isNotEmpty) p.range,
      ?p?.wikiNote,
      if (custom != null) 'Własny szczyt, dodany na zegarku',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: Text(_name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name, style: theme.textTheme.headlineMedium),
                if (subtitle.isNotEmpty) Text(subtitle, style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: date != null ? climbedColor.withValues(alpha: 0.12) : null,
            child: ListTile(
              leading: ClimbDot(climbed: date != null, custom: custom != null),
              title: Text(date != null ? 'Zdobyty ${formatDay(date)}' : 'Jeszcze nie zdobyty'),
              subtitle: Text(date == null
                  ? 'Otwórz Koronę na zegarku na wierzchołku - zaliczy go po GPS'
                  : (gps ? 'Zaliczony na szczycie (GPS)' : 'Dodany ręcznie z datą')),
              trailing: date != null ? GpsIcon(gps: gps, size: 22) : null,
            ),
          ),
          if (p != null && p.groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in p.groups)
                    if (data.catalog.group(g) case final group?) Chip(label: Text(group.name)),
                ],
              ),
            ),
          if (base != null)
            _Info(
              icon: Icons.alt_route,
              text: 'Wariant szczytu ${base.name} - zegarek go rozpoznaje i zapisuje, '
                  'ale do postępu liczy się ${base.name}.',
              onTap: () => openPeak(context, data, base),
            ),
          if (p?.border == true) const _Info(icon: Icons.flag_outlined, text: 'Wierzchołek na granicy państwa'),
          if (p?.note case final note? when note.isNotEmpty) _Info(icon: Icons.info_outline, text: note),
          for (final v in variants)
            _Info(
              icon: Icons.alt_route,
              text: 'Wariant: ${v.name} (${formatHeight(v.h)})'
                  '${data.climbOf(v.id) != null ? ' - zdobyty ${formatShortDay(data.climbOf(v.id)!.date)}' : ''}',
              onTap: () => openPeak(context, data, v),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(height: 240, child: _MiniMap(lat: _lat, lon: _lon, climbed: date != null)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(formatLatLon(_lat, _lon), style: theme.textTheme.bodySmall),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.hiking),
            title: const Text('Szlaki w Mapy.com'),
            onTap: () => _open('https://mapy.com/turisticka?x=$_lon&y=$_lat&z=15&source=coor&id=$_lon%2C$_lat'),
          ),
          ListTile(
            leading: const Icon(Icons.directions),
            title: const Text('Dojazd w Google Maps'),
            onTap: () => _open('https://www.google.com/maps/dir/?api=1&destination=$_lat,$_lon'),
          ),
          if (p?.wiki case final wiki? when wiki.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Wikipedia'),
              onTap: () => _open('https://pl.wikipedia.org/wiki/${Uri.encodeComponent(wiki.replaceAll(' ', '_'))}'),
            ),
          if (p?.osm case final osm?)
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Wierzchołek w OpenStreetMap'),
              onTap: () => _open('https://www.openstreetmap.org/node/$osm'),
            ),
        ],
      ),
    );
  }

  static Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text, this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(text),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.lat, required this.lon, required this.climbed});

  final double lat;
  final double lon;
  final bool climbed;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lon);
    final color = climbed ? climbedColor : unclimbedColor;
    return FlutterMap(
      options: MapOptions(
        initialCenter: point,
        initialZoom: 13,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag),
      ),
      children: [
        baseTiles(MapBase.topo),
        MarkerLayer(markers: [
          Marker(
            point: point,
            width: 36,
            height: 36,
            alignment: Alignment.topCenter,
            child: Icon(Icons.location_on, color: color, size: 36, shadows: const [Shadow(blurRadius: 3)]),
          ),
        ]),
        baseAttribution(MapBase.topo),
      ],
    );
  }
}
