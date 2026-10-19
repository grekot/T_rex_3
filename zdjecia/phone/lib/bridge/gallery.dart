// Galeria telefonu: najnowsze zdjęcia zamienione na PNG 480×480 dla zegarka.
// Każdy problem (brak dostępu, dostęp tylko do wybranych zdjęć, nieczytelny plik) trafia do wyniku,
// żeby ekran mógł powiedzieć, czemu lista jest pusta.
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import 'bridge_server.dart';
import 'format.dart';
import 'photo_prep.dart';

class PreparedPhoto {
  const PreparedPhoto({required this.photo, required this.sourceBytes, required this.source, required this.took});

  final BridgePhoto photo;

  /// Rozmiar danych z galerii, z których powstał PNG
  final int sourceBytes;

  /// Skąd dane: miniatura systemu albo oryginał (gdy miniatury brak)
  final String source;

  /// Czas przygotowania (odczyt + przycięcie + PNG)
  final Duration took;
}

class GalleryLoad {
  const GalleryLoad({
    required this.access,
    this.visible = 0,
    this.photos = const [],
    this.problems = const [],
  });

  final PermissionState access;

  /// Ile zdjęć aplikacja w ogóle widzi w galerii
  final int visible;
  final List<PreparedPhoto> photos;
  final List<String> problems;

  bool get hasAccess => access.hasAccess;
  bool get limited => access == PermissionState.limited;
}

const _imagesOnly = PermissionRequestOption(
  androidPermission: AndroidPermission(type: RequestType.image, mediaLocation: false),
);

// Bez domyślnych filtrów rozmiaru i daty: zdjęcia bez wpisanej szerokości w MediaStore
// (zdarza się przy świeżych plikach) inaczej by znikały.
FilterOptionGroup _filter() => FilterOptionGroup(
      imageOption: const FilterOption(sizeConstraint: SizeConstraint(ignoreSize: true)),
      createTimeCond: DateTimeCond.def().copyWith(ignore: true),
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    );

Future<GalleryLoad> loadLatestPhotos(int count) async {
  final access = await PhotoManager.requestPermissionExtend(requestOption: _imagesOnly);
  if (!access.hasAccess) return GalleryLoad(access: access);

  final visible = await PhotoManager.getAssetCount(type: RequestType.image, filterOption: _filter());
  if (visible == 0) return GalleryLoad(access: access);

  final assets = await PhotoManager.getAssetListRange(
    start: 0,
    end: count,
    type: RequestType.image,
    filterOption: _filter(),
  );
  final photos = <PreparedPhoto>[];
  final problems = <String>[];
  for (final asset in assets) {
    final label = formatDateTime(asset.createDateTime);
    try {
      final prepared = await _prepare(asset);
      if (prepared == null) {
        problems.add('$label: system nie oddał danych zdjęcia');
      } else {
        photos.add(prepared);
      }
    } catch (e) {
      problems.add('$label: $e');
    }
  }
  if (assets.isEmpty) problems.add('Galeria zgłasza $visible zdjęć, ale nie zwróciła żadnego');
  return GalleryLoad(access: access, visible: visible, photos: photos, problems: problems);
}

Future<PreparedPhoto?> _prepare(AssetEntity asset) async {
  final watch = Stopwatch()..start();
  // Miniatura z systemu (już obrócona zgodnie z EXIF, zawsze JPEG - także dla HEIC) zamiast oryginału 12+ Mpx
  var source = 'miniatura';
  var data = await asset.thumbnailDataWithOption(
    const ThumbnailOption(size: ThumbnailSize(960, 960), quality: 92),
  );
  if (data == null || data.isEmpty) {
    source = 'oryginał';
    data = await asset.originBytes;
  }
  if (data == null || data.isEmpty) return null;
  final png = await compute(preparePng, data);
  return PreparedPhoto(
    photo: BridgePhoto(
      id: photoId(asset.id, asset.modifiedDateSecond ?? 0),
      png: png,
      taken: asset.createDateTime,
    ),
    sourceBytes: data.length,
    source: source,
    took: watch.elapsed,
  );
}

/// Android 14+: systemowy wybór zdjęć, gdy aplikacja ma dostęp tylko do części galerii.
Future<void> pickMorePhotos() => PhotoManager.presentLimited(type: RequestType.image);

/// Opis stanu dostępu do pokazania pod przyciskiem
String accessSummary(GalleryLoad load) {
  if (!load.hasAccess) return 'Brak dostępu do zdjęć – zezwól w ustawieniach aplikacji.';
  final scope = load.limited ? 'tylko wybrane zdjęcia' : 'cała galeria';
  return 'Dostęp: $scope · aplikacja widzi zdjęć: ${load.visible}';
}
