// Galeria telefonu: najnowsze zdjęcia zamienione na PNG 480×480 dla zegarka.
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import 'bridge_server.dart';
import 'photo_prep.dart';

class PreparedPhoto {
  const PreparedPhoto({required this.photo, required this.sourceBytes, required this.took});

  final BridgePhoto photo;

  /// Rozmiar miniatury JPEG z galerii, z której powstał PNG
  final int sourceBytes;

  /// Czas przygotowania (miniatura + przycięcie + PNG)
  final Duration took;
}

Future<bool> requestGalleryAccess() async {
  final state = await PhotoManager.requestPermissionExtend(
    requestOption: const PermissionRequestOption(
      androidPermission: AndroidPermission(type: RequestType.image, mediaLocation: false),
    ),
  );
  return state.hasAccess;
}

Future<List<PreparedPhoto>> latestPhotos(int count) async {
  final assets = await PhotoManager.getAssetListRange(
    start: 0,
    end: count,
    type: RequestType.image,
    filterOption: FilterOptionGroup(
      orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
    ),
  );
  final out = <PreparedPhoto>[];
  for (final asset in assets) {
    final watch = Stopwatch()..start();
    // Miniatura z systemu (już obrócona zgodnie z EXIF) zamiast oryginału 12+ Mpx - dużo szybciej
    final thumb = await asset.thumbnailDataWithOption(
      const ThumbnailOption(size: ThumbnailSize(960, 960), quality: 92),
    );
    if (thumb == null) continue;
    final png = await compute(preparePng, thumb);
    out.add(PreparedPhoto(
      photo: BridgePhoto(
        id: photoId(asset.id, asset.modifiedDateSecond ?? 0),
        png: png,
        taken: asset.createDateTime,
      ),
      sourceBytes: thumb.length,
      took: watch.elapsed,
    ));
  }
  return out;
}
