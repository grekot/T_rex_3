// Ręczna poprawka kadru: przesuwanie palcem i przybliżanie dwoma palcami w okrągłym podglądzie
// takim jak ekran zegarka.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../media/gallery.dart';
import '../pool_controller.dart';
import '../select/crop.dart';

/// Ręcznie można przybliżyć mocniej niż automat
const double _manualMinSide = 0.3;

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.pool, required this.item});

  final PoolController pool;
  final PoolItem item;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  ui.Image? _image;
  String? _error;
  late CropBox _box = widget.item.crop;
  CropBox? _startBox;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final asset = widget.pool.assetOf(widget.item.id);
      if (asset == null) throw StateError('Zdjęcia nie ma już w galerii');
      final bytes = await imageBytes(asset, 1600, quality: 90);
      if (bytes == null) throw StateError('System nie oddał danych zdjęcia');
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) setState(() => _image = frame.image);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double viewSize) {
    final image = _image;
    final start = _startBox;
    if (image == null || start == null) return;
    final w = image.width.toDouble(), h = image.height.toDouble();
    final shortSide = math.min(w, h);
    final side = (start.side / d.scale).clamp(_manualMinSide, 1.0);
    final sidePx = side * shortSide;
    final k = viewSize / sidePx; // piksele ekranu na piksel zdjęcia
    var cx = _box.cx * w - d.focalPointDelta.dx / k;
    var cy = _box.cy * h - d.focalPointDelta.dy / k;
    cx = cx.clamp(sidePx / 2, w - sidePx / 2);
    cy = cy.clamp(sidePx / 2, h - sidePx / 2);
    setState(() => _box = CropBox(cx: cx / w, cy: cy / h, side: side));
  }

  Future<void> _save({required bool auto}) async {
    Navigator.pop(context);
    await widget.pool.setCrop(widget.item.id, auto ? null : _box);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(title: const Text('Kadr na zegarek')),
      body: Center(
        child: _error != null
            ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
            : image == null
                ? const CircularProgressIndicator()
                : LayoutBuilder(builder: (context, constraints) {
                    final size = math.min(constraints.maxWidth, constraints.maxHeight) - 32;
                    return GestureDetector(
                      onScaleStart: (_) => _startBox = _box,
                      onScaleUpdate: (d) => _onScaleUpdate(d, size),
                      child: CustomPaint(size: Size.square(size), painter: _CropPainter(image, _box)),
                    );
                  }),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: image == null ? null : () => _save(auto: true),
                  child: const Text('Automatycznie'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: image == null ? null : () => _save(auto: false),
                  child: const Text('Zapisz'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.box);

  final ui.Image image;
  final CropBox box;

  @override
  void paint(Canvas canvas, Size size) {
    final w = image.width.toDouble(), h = image.height.toDouble();
    final sidePx = box.side * math.min(w, h);
    final src = Rect.fromCenter(center: Offset(box.cx * w, box.cy * h), width: sidePx, height: sidePx);
    final dst = Offset.zero & size;
    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.medium);
    // Poza kołem zegarek nic nie pokaże - przyciemnienie
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(dst)
      ..addOval(dst);
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.7));
    canvas.drawOval(
      dst.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.orange,
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.box != box || old.image != image;
}
