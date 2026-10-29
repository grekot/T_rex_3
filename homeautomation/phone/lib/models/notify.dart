// Powiadomienia wysyłane przez samo urządzenie przez ntfy (kontrakt pkt 3d): Config/Set `notify`.

import 'json_utils.dart';

/// Config `notify`. Tokenu urządzenie nie zwraca - tylko [tokenSet].
class NotifyConfig {
  const NotifyConfig({this.enabled = false, this.server = defaultServer, this.topic = '', this.tokenSet = false});

  static const defaultServer = 'https://ntfy.sh';

  final bool enabled;
  final String server;
  final String topic;
  final bool tokenSet;

  /// null = urządzenie (firmware) nie ma powiadomień.
  static NotifyConfig? fromConfig(Json config) {
    final j = asObjectOrNull(config['notify'], 'notify');
    if (j == null) return null;
    final server = asStringOrNull(j['ntfyServer'], 'notify.ntfyServer');
    return NotifyConfig(
      enabled: asBool(j['enabled'], 'notify.enabled'),
      server: server == null || server.isEmpty ? defaultServer : server,
      topic: asString(j['ntfyTopic'], 'notify.ntfyTopic', ''),
      tokenSet: asBool(j['ntfyTokenSet'], 'notify.ntfyTokenSet'),
    );
  }

  bool get customServer => server != defaultServer;

  String get _host => server.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/+$'), '');

  /// Subskrypcja w aplikacji ntfy (Android): `ntfy://<serwer bez https://>/<temat>`.
  Uri get subscribeUri => Uri.parse('ntfy://$_host/$topic');

  /// Ten sam temat w przeglądarce (także iPhone bez schematu `ntfy://`).
  Uri get webUri => Uri.parse('${server.replaceFirst(RegExp(r'/+$'), '')}/$topic');
}

/// Set `notify` (poziom `config`): tylko ustawione pola. `topic: ''` = nowy losowy temat, `token: ''` = usuń token,
/// `server: ''` = domyślny serwer.
class NotifySet {
  const NotifySet({this.enabled, this.topic, this.token, this.server, this.test = false});

  final bool? enabled;
  final String? topic;
  final String? token;
  final String? server;
  final bool test;

  Json toJson() => {
    'notify': {
      'enabled': ?enabled,
      'ntfyTopic': ?topic,
      'ntfyToken': ?token,
      'ntfyServer': ?server,
      if (test) 'test': true,
    },
  };
}

/// Temat ntfy zgodny z kontraktem: 1-64 znaki `[A-Za-z0-9_-]`.
bool validNtfyTopic(String t) => RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(t);
