/// Adres termostatu w sieci lokalnej.
class LocalEndpoint {
  const LocalEndpoint(this.host, [this.port = 80]);

  final String host;
  final int port;

  /// Parsuje `192.168.1.20`, `192.168.1.20:8080`, `termostat-ab12cd.local`, `[fe80::1]:80`.
  static LocalEndpoint? tryParse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    s = s.replaceFirst(RegExp(r'^https?://'), '');
    s = s.split('/').first;
    final uri = Uri.tryParse('http://$s');
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? uri.port : 80;
    if (port <= 0 || port > 65535) return null;
    return LocalEndpoint(uri.host, port);
  }

  Uri http(String path, [Map<String, String>? query]) =>
      Uri(scheme: 'http', host: host, port: port, path: path, queryParameters: query);

  Uri ws(String path, [Map<String, String>? query]) =>
      Uri(scheme: 'ws', host: host, port: port, path: path, queryParameters: query);

  /// Do wyświetlenia i zapisu: port tylko gdy inny niż 80.
  String get display {
    final h = host.contains(':') ? '[$host]' : host;
    return port == 80 ? h : '$h:$port';
  }

  @override
  bool operator ==(Object other) => other is LocalEndpoint && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => display;
}

/// Czy adres należy do sieci lokalnej. Termostat mówi czystym HTTP bez TLS,
/// więc token wysyłamy tylko na takie adresy: prywatne IPv4 (RFC 1918),
/// link-local, loopback, IPv6 ULA/link-local oraz nazwy `.local`.
bool isLocalNetworkHost(String host) {
  final h = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  if (h == 'localhost' || h.endsWith('.local')) return true;

  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
  if (v4 != null) {
    final o = [for (var i = 1; i <= 4; i++) int.parse(v4.group(i)!)];
    if (o.any((x) => x > 255)) return false;
    return o[0] == 10 ||
        o[0] == 127 ||
        (o[0] == 172 && o[1] >= 16 && o[1] <= 31) ||
        (o[0] == 192 && o[1] == 168) ||
        (o[0] == 169 && o[1] == 254);
  }

  if (h.contains(':')) {
    if (h == '::1') return true;
    final first = int.tryParse(h.split(':').first, radix: 16);
    if (first == null) return false;
    return (first & 0xfe00) == 0xfc00 || // fc00::/7
        (first & 0xffc0) == 0xfe80; // fe80::/10
  }
  return false;
}
