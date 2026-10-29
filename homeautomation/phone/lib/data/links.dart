import 'package:flutter/services.dart';

/// Otwieranie adresu w innej aplikacji (ntfy, przeglądarka) przez kanał natywny `pl.grekot.homeautomation/links`
/// (MainActivity.kt, AppDelegate.swift) - bez dodatkowej wtyczki. false = nic go nie obsłużyło.
typedef OpenUrl = Future<bool> Function(Uri uri);

const _channel = MethodChannel('pl.grekot.homeautomation/links');

Future<bool> openExternalUrl(Uri uri) async {
  try {
    return await _channel.invokeMethod<bool>('open', {'url': uri.toString()}) ?? false;
  } on Object {
    return false;
  }
}
