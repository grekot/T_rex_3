// Analiza zdjęcia na telefonie: jakość (czysty Dart w osobnym wątku) + ML Kit bez internetu:
// twarze (uśmiech, otwarte oczy), etykiety treści i - gdy nie ma twarzy - ilość tekstu (dokumenty, kartki).
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:photo_manager/photo_manager.dart';

import '../select/analysis.dart';
import '../select/quality.dart';
import 'gallery.dart';

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

class PhotoAnalyzer {
  PhotoAnalyzer(this.tempDir);

  final Directory tempDir;
  final _faces = FaceDetector(
    options: FaceDetectorOptions(enableClassification: true, minFaceSize: 0.08),
  );
  final _labels = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));
  final _text = TextRecognizer(script: TextRecognitionScript.latin);

  Future<PhotoAnalysis?> analyze(AssetEntity asset) async {
    final bytes = await imageBytes(asset, 512, quality: 85);
    if (bytes == null) return null;
    final quality = await compute(measureQuality, bytes);
    final file = File('${tempDir.path}/analiza_${asset.id.replaceAll(RegExp(r'[^0-9A-Za-z]'), '_')}.jpg');
    await file.writeAsBytes(bytes, flush: true);
    try {
      final input = InputImage.fromFilePath(file.path);
      final faces = await _faces.processImage(input);
      final labels = await _labels.processImage(input);
      var textChars = -1;
      if (faces.isEmpty) {
        final text = await _text.processImage(input);
        textChars = _letterOrDigit.allMatches(text.text).length;
      }
      final w = quality.width.toDouble(), h = quality.height.toDouble();
      return PhotoAnalysis(
        id: photoIdOf(asset),
        assetId: asset.id,
        taken: asset.createDateTime,
        favorite: asset.isFavorite,
        quality: quality,
        faces: [
          for (final f in faces)
            FaceBox(
              left: (f.boundingBox.left / w).clamp(0.0, 1.0),
              top: (f.boundingBox.top / h).clamp(0.0, 1.0),
              width: (f.boundingBox.width / w).clamp(0.0, 1.0),
              height: (f.boundingBox.height / h).clamp(0.0, 1.0),
              smile: f.smilingProbability,
              eyesOpen: _eyes(f),
            ),
        ],
        labels: [for (final l in labels) LabelHit(l.label, l.confidence)],
        textChars: textChars,
      );
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  double? _eyes(Face f) {
    final l = f.leftEyeOpenProbability, r = f.rightEyeOpenProbability;
    if (l == null && r == null) return null;
    if (l == null) return r;
    if (r == null) return l;
    return l < r ? l : r;
  }

  Future<void> close() async {
    await _faces.close();
    await _labels.close();
    await _text.close();
  }
}
