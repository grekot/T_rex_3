// Wydania firmware (kontrakt pkt 3e): manifest na Firebase Hosting, porównanie z `fw` / `fwId` urządzeń,
// aktualizacje węzłów przez hub (`GET hub/api/updates`).

import 'json_utils.dart';

const firmwareManifestUrl = 'https://ha-firmware.web.app/manifest.json';

/// Adres, który urządzenie przyjmie z chmury (`HOMENODE_FW_URL_PREFIX`, pkt 3e).
const firmwareUrlPrefix = 'https://ha-firmware.web.app/fw/';

/// Porównanie wersji `X.Y.Z` (brakujące części = 0; przyrostek po `-` / `+` pomijany, np. `2.1.0-fake`).
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.trim().split(RegExp(r'[-+]')).first.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Jedno wydanie z manifestu (`fw.<fwId>`).
class FirmwareRelease {
  const FirmwareRelease({
    required this.fwId,
    required this.version,
    required this.url,
    required this.sha256,
    this.size = 0,
    this.minVersion,
    this.intermediate,
    this.notes,
    this.date,
  });

  final String fwId;
  final String version;
  final String url;
  final String sha256;
  final int size;

  /// Starsze urządzenie najpierw aktualizuje się do tej wersji (wersja pośrednia).
  final String? minVersion;

  /// Plik wersji pośredniej (przy `minVersion` zawsze, pkt 3e): najwyższa wersja z [minVersion, wydanie).
  final FirmwareRelease? intermediate;
  final String? notes;
  final String? date;

  /// Wpis, który urządzenie przyjmie: HTTPS z [firmwareUrlPrefix] i suma SHA-256 (64 hex).
  bool get valid => url.startsWith(firmwareUrlPrefix) && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256);

  /// Set „Aktualizuj” (pkt 3a / 3e).
  Json get setJson => {'firmwareUrl': url, 'firmwareSha256': sha256};

  factory FirmwareRelease.fromJson(String fwId, Json j) => FirmwareRelease(
    fwId: fwId,
    version: asString(j['version'], 'version'),
    url: asString(j['url'], 'url'),
    sha256: asString(j['sha256'], 'sha256'),
    size: asInt(j['size'], 'size'),
    minVersion: asStringOrNull(j['minVersion'], 'minVersion'),
    intermediate: switch (asObjectOrNull(j['intermediate'], 'intermediate')) {
      final Json i => FirmwareRelease.fromJson(fwId, i),
      null => null,
    },
    notes: asStringOrNull(j['notes'], 'notes'),
    date: asStringOrNull(j['date'], 'date'),
  );
}

class FirmwareManifest {
  const FirmwareManifest({this.generated, this.releases = const {}});

  final String? generated;
  final Map<String, FirmwareRelease> releases;

  /// Wpisy niepełne albo z adresem spoza [firmwareUrlPrefix] są pomijane (urządzenie i tak by je odrzuciło).
  factory FirmwareManifest.fromJson(Json j) {
    final v = asInt(j['v'], 'v', 1);
    if (v != 1) throw FormatException('Nieznana wersja manifestu: $v');
    final fw = asObjectOrNull(j['fw'], 'fw') ?? const {};
    final releases = <String, FirmwareRelease>{};
    for (final e in fw.entries) {
      if (e.value is! Map) continue;
      try {
        final r = FirmwareRelease.fromJson(e.key, (e.value as Map).cast<String, dynamic>());
        if (r.valid && r.version.isNotEmpty) releases[e.key] = r;
      } on FormatException {
        // zły wpis jednego wariantu nie psuje reszty
      }
    }
    return FirmwareManifest(generated: asStringOrNull(j['generated'], 'generated'), releases: releases);
  }
}

enum UpdateStatus {
  /// Urządzenie nie podaje `fwId` (starszy firmware) - nie wiadomo, który plik pasuje.
  unknown,

  /// W manifeście nie ma wydania dla tego `fwId`.
  noRelease,
  upToDate,
  available,

  /// Wydanie wymaga wersji pośredniej (`minVersion`), a manifest nie podaje jej pliku.
  needsIntermediate,
}

class UpdateCheck {
  const UpdateCheck(this.status, {this.release, FirmwareRelease? step}) : _step = step;

  final UpdateStatus status;

  /// Najnowsze wydanie.
  final FirmwareRelease? release;
  final FirmwareRelease? _step;

  /// Co zainstalować teraz: wersję pośrednią (pierwszy z dwóch kroków) albo [release].
  FirmwareRelease? get step => _step ?? release;

  bool get twoSteps => _step != null && _step.version != release?.version;

  bool get canUpdate => status == UpdateStatus.available;
}

UpdateCheck checkUpdate(FirmwareManifest m, {required String? fw, required String? fwId}) {
  if (fwId == null || fwId.isEmpty || fw == null || fw.isEmpty) return const UpdateCheck(UpdateStatus.unknown);
  final r = m.releases[fwId];
  if (r == null) return const UpdateCheck(UpdateStatus.noRelease);
  if (compareVersions(fw, r.version) >= 0) return UpdateCheck(UpdateStatus.upToDate, release: r);
  final min = r.minVersion;
  if (min != null && compareVersions(fw, min) < 0) {
    final i = r.intermediate;
    if (i == null || !i.valid || compareVersions(fw, i.version) >= 0) {
      return UpdateCheck(UpdateStatus.needsIntermediate, release: r);
    }
    return UpdateCheck(UpdateStatus.available, release: r, step: i);
  }
  return UpdateCheck(UpdateStatus.available, release: r);
}

/// Stan aktualizacji węzła w hubie.
enum HubUpdateState {
  idle,
  queued,
  updating,
  observing,
  done,
  failed;

  static HubUpdateState fromWire(Object? v) => values.firstWhere((s) => s.name == v, orElse: () => idle);

  String get label => switch (this) {
    idle => '',
    queued => 'w kolejce',
    updating => 'aktualizuje się',
    observing => 'obserwacja (10 min)',
    done => 'zaktualizowane',
    failed => 'nieudane',
  };

  bool get busy => this == queued || this == updating || this == observing;
}

/// Wpis `GET hub/api/updates` → `devices[]`.
class HubUpdateEntry {
  const HubUpdateEntry({
    required this.id,
    this.fwId,
    this.current,
    this.available,
    this.next,
    this.ready = false,
    this.state = HubUpdateState.idle,
    this.error,
  });

  final String id;
  final String? fwId;
  final String? current;
  final String? available;

  /// Wersja, którą zainstaluje najbliższe zatwierdzenie (`available` albo pośrednia); null = nic do zrobienia.
  final String? next;

  /// Hub ma już plik [next] u siebie.
  final bool ready;
  final HubUpdateState state;
  final String? error;

  bool get hasUpdate => next != null;

  /// Po [next] będzie jeszcze drugi krok (wersja pośrednia).
  bool get twoSteps => next != null && available != null && next != available;

  bool get selectable => hasUpdate && ready && !state.busy;

  /// Kod błędu huba po polsku.
  String? get errorLabel => switch (error) {
    null => null,
    'needs_intermediate' => 'brak pliku wersji pośredniej',
    'not_ready' => 'hub nie pobrał jeszcze pliku',
    'sha256' => 'suma pliku się nie zgadza',
    'crash' => 'nowa wersja się zawieszała - węzeł wrócił do poprzedniej',
    'boot' => 'nowa wersja nie wystartowała - węzeł wrócił do poprzedniej',
    'offline' => 'węzeł nie odpowiada',
    final e => e,
  };

  factory HubUpdateEntry.fromJson(Json j) => HubUpdateEntry(
    id: asString(j['id'], 'id'),
    fwId: asStringOrNull(j['fwId'], 'fwId'),
    current: asStringOrNull(j['current'], 'current'),
    available: asStringOrNull(j['available'], 'available'),
    // Starszy hub bez `next`: dostępna, jeśli nowsza od obecnej.
    next: j.containsKey('next')
        ? asStringOrNull(j['next'], 'next')
        : switch ((asStringOrNull(j['current'], 'current'), asStringOrNull(j['available'], 'available'))) {
            (final String c, final String a) when compareVersions(c, a) < 0 => a,
            _ => null,
          },
    ready: asBool(j['ready'], 'ready'),
    state: HubUpdateState.fromWire(j['state']),
    error: asStringOrNull(j['error'], 'error'),
  );
}

/// `GET hub/api/updates` albo `homes/{h}/devices/{hubId}/updates`.
class HubUpdates {
  const HubUpdates({this.checked, this.manifest, this.devices = const []});

  /// Ostatnie pobranie manifestu przez hub (unix, s).
  final int? checked;
  final String? manifest;
  final List<HubUpdateEntry> devices;

  factory HubUpdates.fromJson(Json j) => HubUpdates(
    checked: asIntOrNull(j['checked'], 'checked'),
    manifest: asStringOrNull(j['manifest'], 'manifest'),
    devices: [
      for (final d
          in (j['devices'] is List
              ? j['devices'] as List
              : j['devices'] is Map
              ? (j['devices'] as Map).values
              : const []))
        if (d is Map) HubUpdateEntry.fromJson(d.cast<String, dynamic>()),
    ],
  );
}
