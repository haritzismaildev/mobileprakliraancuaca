import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/text_utils.dart';
import '../data/bmkg_service.dart';
import '../data/location_service.dart';
import '../data/region.dart';

class GpsFix {
  const GpsFix({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.mocked,
  });

  final double lat;
  final double lon;
  final double accuracyM;
  final bool mocked;
}

/// Mengatur alur: data wilayah -> GPS -> nama wilayah -> kode adm4 -> prakiraan BMKG.
class AppController extends ChangeNotifier {
  AppController({BmkgService? bmkg, LocationService? location})
      : _bmkg = bmkg ?? BmkgService(),
        _location = location ?? LocationService();

  final BmkgService _bmkg;
  final LocationService _location;

  RegionIndex? index;
  Region? place;
  ForecastResult? forecast;
  GpsFix? fix;

  /// Pesan galat utama (hanya ditampilkan bila belum ada prakiraan).
  String? error;
  LocationFailureKind? failureKind;

  /// Catatan non-fatal (mis. kelurahan hanya perkiraan).
  String? approxNote;

  bool booting = true;
  bool locating = false;
  bool loading = false;
  bool usingGps = true;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      index = await RegionIndex.loadFromAsset();
    } catch (e) {
      error = 'Gagal memuat data wilayah: $e';
      booting = false;
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    usingGps = (prefs.getString('mode') ?? 'gps') == 'gps';
    final saved = prefs.getString('adm4');
    if (saved != null) place = index!.byCode[saved];
    booting = false;
    notifyListeners();

    if (place != null) await loadForecast();
    if (usingGps) await detectLocation();
  }

  Future<void> detectLocation() async {
    final idx = index;
    if (idx == null || locating) return;
    locating = true;
    error = null;
    failureKind = null;
    approxNote = null;
    notifyListeners();
    try {
      final pos = await _location.acquire();
      fix = GpsFix(
        lat: pos.latitude,
        lon: pos.longitude,
        accuracyM: pos.accuracy,
        mocked: pos.isMocked,
      );
      final names = await _location.reverseGeocode(pos.latitude, pos.longitude);
      final res = idx.resolve(names);
      final desa = res.desa;
      final fallback = res.fallbackDesa;
      if (desa != null) {
        await _choose(desa, gps: true);
      } else if (fallback != null && res.kecamatan != null) {
        approxNote = 'Kelurahan/desa Anda tidak terdeteksi persis. Menampilkan '
            '${prettyName(fallback.name)} (Kec. ${prettyName(res.kecamatan!.name)}) '
            'sebagai perkiraan. Pilih yang tepat lewat tombol cari.';
        await _choose(fallback, gps: true);
      } else if (place == null) {
        error = 'Koordinat GPS didapat (±${pos.accuracy.round()} m), tetapi nama wilayahnya '
            'tidak bisa dipetakan. Cari kelurahan/desa Anda secara manual.';
      } else {
        approxNote = 'GPS aktif, tetapi nama wilayah tidak bisa dipetakan. '
            'Memakai lokasi tersimpan.';
      }
    } on LocationFailure catch (e) {
      failureKind = e.kind;
      if (place == null) {
        error = e.message;
      } else {
        approxNote = '${e.message} Memakai lokasi tersimpan.';
      }
    } catch (e) {
      if (place == null) {
        error = 'Gagal menentukan lokasi: $e';
      } else {
        approxNote = 'Gagal menentukan lokasi: $e. Memakai lokasi tersimpan.';
      }
    } finally {
      locating = false;
      notifyListeners();
    }
  }

  Future<void> selectManual(Region desa) async {
    fix = null;
    approxNote = null;
    error = null;
    failureKind = null;
    await _choose(desa, gps: false);
  }

  Future<void> _choose(Region desa, {required bool gps}) async {
    if (place?.code != desa.code) forecast = null;
    place = desa;
    usingGps = gps;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adm4', desa.code);
    await prefs.setString('mode', gps ? 'gps' : 'manual');
    await loadForecast();
  }

  Future<void> loadForecast({bool force = false}) async {
    final p = place;
    if (p == null) return;
    loading = true;
    notifyListeners();
    try {
      forecast = await _bmkg.load(p.code, force: force);
      error = null;
    } on BmkgException catch (e) {
      final old = forecast;
      if (old == null) {
        error = e.message;
      } else {
        forecast = ForecastResult(
          data: old.data,
          fetchedAt: old.fetchedAt,
          fromCache: true,
          warning: e.message,
        );
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (usingGps) await detectLocation();
    if (place != null) await loadForecast(force: true);
  }

  Future<void> openAppSettings() => _location.openAppSettings();
  Future<void> openLocationSettings() => _location.openLocationSettings();
}
