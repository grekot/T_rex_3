// Ręczne dodanie zdjęcia do puli: najnowsze zdjęcia z całej galerii (także spoza aparatu i starsze).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../media/gallery.dart';
import '../pool_controller.dart';

const int _pickLimit = 300;

class PickScreen extends StatefulWidget {
  const PickScreen({super.key, required this.pool});

  final PoolController pool;

  @override
  State<PickScreen> createState() => _PickScreenState();
}

class _PickScreenState extends State<PickScreen> {
  late final Future<List<AssetEntity>> _photos = recentPhotos(_pickLimit);
  final Map<String, Future<Uint8List?>> _thumbs = {};

  Future<Uint8List?> _thumb(AssetEntity a) =>
      _thumbs[a.id] ??= a.thumbnailDataWithOption(const ThumbnailOption(size: ThumbnailSize(240, 240), quality: 80));

  @override
  Widget build(BuildContext context) {
    final pinned = widget.pool.pinned;
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj zdjęcie do puli')),
      body: FutureBuilder<List<AssetEntity>>(
        future: _photos,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final photos = snap.data!;
          if (photos.isEmpty) return const Center(child: Text('Brak zdjęć w galerii.'));
          return GridView.builder(
            padding: const EdgeInsets.all(4) + EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: photos.length,
            itemBuilder: (context, i) {
              final a = photos[i];
              final inPool = pinned.contains(photoIdOf(a));
              return GestureDetector(
                onTap: inPool
                    ? null
                    : () {
                        final messenger = ScaffoldMessenger.of(context);
                        widget.pool.addManual(a);
                        Navigator.pop(context);
                        messenger.showSnackBar(const SnackBar(content: Text('Dodano i przypięto – kadruję...')));
                      },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FutureBuilder<Uint8List?>(
                      future: _thumb(a),
                      builder: (context, t) => t.data == null
                          ? const ColoredBox(color: Colors.black12)
                          : Image.memory(t.data!, fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                    if (inPool) const Align(alignment: Alignment.topRight, child: Icon(Icons.push_pin, color: Colors.orange)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
