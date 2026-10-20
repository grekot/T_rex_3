// Galeria telefonu (photo_manager): dostęp, zdjęcia z aparatu z ostatnich dni, miniatury,
// gotowe PNG 480×480 dla zegarka.
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../bridge/photo_prep.dart';
import '../select/candidates.dart';
import '../select/crop.dart';

/// Najwięcej zdjęć branych z okresu (przy 30 dniach to i tak dużo)
const int maxCandidates = 3000;

const _imagesOnly = PermissionRequestOption(
  androidPermission: AndroidPermission(type: RequestType.image, mediaLocation: false),
);

Future<PermissionState> requestGalleryAccess() =>
    PhotoManager.requestPermissionExtend(requestOption: _imagesOnly);

/// Android 14+: systemowy wybór zdjęć, gdy aplikacja ma dostęp tylko do części galerii
Future<void> pickMorePhotos() => PhotoManager.presentLimited(type: RequestType.image);

// Bez domyślnego filtra rozmiaru: zdjęcia bez wpisanej szerokości w MediaStore inaczej by znikały
FilterOptionGroup _filter({DateTime? since}) => FilterOptionGroup(
      imageOption: const FilterOption(sizeConstraint: SizeConstraint(ignoreSize: true)),
      createTimeCond: since == null
          ? DateTimeCond.def().copyWith(ignore: true)
          : DateTimeCond(min: since, max: DateTime.now().add(const Duration(days: 1))),
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    );

Future<List<AssetEntity>> _images(FilterOptionGroup filter, int limit) async {
  final count = await PhotoManager.getAssetCount(type: RequestType.image, filterOption: filter);
  if (count == 0) return const [];
  return PhotoManager.getAssetListRange(
    start: 0,
    end: count < limit ? count : limit,
    type: RequestType.image,
    filterOption: filter,
  );
}

/// Zdjęcia z aparatu z ostatnich [days] dni (plus ulubione z innych folderów)
Future<List<AssetEntity>> cameraPhotos(int days) async {
  final since = DateTime.now().subtract(Duration(days: days));
  final all = await _images(_filter(since: since), maxCandidates);
  return [
    for (final a in all)
      if (isCameraPath(a.relativePath) || a.isFavorite) a,
  ];
}

/// Data najstarszego zdjęcia z aparatu (początek historii dla wspomnień); null = pusta galeria
Future<DateTime?> oldestCameraPhoto() async {
  final filter = FilterOptionGroup(
    imageOption: const FilterOption(sizeConstraint: SizeConstraint(ignoreSize: true)),
    createTimeCond: DateTimeCond.def().copyWith(ignore: true),
    orders: [const OrderOption(type: OrderOptionType.createDate, asc: true)],
  );
  // Kilkadziesiąt najstarszych, bo pierwsze bywają zrzutami ekranu albo zdjęciami z komunikatorów
  for (final a in await _images(filter, 50)) {
    if (isCameraPath(a.relativePath)) return a.createDateTime;
  }
  return null;
}

/// Zdjęcia z aparatu z okresu [start, end) - kandydaci na wspomnienia
Future<List<AssetEntity>> cameraPhotosBetween(DateTime start, DateTime end) async {
  final filter = FilterOptionGroup(
    imageOption: const FilterOption(sizeConstraint: SizeConstraint(ignoreSize: true)),
    createTimeCond: DateTimeCond(min: start, max: end),
    orders: [const OrderOption(type: OrderOptionType.createDate, asc: true)],
  );
  return [
    for (final a in await _images(filter, 2000))
      if (isCameraPath(a.relativePath) || a.isFavorite) a,
  ];
}

/// Najnowsze zdjęcia z całej galerii - do ręcznego dodawania
Future<List<AssetEntity>> recentPhotos(int limit) => _images(_filter(), limit);

String photoIdOf(AssetEntity a) => photoId(a.id, a.modifiedDateSecond ?? 0);

/// Miniatura JPEG z systemu (już obrócona zgodnie z EXIF, także dla HEIC), a gdy jej brak - oryginał
Future<Uint8List?> imageBytes(AssetEntity a, int size, {int quality = 90}) async {
  final thumb = await a.thumbnailDataWithOption(ThumbnailOption(size: ThumbnailSize(size, size), quality: quality));
  if (thumb != null && thumb.isNotEmpty) return thumb;
  return a.originBytes;
}

/// PNG 480×480 dla zegarka z kadrem; źródło 1600 px, żeby przybliżony kadr był ostry
Future<Uint8List> watchPng(AssetEntity a, CropBox crop) async {
  final source = await imageBytes(a, 1600, quality: 92);
  if (source == null) throw StateError('System nie oddał danych zdjęcia');
  return compute(preparePngJob, PrepJob(source, crop));
}
