import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/app_icons.dart';

/// Ikona z katalogu aplikacji ([appIcons]) jako biały obrazek PNG (base64) do kratki widżetu - Android barwi ją
/// sam (kolor tekstu albo nazwany kolor pozycji). Rysuje silnik usługi widżetów, bez ekranu; null = nieznany
/// klucz albo czcionka ikon niedostępna (wtedy ikona zapasowa Androida).
Future<String?> renderIconPng(String key, {int size = 96}) async {
  final icon = appIcon(key)?.icon;
  if (icon == null) return null;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size.toDouble(),
          color: Colors.white,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset((size - painter.width) / 2, (size - painter.height) / 2));
    final image = await recorder.endRecording().toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes == null ? null : base64Encode(bytes.buffer.asUint8List());
  } on Object {
    return null;
  }
}
