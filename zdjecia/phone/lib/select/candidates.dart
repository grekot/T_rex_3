// Które zdjęcia w ogóle brać pod uwagę i jak je nazywać dla zegarka.
import 'crop.dart';

/// Foldery aplikacji i zrzutów ekranu - to nie są „moje zdjęcia”
const _skipFolders = [
  'screenshot', 'screenrecord', 'screen record', 'whatsapp', 'messenger', 'telegram', 'download', 'instagram',
  'facebook', 'snapchat', 'signal', 'viber', 'tiktok', 'bluetooth', 'pinterest', 'twitter', 'discord',
];

/// Zdjęcie z aparatu telefonu (folder DCIM, bez zrzutów ekranu i aplikacji)
bool isCameraPath(String? relativePath) {
  if (relativePath == null || relativePath.isEmpty) return true; // Android < 10 nie podaje folderu
  final path = relativePath.toLowerCase();
  if (_skipFolders.any(path.contains)) return false;
  return path.startsWith('dcim/');
}

/// Krótki, stały skrót kadru (FNV-1a), żeby zmiana kadru dała zegarkowi nowe zdjęcie
String cropHash(CropBox crop) {
  var h = 0x811c9dc5;
  for (final c in crop.key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(36).padLeft(7, '0').substring(0, 7);
}

/// Identyfikator na zegarku: zdjęcie + kadr, najwyżej 40 znaków [A-Za-z0-9_-]
String watchPhotoId(String photoId, CropBox crop) {
  final suffix = '_${cropHash(crop)}';
  final base = photoId.length + suffix.length <= 40 ? photoId : photoId.substring(photoId.length - (40 - suffix.length));
  return '$base$suffix';
}
