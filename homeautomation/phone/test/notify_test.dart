// Powiadomienia z urządzenia przez ntfy (kontrakt pkt 3d): Config/Set `notify`, ekran „Powiadomienia”.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeautomation/controllers/field_errors.dart';
import 'package:homeautomation/models/json_utils.dart';
import 'package:homeautomation/models/notify.dart';
import 'package:homeautomation/models/set_values.dart';
import 'package:homeautomation/ui/notify_screen.dart';

/// Urządzenie w pamięci dla ekranu: Config `notify` i Set jak w firmware (bez walidacji).
class _MemDevice {
  _MemDevice(this.notify);

  Json? notify;
  final sent = <Json>[];

  Future<Json> load() async => {'name': 'Salon', 'notify': ?notify};

  Future<SetResult> send(Json v) async {
    sent.add(v);
    final n = (v['notify'] as Map).cast<String, dynamic>();
    if (n['ntfyTopic'] == 'zly temat') return const SetResult(ok: false, errors: {'notify.ntfyTopic': 'format'});
    notify = {...notify!, 'enabled': ?n['enabled'], if (n['ntfyTopic'] == '') 'ntfyTopic': 'ha-nowy0000000000'};
    return SetResult(ok: true, configJson: await load());
  }
}

void main() {
  test('model: brak notify = brak obsługi, adresy subskrypcji, Set tylko z ustawionymi polami', () {
    expect(NotifyConfig.fromConfig({'name': 'x'}), isNull);
    final c = NotifyConfig.fromConfig({
      'notify': {
        'enabled': true,
        'ntfyServer': 'https://ntfy.sh',
        'ntfyTopic': 'ha-3f9c0a17b2e4d681',
        'ntfyTokenSet': false,
      },
    })!;
    expect((c.enabled, c.customServer, c.tokenSet), (true, false, false));
    expect('${c.subscribeUri}', 'ntfy://ntfy.sh/ha-3f9c0a17b2e4d681');
    expect('${c.webUri}', 'https://ntfy.sh/ha-3f9c0a17b2e4d681');
    final own = NotifyConfig.fromConfig({
      'notify': {'ntfyServer': 'https://ntfy.example.pl/', 'ntfyTopic': 'dom'},
    })!;
    expect(
      ('${own.subscribeUri}', '${own.webUri}', own.customServer),
      ('ntfy://ntfy.example.pl/dom', 'https://ntfy.example.pl/dom', true),
    );
    expect(const NotifySet(enabled: true).toJson(), {
      'notify': {'enabled': true},
    });
    expect(const NotifySet(topic: '', token: '', test: true).toJson(), {
      'notify': {'ntfyTopic': '', 'ntfyToken': '', 'test': true},
    });
    expect((validNtfyTopic('ha-3f9c_A'), validNtfyTopic('zły temat'), validNtfyTopic('')), (true, false, false));
    expect(describeErrors({'notify.ntfyTopic': 'format'}), 'Temat ntfy: zły format');
  });

  testWidgets('ekran: włączenie, próbne, subskrypcja w ntfy z zapasową stroną, nowy temat', (tester) async {
    final dev = _MemDevice({
      'enabled': false,
      'ntfyServer': 'https://ntfy.sh',
      'ntfyTopic': 'ha-3f9c0a17b2e4d681',
      'ntfyTokenSet': false,
    });
    final opened = <String>[];
    var ntfyInstalled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: NotifyScreen(
          deviceName: 'Salon',
          loadConfig: dev.load,
          send: dev.send,
          openUrl: (u) async {
            opened.add('$u');
            return ntfyInstalled || u.scheme == 'https';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ha-3f9c0a17b2e4d681'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const Key('notifyTest'))).onPressed, isNull);

    await tester.tap(find.byKey(const Key('notifyEnabled')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notifyTest')));
    await tester.pumpAndSettle();
    expect(dev.sent, [
      {
        'notify': {'enabled': true},
      },
      {
        'notify': {'test': true},
      },
    ]);
    expect(find.text('Wysłano próbne powiadomienie.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('notifySubscribe')));
    await tester.pumpAndSettle();
    expect(opened, ['ntfy://ntfy.sh/ha-3f9c0a17b2e4d681', 'https://ntfy.sh/ha-3f9c0a17b2e4d681']);
    ntfyInstalled = true;
    opened.clear();
    await tester.tap(find.byKey(const Key('notifySubscribe')));
    await tester.pumpAndSettle();
    expect(opened, ['ntfy://ntfy.sh/ha-3f9c0a17b2e4d681']);

    ScaffoldMessenger.of(tester.element(find.byKey(const Key('notifyTopic')))).clearSnackBars();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('notifyNewTopic')));
    await tester.tap(find.byKey(const Key('notifyNewTopic')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zmień temat'));
    await tester.pumpAndSettle();
    expect(find.text('ha-nowy0000000000'), findsOneWidget);
  });

  testWidgets('ekran: urządzenie bez powiadomień (starszy firmware)', (tester) async {
    final dev = _MemDevice(null);
    await tester.pumpWidget(
      MaterialApp(
        home: NotifyScreen(deviceName: 'X', loadConfig: dev.load, send: dev.send),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notifyUnsupported')), findsOneWidget);
  });
}
