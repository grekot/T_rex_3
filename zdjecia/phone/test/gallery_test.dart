import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:zdjecia/bridge/gallery.dart';

void main() {
  test('opis dostępu do galerii', () {
    expect(accessSummary(const GalleryLoad(access: PermissionState.denied)), contains('Brak dostępu'));
    const limited = GalleryLoad(access: PermissionState.limited, visible: 2);
    expect(limited.limited, isTrue);
    expect(accessSummary(limited), 'Dostęp: tylko wybrane zdjęcia · aplikacja widzi zdjęć: 2');
    expect(
      accessSummary(const GalleryLoad(access: PermissionState.authorized, visible: 1234)),
      'Dostęp: cała galeria · aplikacja widzi zdjęć: 1234',
    );
  });
}
