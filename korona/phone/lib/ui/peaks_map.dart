import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/climbs.dart';
import '../data/peaks_data.dart';
import '../data/peaks.dart';
import 'format.dart';
import 'widgets.dart';

/// Podkład mapy. Oba bez klucza API; OpenTopoMap ma poziomice i szlaki - lepszy w górach.
enum MapBase {
  topo('Topograficzna', 'https://tile.opentopomap.org/{z}/{x}/{y}.png', 17,
      '© OpenTopoMap (CC-BY-SA), dane © współtwórcy OpenStreetMap', 'https://opentopomap.org/about'),
  osm('OpenStreetMap', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', 19, '© współtwórcy OpenStreetMap',
      'https://www.openstreetmap.org/copyright');

  const MapBase(this.label, this.url, this.maxZoom, this.attribution, this.attributionUrl);

  final String label;
  final String url;
  final int maxZoom;
  final String attribution;
  final String attributionUrl;
}

/// Kafelki z nazwą pakietu jako User-Agent (wymóg zasad korzystania z serwerów OSM)
TileLayer baseTiles(MapBase base) => TileLayer(
      urlTemplate: base.url,
      userAgentPackageName: 'pl.grekot.naszczycie',
      maxNativeZoom: base.maxZoom,
    );

Widget baseAttribution(MapBase base) => RichAttributionWidget(
      showFlutterMapAttribution: false,
      attributions: [
        TextSourceAttribution(base.attribution, onTap: () => launchUrl(Uri.parse(base.attributionUrl))),
      ],
    );

/// Filtr mapy: wszystkie szczyty, jedna grupa albo tylko własne
const _all = '';
const _custom = '#custom';

/// Punkt na mapie: szczyt z listy albo własny
class _Point {
  _Point.peak(Peak this.peak, Climb? climb)
      : custom = null,
        name = peak.name,
        h = peak.h,
        pos = LatLng(peak.lat, peak.lon),
        climbed = climb != null,
        date = climb?.date;

  _Point.custom(CustomPeak this.custom)
      : peak = null,
        name = custom.name,
        h = null,
        pos = LatLng(custom.lat, custom.lon),
        climbed = true,
        date = custom.date;

  final Peak? peak;
  final CustomPeak? custom;
  final String name;
  final int? h;
  final LatLng pos;
  final bool climbed;
  final DateTime? date;

  bool get isCustom => custom != null;
}

/// Mapa szczytów: zdobyte zielone, niezdobyte szare, własne niebieskie.
/// Stuknięcie w szczyt - karta z datą i przejście do szczegółów.
class PeaksMap extends StatefulWidget {
  const PeaksMap({super.key, required this.data, this.groupId});

  final PeaksData data;

  /// Początkowy filtr (np. z ekranu grupy); null = wszystkie
  final String? groupId;

  @override
  State<PeaksMap> createState() => _PeaksMapState();
}

class _PeaksMapState extends State<PeaksMap> {
  final _controller = MapController();
  late String _filter = widget.groupId ?? _all;
  MapBase _base = MapBase.topo;
  bool _ready = false;

  PeaksData get data => widget.data;

  List<_Point> _points() {
    final out = <_Point>[];
    if (_filter != _custom) {
      final peaks = _filter == _all ? data.catalog.peaks : data.catalog.peaksOf(_filter);
      out.addAll(peaks.map((p) => _Point.peak(p, data.climbOf(p.id))));
    }
    if (_filter == _all || _filter == _custom) out.addAll(data.doc.custom.map(_Point.custom));
    // Zdobyte rysowane na wierzchu
    out.sort((a, b) => (a.climbed ? 1 : 0) - (b.climbed ? 1 : 0));
    return out;
  }

  CameraFit _fit(List<_Point> points) {
    if (points.isEmpty) {
      // Polska południowa
      return CameraFit.bounds(bounds: LatLngBounds(const LatLng(49.0, 14.5), const LatLng(51.2, 23.0)));
    }
    if (points.length == 1) {
      final p = points.first.pos;
      return CameraFit.bounds(
        bounds: LatLngBounds(LatLng(p.latitude - 0.02, p.longitude - 0.03), LatLng(p.latitude + 0.02, p.longitude + 0.03)),
      );
    }
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints([for (final p in points) p.pos]),
      padding: const EdgeInsets.fromLTRB(40, 90, 40, 60),
      maxZoom: 13,
    );
  }

  void _setFilter(String f) {
    setState(() => _filter = f);
    if (_ready) _controller.fitCamera(_fit(_points()));
  }

  @override
  Widget build(BuildContext context) {
    final points = _points();
    final climbed = points.where((p) => p.climbed && !p.isCustom).length;
    final custom = points.where((p) => p.isCustom).length;
    final todo = points.length - climbed - custom;
    final theme = Theme.of(context);

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCameraFit: _fit(points),
            maxZoom: 18,
            minZoom: 4,
            onMapReady: () => _ready = true,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            baseTiles(_base),
            MarkerLayer(
              markers: [
                for (final p in points)
                  Marker(
                    point: p.pos,
                    width: 150,
                    height: 52,
                    child: _PeakMarker(point: p, onTap: () => _showPoint(p)),
                  ),
              ],
            ),
            baseAttribution(_base),
          ],
        ),
        // Filtr: wszystkie / grupy / własne
        Positioned(
          left: 0,
          right: 0,
          top: 8,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _chip('Wszystkie', _all),
                for (final g in data.catalog.groups) _chip(g.short, g.id),
                if (data.doc.custom.isNotEmpty) _chip('Własne', _custom),
              ],
            ),
          ),
        ),
        // Legenda
        Positioned(
          left: 8,
          bottom: 28,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: DefaultTextStyle(
                style: theme.textTheme.bodySmall!,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legend(climbedColor, 'zdobyte: $climbed'),
                    _legend(unclimbedColor, 'do zdobycia: $todo'),
                    if (custom > 0) _legend(customColor, 'własne: $custom'),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Podkład
        Positioned(
          right: 8,
          bottom: 28,
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: 'Podkład: ${_base.label}',
            onPressed: () => setState(() => _base = _base == MapBase.topo ? MapBase.osm : MapBase.topo),
            child: Icon(_base == MapBase.topo ? Icons.terrain : Icons.map_outlined),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label),
          selected: _filter == value,
          showCheckmark: false,
          onSelected: (_) => _setFilter(value),
        ),
      );

  Widget _legend(Color color, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(text),
          ],
        ),
      );

  void _showPoint(_Point p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final subtitle = [
          if (p.h != null) formatHeight(p.h),
          if (p.peak != null && p.peak!.range.isNotEmpty) p.peak!.range,
          if (p.isCustom) 'własny szczyt',
        ].join(' · ');
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: theme.textTheme.headlineSmall),
                if (subtitle.isNotEmpty) Text(subtitle, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  p.date != null ? 'Zdobyty ${formatDay(p.date!)}' : 'Jeszcze nie zdobyty',
                  style: theme.textTheme.titleMedium?.copyWith(color: p.climbed ? climbedColor : unclimbedColor),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (p.peak != null) {
                        openPeak(context, data, p.peak!);
                      } else {
                        openCustom(context, data, p.custom!);
                      }
                    },
                    child: const Text('Szczegóły'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Kropka szczytu; nazwa pod spodem dopiero po przybliżeniu (przy setkach szczytów)
class _PeakMarker extends StatelessWidget {
  const _PeakMarker({required this.point, required this.onTap});

  final _Point point;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zoom = MapCamera.of(context).zoom;
    final color = point.isCustom ? customColor : (point.climbed ? climbedColor : unclimbedColor);
    final size = point.climbed ? 16.0 : 12.0;
    final showLabel = zoom >= 11 || (point.climbed && zoom >= 9.5);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: point.climbed ? color : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: point.climbed ? Colors.white : color, width: 2.5),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 2)],
                ),
              ),
            ),
          ),
        ),
        if (showLabel)
          Positioned(
            top: 34,
            child: IgnorePointer(
              child: Text(
                point.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: point.climbed ? FontWeight.bold : FontWeight.w500,
                  color: Colors.black87,
                  shadows: const [
                    Shadow(color: Colors.white, blurRadius: 3),
                    Shadow(color: Colors.white, blurRadius: 3),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
