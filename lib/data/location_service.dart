import 'dart:async';

import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

enum LocationFailureKind { serviceOff, denied, deniedForever, timeout, other }

class LocationFailure implements Exception {
  const LocationFailure(this.kind, this.message);
  final LocationFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

class LocationService {
  /// Target akurasi: berhenti lebih awal bila GPS sudah sebaik ini (meter).
  static const double goodAccuracyM = 25;
  static const Duration maxWait = Duration(seconds: 20);

  Future<Position> acquire() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        LocationFailureKind.serviceOff,
        'Layanan lokasi (GPS) di perangkat sedang mati.',
      );
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      throw const LocationFailure(
        LocationFailureKind.deniedForever,
        'Izin lokasi ditolak permanen. Aktifkan lewat pengaturan aplikasi.',
      );
    }
    if (perm == LocationPermission.denied) {
      throw const LocationFailure(
        LocationFailureKind.denied,
        'Izin lokasi belum diberikan.',
      );
    }
    return _bestFix();
  }

  /// Mendengarkan aliran GPS hingga akurasi cukup baik atau waktu habis,
  /// lalu memakai fix terbaik yang pernah diterima.
  Future<Position> _bestFix() async {
    Position? best;
    final done = Completer<Position>();
    late StreamSubscription<Position> sub;

    final timer = Timer(maxWait, () {
      if (done.isCompleted) return;
      final b = best;
      if (b != null) {
        done.complete(b);
      } else {
        done.completeError(const LocationFailure(
          LocationFailureKind.timeout,
          'GPS belum mendapat posisi. Coba di area terbuka.',
        ));
      }
    });

    sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).listen(
      (p) {
        final b = best;
        if (b == null || p.accuracy < b.accuracy) best = p;
        if (p.accuracy <= goodAccuracyM && !done.isCompleted) done.complete(p);
      },
      onError: (Object e) {
        if (!done.isCompleted) {
          done.completeError(LocationFailure(LocationFailureKind.other, 'Gagal membaca GPS: $e'));
        }
      },
    );

    try {
      return await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  /// Nama wilayah dari koordinat (geocoder bawaan Android). Mengembalikan daftar
  /// kosong bila gagal; pemanggil harus siap dengan pencarian manual.
  Future<List<String>> reverseGeocode(double lat, double lon) async {
    try {
      try {
        await geo.setLocaleIdentifier('id_ID');
      } catch (_) {
        // Tidak semua platform mendukung pengaturan locale; lanjut dengan locale sistem.
      }
      final marks = await geo
          .placemarkFromCoordinates(lat, lon)
          .timeout(const Duration(seconds: 12));
      final out = <String>[];
      for (final p in marks.take(3)) {
        for (final v in [p.administrativeArea, p.subAdministrativeArea, p.locality, p.subLocality]) {
          if (v != null && v.trim().isNotEmpty) out.add(v.trim());
        }
      }
      return out;
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> openAppSettings() => Geolocator.openAppSettings();
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
