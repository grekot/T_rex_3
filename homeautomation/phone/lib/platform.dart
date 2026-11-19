import 'package:flutter/foundation.dart';

// Co umie platforma, na której działa aplikacja. Wersja na komputer (Windows) to ten sam kod: bez Bluetootha,
// aparatu, sieci WiFi urządzenia (SoftAP), pracy w tle, widżetów i położenia telefonu - takie elementy chowamy.
// W testach platformę zmienia `debugDefaultTargetPlatformOverride`.

/// Aplikacja na komputerze (Windows, także Linux / macOS).
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Skaner kodów QR aparatem (mobile_scanner) i konfiguracja nowych urządzeń (Bluetooth, SoftAP): tylko telefon.
bool get canSetUpDevices =>
    !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// Położenie z GPS telefonu (kanał `location` w MainActivity.kt / AppDelegate.swift).
bool get hasPhoneLocation => canSetUpDevices;

/// „telefon” albo „komputer” - w tekstach typu „Z telefonu”, „ten telefon”.
String get thisDeviceName => isDesktop ? 'komputer' : 'telefon';

/// „Z telefonu” / „Z komputera”.
String get fromThisDevice => isDesktop ? 'Z komputera' : 'Z telefonu';
