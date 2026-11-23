import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class BmkgException implements Exception {
  const BmkgException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ForecastResult {
  const ForecastResult({
    required this.data,
    required this.fetchedAt,
    this.fromCache = false,
    this.warning,
  });

  final ForecastData data;
  final DateTime fetchedAt;
  final bool fromCache;

  /// Diisi bila unduhan gagal dan yang ditampilkan adalah data cache lama.
  final String? warning;
}

/// Klien API publik BMKG. Data BMKG hanya diperbarui 2x sehari dan dibatasi
/// 60 permintaan/menit/IP, jadi hasil disimpan di perangkat dan tidak diunduh
/// ulang bila masih baru.
class BmkgService {
  BmkgService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint = 'https://api.bmkg.go.id/publik/prakiraan-cuaca';
  static const freshFor = Duration(minutes: 30);
  static const minForceGap = Duration(minutes: 5);
  static const _maxCached = 5;

  Future<ForecastResult> load(String adm4, {bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedBody = prefs.getString('fc_$adm4');
    final cachedMs = prefs.getInt('fc_ts_$adm4');
    final cachedAt = cachedMs == null ? null : DateTime.fromMillisecondsSinceEpoch(cachedMs);

    if (cachedBody != null && cachedAt != null) {
      final age = DateTime.now().difference(cachedAt);
      if (age < (force ? minForceGap : freshFor)) {
        try {
          return ForecastResult(
            data: parseForecast(cachedBody),
            fetchedAt: cachedAt,
            fromCache: true,
          );
        } on FormatException {
          // cache rusak: lanjut mengunduh
        }
      }
    }

    try {
      final resp = await _client.get(
        Uri.parse('$_endpoint?adm4=$adm4'),
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'CuacaKelurahan/1.0 (aplikasi tidak resmi)',
        },
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw BmkgException(_httpMessage(resp.statusCode));
      }
      final body = utf8.decode(resp.bodyBytes);
      final data = parseForecast(body); // validasi dulu sebelum disimpan
      await _save(prefs, adm4, body);
      return ForecastResult(data: data, fetchedAt: DateTime.now());
    } catch (e) {
      final message = _describe(e);
      if (cachedBody != null && cachedAt != null) {
        try {
          return ForecastResult(
            data: parseForecast(cachedBody),
            fetchedAt: cachedAt,
            fromCache: true,
            warning: message,
          );
        } on FormatException {
          // cache tidak bisa dipakai
        }
      }
      throw BmkgException(message);
    }
  }

  Future<void> _save(SharedPreferences prefs, String adm4, String body) async {
    await prefs.setString('fc_$adm4', body);
    await prefs.setInt('fc_ts_$adm4', DateTime.now().millisecondsSinceEpoch);
    final index = prefs.getStringList('fc_index') ?? <String>[];
    index.remove(adm4);
    index.insert(0, adm4);
    while (index.length > _maxCached) {
      final old = index.removeLast();
      await prefs.remove('fc_$old');
      await prefs.remove('fc_ts_$old');
    }
    await prefs.setStringList('fc_index', index);
  }

  String _httpMessage(int code) {
    if (code == 429) return 'Terlalu banyak permintaan ke BMKG. Coba lagi beberapa menit lagi.';
    if (code == 404) return 'BMKG tidak memiliki prakiraan untuk kode wilayah ini.';
    if (code >= 500) return 'Server BMKG sedang bermasalah (HTTP $code).';
    return 'BMKG menolak permintaan (HTTP $code).';
  }

  String _describe(Object e) {
    if (e is BmkgException) return e.message;
    if (e is SocketException || e is http.ClientException) {
      return 'Tidak ada koneksi internet atau server BMKG tidak terjangkau.';
    }
    if (e is TimeoutException) return 'Server BMKG tidak merespons (waktu habis).';
    if (e is FormatException) return 'Respons BMKG tidak dapat dibaca: ${e.message}';
    return 'Gagal mengambil data BMKG: $e';
  }
}
