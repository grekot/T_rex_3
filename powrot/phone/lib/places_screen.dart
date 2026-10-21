import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wspolne/wspolne.dart';

import 'compass_screen.dart';
import 'gpx.dart';
import 'models.dart';
import 'repository.dart';

/// Miejsca zapisane na zegarku w aplikacji Powrót (moje i udostępnione mi):
/// kompas na azymut, nawigacja w Google Maps, plik GPX do zegarka, udostępnianie znajomym.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key, required this.repo});

  final PlacesRepository repo;

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  late final Stream<List<Place>> _places = widget.repo.watchPlaces();
  ({double lat, double lon})? _here;

  PlacesRepository get repo => widget.repo;

  @override
  void initState() {
    super.initState();
    _locate(ask: false);
    // Wpis w książce adresowej - dzięki niemu inni mogą dodać mnie do znajomych po e-mailu
    repo.registerEmail().catchError((_) {});
  }

  /// Moja pozycja (do odległości i do pliku GPX). [ask] - czy pytać o zgodę.
  Future<({double lat, double lon})?> _locate({required bool ask}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return _here;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && ask) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return _here;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) setState(() => _here = (lat: last.latitude, lon: last.longitude));
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (mounted) setState(() => _here = (lat: p.latitude, lon: p.longitude));
    } catch (_) {
      // brak zgody, wyłączona lokalizacja, przekroczony czas - działamy bez pozycji
    }
    return _here;
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _navigate(Place p, {bool driving = false}) async {
    final ok = await launchUrl(mapsDirectionsUri(p.lat, p.lon, driving: driving), mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack('Nie udało się otworzyć Google Maps');
  }

  /// Strzałka do celu na azymut - w terenie bez dróg
  Future<void> _compass(Place p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CompassScreen(place: p)));
    _locate(ask: false); // po marszu odległości na liście są nieaktualne
  }

  Future<void> _sendLocation(Place p) async {
    await SharePlus.instance.share(ShareParams(
      text: '${p.name}: ${mapsPlaceUri(p.lat, p.lon)}',
      subject: p.name,
    ));
  }

  /// Plik GPX (trasa od mojej pozycji do miejsca) -> menu udostępniania -> Zepp
  Future<void> _sendGpx(Place p) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trasa na zegarek'),
        content: const Text(
          '1. W menu udostępniania wybierz aplikację Zepp (jeśli jej nie ma – „Zapisz w Plikach”, '
          'a potem otwórz plik .gpx w Zepp).\n'
          '2. W Zepp: zapisz trasę i wyślij ją do zegarka.\n'
          '3. Na zegarku: Trening → np. Spacer → Nawigacja → Moje trasy → ta trasa.\n\n'
          'Trasa prowadzi w linii prostej od Twojej obecnej pozycji do miejsca – na mapie zegarka '
          'widać cel na tle ulic i ścieżek.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Dalej')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final from = await _locate(ask: true);
    if (from == null && mounted) _snack('Bez Twojej pozycji plik zawiera tylko punkt docelowy');
    final gpx = buildGpx(name: p.name, lat: p.lat, lon: p.lon, from: from);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${gpxFileName(p.name)}');
    await file.writeAsString(gpx);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/gpx+xml')],
      subject: 'Trasa: ${p.name}',
    ));
  }

  Future<void> _rename(Place p) async {
    final name = await askForName(context, title: 'Zmień nazwę', initial: p.name, maxLength: 40);
    if (name == null || name == p.name) return;
    await repo.renamePlace(p.id, name.length > 40 ? name.substring(0, 40) : name);
  }

  Future<void> _remove(Place p) async {
    final owner = p.isOwner(repo.uid);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(owner ? 'Usunąć „${p.name}”?' : 'Usunąć „${p.name}” u siebie?'),
        content: Text(owner
            ? (p.isShared ? 'Miejsce zniknie też u osób, którym je udostępniono.' : 'Miejsce zniknie też z zegarka.')
            : 'Pozostali nadal będą je widzieć.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok != true) return;
    if (owner) {
      await repo.deletePlace(p.id);
    } else {
      await repo.leavePlace(p.id);
    }
  }

  void _actions(Place p) {
    final owner = p.isOwner(repo.uid);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        void run(Future<void> Function() f) {
          Navigator.pop(ctx);
          f();
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(p.name, style: Theme.of(ctx).textTheme.titleMedium)),
              ListTile(
                leading: const Icon(Icons.explore_outlined),
                title: const Text('Kompas – na azymut'),
                subtitle: const Text('Strzałka do celu, w terenie bez dróg'),
                onTap: () => run(() => _compass(p)),
              ),
              ListTile(
                leading: const Icon(Icons.directions_walk),
                title: const Text('Nawiguj pieszo (Google Maps)'),
                onTap: () => run(() => _navigate(p)),
              ),
              ListTile(
                leading: const Icon(Icons.directions_car),
                title: const Text('Nawiguj autem (Google Maps)'),
                onTap: () => run(() => _navigate(p, driving: true)),
              ),
              ListTile(
                leading: const Icon(Icons.watch),
                title: const Text('Trasa na zegarek (plik GPX)'),
                subtitle: const Text('Nawigacja po mapie T-Rexa'),
                onTap: () => run(() => _sendGpx(p)),
              ),
              ListTile(
                leading: const Icon(Icons.group_add_outlined),
                title: const Text('Udostępnij znajomym'),
                onTap: () => run(() => showShareSheet(context, repo, p, collection: 'places')),
              ),
              ListTile(
                leading: const Icon(Icons.send_outlined),
                title: const Text('Wyślij link do lokalizacji'),
                onTap: () => run(() => _sendLocation(p)),
              ),
              if (owner)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Zmień nazwę'),
                  onTap: () => run(() => _rename(p)),
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(owner ? 'Usuń' : 'Usuń u mnie'),
                onTap: () => run(() => _remove(p)),
              ),
            ],
          ),
        );
      },
    );
  }

  String _subtitle(Place p) {
    final parts = <String>[];
    if (p.savedAt != null) parts.add(_when(p.savedAt!));
    final here = _here;
    if (here != null) parts.add('${formatDistance(distanceMeters(here.lat, here.lon, p.lat, p.lon))} stąd');
    if (!p.isOwner(repo.uid)) {
      parts.add(p.ownerEmail.isNotEmpty ? 'od: ${p.ownerEmail}' : 'udostępnione Tobie');
    } else if (p.isShared) {
      parts.add('wspólne (${p.members.length} os.)');
    }
    return parts.join(' · ');
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}';
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
    if (days == 0) return 'dziś $time';
    if (days == 1) return 'wczoraj $time';
    return '${two(t.day)}.${two(t.month)} $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Powrót – miejsca'),
        actions: [
          IconButton(
            tooltip: 'Odśwież moją pozycję',
            icon: const Icon(Icons.my_location),
            onPressed: () => _locate(ask: true),
          ),
          IconButton(
            tooltip: 'Znajomi',
            icon: const Icon(Icons.group_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FriendsScreen(repo: repo, sharedItems: repo.watchPlaces())),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') FirebaseAuth.instance.signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(repo.email)),
              const PopupMenuItem(value: 'logout', child: Text('Wyloguj')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<List<Place>>(
        stream: _places,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Błąd: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final places = snapshot.data!;
          if (places.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Brak miejsc.\n\nZapisz miejsce na zegarku w aplikacji Powrót – po zalogowaniu się w niej '
                  '(ustawienia w Zepp) tym samym kontem pojawi się tutaj.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            itemCount: places.length,
            itemBuilder: (context, i) {
              final p = places[i];
              return Card(
                child: ListTile(
                  leading: Icon(p.isShared ? Icons.people_alt_outlined : Icons.place_outlined),
                  title: Text(p.name),
                  subtitle: Text(_subtitle(p)),
                  onTap: () => _actions(p),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Kompas – na azymut',
                        icon: const Icon(Icons.explore_outlined),
                        onPressed: () => _compass(p),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Nawiguj pieszo',
                        icon: const Icon(Icons.directions_walk),
                        onPressed: () => _navigate(p),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
