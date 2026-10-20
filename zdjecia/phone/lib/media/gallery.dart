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

// Po dacie ZROBIENIA zdjęcia (datetaken), nie dodania pliku - patrz takenBetweenSql
CustomFilter _taken({DateTime? start, DateTime? end, required bool oldestFirst}) => CustomFilter.sql(
      where: takenBetweenSql(start: start, end: end),
      orderBy: [OrderByItem('datetaken', oldestFirst)],
    );

Future<List<AssetEntity>> _images(PMFilter filter, int limit) async {
  final count = await PhotoManager.getAssetCount(type: RequestType.image, filterOption: filter);
  if (count == 0) return const [];
  return PhotoManager.getAssetListRange(
    start: 0,
    end: count < limit ? count : limit,
    type: RequestType.image,
    filterOption: filter,
  );
}

/// Zdjęcia z aparatu zrobione w ostatnich [days] dniach (plus ulubione z innych folderów)
Future<List<AssetEntity>> cameraPhotos(int days) async {
  final since = DateTime.now().subtract(Duration(days: days));
  final all = await _images(_taken(start: since, oldestFirst: false), maxCandidates);
  return [
    for (final a in all)
      if (isCameraPath(a.relativePath) || a.isFavorite) a,
  ];
}

/// Data zrobienia najstarszego zdjęcia z aparatu (początek historii dla wspomnień); null = pusta galeria
Future<DateTime?> oldestCameraPhoto() async {
  final filter = CustomFilter.sql(
    where: 'media_type = 1 AND datetaken > 0',
    orderBy: [const OrderByItem.asc('datetaken')],
  );
  // Kilkaset najstarszych, bo pierwsze bywają zrzutami ekranu albo zdjęciami z komunikatorów
  for (final a in await _images(filter, 300)) {
    if (isCameraPath(a.relativePath)) return a.createDateTime;
  }
  return null;
}

/// Zdjęcia z aparatu zrobione w okresie [start, end) - kandydaci na wspomnienia
Future<List<AssetEntity>> cameraPhotosBetween(DateTime start, DateTime end) async {
  return [
    for (final a in await _images(_taken(start: start, end: end, oldestFirst: true), 2000))
      if (isCameraPath(a.relativePath) || a.isFavorite) a,
  ];
}

/// Najnowsze zdjęcia z całej galerii - do ręcznego dodawania
Future<List<AssetEntity>> recentPhotos(int limit) => _images(_taken(oldestFirst: false), limit);

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
