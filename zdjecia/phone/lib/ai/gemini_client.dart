// Gemini API wprost przez HTTP (klucz z Google AI Studio, jak w EscapeRoom): generateContent
// z obrazkami i odpowiedzią według schematu JSON oraz lista dostępnych modeli.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_errors.dart';

/// Domyślny model - ten sam, który działa w EscapeRoom; lista w ustawieniach pochodzi z API
const String defaultGeminiModel = 'gemini-3.8-flash';

const String geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta';

class GeminiClient {
  GeminiClient({required this.apiKey, this.model = defaultGeminiModel, http.Client? client, this.baseUrl = geminiBaseUrl})
      : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final String baseUrl;
  final http.Client _client;

  Map<String, String> get _headers => {'content-type': 'application/json', 'x-goog-api-key': apiKey};

  /// Treść zapytania (części: tekst i obrazki) → obiekt JSON według [schema]
  Future<Map<String, dynamic>> generateJson({
    required String system,
    required List<Map<String, Object>> parts,
    required Map<String, Object> schema,
    int maxTokens = 8192,
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final body = {
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        {'role': 'user', 'parts': parts},
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseJsonSchema': schema,
        'maxOutputTokens': maxTokens,
        'temperature': 0.2,
      },
    };
    return parseJsonObject(await _generate(body, timeout));
  }

  /// Krótkie zapytanie sprawdzające klucz i model
  Future<void> ping() async {
    await _generate({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Odpowiedz jednym słowem: OK'},
          ],
        },
      ],
      'generationConfig': {'maxOutputTokens': 8},
    }, const Duration(seconds: 30));
  }

  /// Modele Gemini obsługujące generateContent (bez obrazkowych, TTS i embeddingów)
  Future<List<String>> listModels() async {
    _requireKey();
    final out = <String>[];
    String? token;
    do {
      final uri = Uri.parse('$baseUrl/models').replace(queryParameters: {'pageSize': '200', 'pageToken': ?token});
      final res = await _send(() => _client.get(uri, headers: _headers), const Duration(seconds: 30));
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      for (final m in (j['models'] as List? ?? const [])) {
        final map = m as Map;
        final methods = (map['supportedGenerationMethods'] as List? ?? const []).cast<String>();
        final id = (map['name'] as String).replaceFirst('models/', '');
        final lower = id.toLowerCase();
        if (!methods.contains('generateContent') || !lower.startsWith('gemini-')) continue;
        if (const ['image', 'tts', 'embedding', 'audio', 'live', 'nano-banana'].any(lower.contains)) continue;
        out.add(id);
      }
      token = j['nextPageToken'] as String?;
    } while (token != null && token.isNotEmpty);
    out.sort();
    return out;
  }

  void _requireKey() {
    if (apiKey.trim().isEmpty) throw AiException(AiErrorKind.noApiKey, 'Brak klucza Gemini.');
  }

  Future<String> _generate(Map<String, Object> body, Duration timeout) async {
    _requireKey();
    final res = await _send(
      () => _client.post(Uri.parse('$baseUrl/models/$model:generateContent'), headers: _headers, body: jsonEncode(body)),
      timeout,
    );
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw AiException(AiErrorKind.badJson, 'Niepoprawna odpowiedź serwera.', body: res.body);
    }
    final feedback = j['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      throw AiException(AiErrorKind.refusal, 'Zablokowano: ${feedback['blockReason']}');
    }
    final candidates = j['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw AiException(AiErrorKind.refusal, 'Model nie zwrócił odpowiedzi.', body: res.body);
    }
    final c = candidates.first as Map;
    final finish = c['finishReason']?.toString();
    final text = StringBuffer();
    final content = c['content'];
    if (content is Map && content['parts'] is List) {
      for (final p in content['parts'] as List) {
        if (p is Map && p['text'] != null && p['thought'] != true) text.write(p['text']);
      }
    }
    if (const ['SAFETY', 'PROHIBITED_CONTENT', 'BLOCKLIST', 'SPII'].contains(finish)) {
      throw AiException(AiErrorKind.refusal, 'Zablokowano: $finish');
    }
    if (finish == 'MAX_TOKENS') {
      throw AiException(AiErrorKind.truncated, 'Odpowiedź ucięta (MAX_TOKENS).', body: text.toString());
    }
    return text.toString();
  }

  Future<http.Response> _send(Future<http.Response> Function() request, Duration timeout) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } on TimeoutException {
      throw AiException(AiErrorKind.timeout, 'Przekroczono czas oczekiwania.');
    } on SocketException catch (e) {
      throw AiException(AiErrorKind.network, e.message);
    } on http.ClientException catch (e) {
      throw AiException(AiErrorKind.network, e.message);
    }
    if (res.statusCode != 200) _throwForStatus(res);
    return res;
  }

  Never _throwForStatus(http.Response res) {
    var msg = res.reasonPhrase ?? 'HTTP ${res.statusCode}';
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is Map && j['error'] is Map) msg = (j['error'] as Map)['message']?.toString() ?? msg;
    } catch (_) {}
    final kind = switch (res.statusCode) {
      401 || 403 => AiErrorKind.unauthorized,
      429 => AiErrorKind.rateLimited,
      400 || 404 => AiErrorKind.badRequest,
      >= 500 => AiErrorKind.server,
      _ => AiErrorKind.unknown,
    };
    throw AiException(kind, msg, statusCode: res.statusCode, body: res.body);
  }
}
