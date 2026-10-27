// Minimalny responder mDNS (RFC 6762/6763) dla atrapy: ogłasza `_termostat._tcp`
// z rekordami PTR, SRV, TXT i A - tak, jak zrobi to firmware termostatu.

import 'dart:io';
import 'dart:typed_data';

const _mdnsPort = 5353;
final _mdnsGroup = InternetAddress('224.0.0.251');

const _typeA = 1;
const _typePtr = 12;
const _typeTxt = 16;
const _typeSrv = 33;
const _typeAny = 255;

class MdnsResponder {
  MdnsResponder({
    required this.instance,
    required this.port,
    required this.txt,
    this.serviceType = '_homeauto._tcp',
    this.log = _noLog,
  });

  static void _noLog(String _) {}

  /// Nazwa instancji i hosta, np. `termostat-ab12cd`.
  final String instance;
  final int port;
  final Map<String, String> txt;
  final String serviceType;
  final void Function(String) log;

  RawDatagramSocket? _socket;
  List<InternetAddress> _addresses = [];

  String get _service => '$serviceType.local';
  String get _instanceName => '$instance.$_service';
  String get _host => '$instance.local';

  /// Zwraca false, gdy port 5353 jest zajęty i nie da się go współdzielić.
  Future<bool> start() async {
    _addresses = [
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4))
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a,
    ];
    try {
      final s = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _mdnsPort,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      );
      for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        try {
          s.joinMulticast(_mdnsGroup, iface);
        } on SocketException {
          // Interfejs bez multicastu - pomijamy.
        }
      }
      s.multicastLoopback = true;
      s.listen((e) {
        if (e == RawSocketEvent.read) _onPacket(s.receive());
      });
      _socket = s;
    } on SocketException catch (e) {
      log('mDNS niedostępny (${e.message}). Aplikacja znajdzie atrapę po ręcznie wpisanym adresie.');
      return false;
    }
    log('mDNS: $_instanceName → ${_addresses.map((a) => a.address).join(', ')}:$port');
    _announce();
    Future.delayed(const Duration(seconds: 1), _announce);
    return true;
  }

  void stop() {
    _socket?.close();
    _socket = null;
  }

  void _announce() => _send(_answers(all: true), _mdnsGroup, _mdnsPort);

  void _onPacket(Datagram? d) {
    if (d == null || d.data.length < 12) return;
    final data = d.data;
    final flags = (data[2] << 8) | data[3];
    if (flags & 0x8000 != 0) return; // odpowiedź, nie pytanie
    final qd = (data[4] << 8) | data[5];
    var offset = 12;
    var wanted = false;
    var unicast = false;
    try {
      for (var i = 0; i < qd; i++) {
        final (name, next) = _readName(data, offset);
        final type = (data[next] << 8) | data[next + 1];
        final cls = (data[next + 2] << 8) | data[next + 3];
        offset = next + 4;
        final n = name.toLowerCase();
        final matches = switch (type) {
          _typePtr => n == _service.toLowerCase() || n == '_services._dns-sd._udp.local',
          _typeSrv || _typeTxt => n == _instanceName.toLowerCase(),
          _typeA => n == _host.toLowerCase(),
          _typeAny => n == _service.toLowerCase() || n == _instanceName.toLowerCase() || n == _host.toLowerCase(),
          _ => false,
        };
        if (matches) {
          wanted = true;
          if (cls & 0x8000 != 0) unicast = true;
        }
      }
    } on RangeError {
      return;
    }
    if (!wanted) return;
    // Pytanie z portu innego niż 5353 albo z bitem QU - odpowiadamy wprost do pytającego.
    if (unicast || d.port != _mdnsPort) {
      _send(_answers(all: true), d.address, d.port);
    } else {
      _send(_answers(all: true), _mdnsGroup, _mdnsPort);
    }
  }

  List<Uint8List> _answers({required bool all}) => [
    _record(_service, _typePtr, 4500, _name(_instanceName), cacheFlush: false),
    _record(_instanceName, _typeSrv, 120, Uint8List.fromList([0, 0, 0, 0, port >> 8, port & 0xff, ..._name(_host)])),
    _record(_instanceName, _typeTxt, 4500, _txt()),
    for (final a in _addresses) _record(_host, _typeA, 120, Uint8List.fromList(a.rawAddress)),
  ];

  void _send(List<Uint8List> records, InternetAddress to, int toPort) {
    final b = BytesBuilder()..add([0, 0, 0x84, 0x00, 0, 0, records.length >> 8, records.length & 0xff, 0, 0, 0, 0]);
    for (final r in records) {
      b.add(r);
    }
    _socket?.send(b.toBytes(), to, toPort);
  }

  Uint8List _txt() {
    final b = BytesBuilder();
    for (final e in txt.entries) {
      final s = '${e.key}=${e.value}'.codeUnits;
      b
        ..addByte(s.length)
        ..add(s);
    }
    return b.toBytes();
  }

  static Uint8List _name(String name) {
    final b = BytesBuilder();
    for (final label in name.split('.')) {
      final bytes = label.codeUnits;
      b
        ..addByte(bytes.length)
        ..add(bytes);
    }
    b.addByte(0);
    return b.toBytes();
  }

  static Uint8List _record(String name, int type, int ttl, Uint8List rdata, {bool cacheFlush = true}) {
    final cls = cacheFlush ? 0x8001 : 0x0001;
    return (BytesBuilder()
          ..add(_name(name))
          ..add([type >> 8, type & 0xff, cls >> 8, cls & 0xff])
          ..add([ttl >> 24 & 0xff, ttl >> 16 & 0xff, ttl >> 8 & 0xff, ttl & 0xff])
          ..add([rdata.length >> 8, rdata.length & 0xff])
          ..add(rdata))
        .toBytes();
  }

  /// Czyta nazwę DNS (z obsługą kompresji); zwraca nazwę i offset za nią.
  static (String, int) _readName(Uint8List data, int offset) {
    final labels = <String>[];
    var pos = offset;
    int? end;
    for (var jumps = 0; jumps < 20; jumps++) {
      final len = data[pos];
      if (len == 0) {
        end ??= pos + 1;
        return (labels.join('.'), end);
      }
      if (len & 0xc0 == 0xc0) {
        end ??= pos + 2;
        pos = ((len & 0x3f) << 8) | data[pos + 1];
        continue;
      }
      labels.add(String.fromCharCodes(data.sublist(pos + 1, pos + 1 + len)));
      pos += len + 1;
    }
    throw RangeError('Za dużo skoków w nazwie DNS');
  }
}
