import 'dart:convert';
import 'dart:math' as math;

/// Identitas lokasi prakiraan (tingkat kelurahan/desa, kode adm4).
class PlaceInfo {
  const PlaceInfo({
    required this.adm4,
    required this.desa,
    required this.kecamatan,
    required this.kotkab,
    required this.provinsi,
    required this.lat,
    required this.lon,
    required this.utcOffset,
  });

  final String adm4;
  final String desa;
  final String kecamatan;
  final String kotkab;
  final String provinsi;
  final double? lat;
  final double? lon;
  final Duration utcOffset;

  String get zoneLabel {
    final h = utcOffset.inHours;
    switch (h) {
      case 7:
        return 'WIB';
      case 8:
        return 'WITA';
      case 9:
        return 'WIT';
      default:
        return 'UTC${h >= 0 ? '+' : ''}$h';
    }
  }
}

/// Satu titik prakiraan (interval 3 jam) dari BMKG.
class ForecastSlot {
  const ForecastSlot({
    required this.utc,
    required this.wall,
    required this.desc,
    required this.descEn,
    this.temp,
    this.humidity,
    this.cloud,
    this.rain,
    this.code,
    this.windKmh,
    this.windFrom = '',
    this.windTo = '',
    this.windDeg,
    this.visibilityKm,
    this.visibilityText,
    this.iconUrl,
  });

  /// Waktu berlaku prakiraan dalam UTC.
  final DateTime utc;

  /// "Jam dinding" lokasi: DateTime bertanda UTC yang komponen jam/harinya
  /// sama dengan waktu setempat (WIB/WITA/WIT). Jangan dikonversi lagi.
  final DateTime wall;

  final String desc;
  final String descEn;
  final double? temp;
  final int? humidity;
  final int? cloud;
  final double? rain;
  final int? code;
  final double? windKmh;
  final String windFrom;
  final String windTo;
  final int? windDeg;
  final double? visibilityKm;
  final String? visibilityText;
  final String? iconUrl;

  bool get isRain {
    final d = desc.toLowerCase();
    return d.contains('hujan') || d.contains('petir');
  }

  bool get isNight => wall.hour >= 18 || wall.hour < 6;

  String get visibilityLabel {
    final text = visibilityText;
    if (text != null && text.trim().isNotEmpty) return text;
    final v = visibilityKm;
    if (v == null) return '—';
    return '${v.toStringAsFixed(v >= 10 ? 0 : 1)} km';
  }
}

class ForecastData {
  const ForecastData({required this.place, required this.slots, required this.analysisUtc});

  final PlaceInfo place;
  final List<ForecastSlot> slots;

  /// Waktu produksi/analisis data oleh BMKG (UTC), jika tersedia.
  final DateTime? analysisUtc;
}

/// Ringkasan satu hari (menurut tanggal setempat).
class DayForecast {
  DayForecast._(
    this.date,
    this.slots,
    this.minTemp,
    this.maxTemp,
    this.maxRain,
    this.rainSlots,
    this.dominant,
  );

  final DateTime date;
  final List<ForecastSlot> slots;
  final double? minTemp;
  final double? maxTemp;
  final double maxRain;
  final int rainSlots;
  final ForecastSlot dominant;

  factory DayForecast.from(DateTime date, List<ForecastSlot> slots) {
    double? minT;
    double? maxT;
    var maxRain = 0.0;
    var rainSlots = 0;
    final counts = <String, int>{};
    for (final s in slots) {
      final t = s.temp;
      if (t != null) {
        minT = minT == null ? t : math.min(minT, t);
        maxT = maxT == null ? t : math.max(maxT, t);
      }
      final r = s.rain;
      if (r != null && r > maxRain) maxRain = r;
      if (s.isRain) rainSlots++;
      counts[s.desc] = (counts[s.desc] ?? 0) + 1;
    }
    // Kondisi dominan = yang paling sering muncul; jika seri, pilih yang hujan.
    var bestDesc = slots.first.desc;
    var bestCount = -1;
    var bestIsRain = false;
    counts.forEach((d, n) {
      final isRain = d.toLowerCase().contains('hujan') || d.toLowerCase().contains('petir');
      if (n > bestCount || (n == bestCount && isRain && !bestIsRain)) {
        bestDesc = d;
        bestCount = n;
        bestIsRain = isRain;
      }
    });
    // Wakil tampilan: slot siang hari dengan kondisi dominan jika ada.
    final withDesc = slots.where((s) => s.desc == bestDesc).toList();
    final daytime = withDesc.where((s) => s.wall.hour >= 9 && s.wall.hour <= 15).toList();
    final dominant = daytime.isNotEmpty ? daytime.first : withDesc.first;
    return DayForecast._(date, slots, minT, maxT, maxRain, rainSlots, dominant);
  }
}

// ---------------------------------------------------------------- parsing

double? _d(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}

int? _i(dynamic v) => _d(v)?.round();

String _s(dynamic v) => v == null ? '' : '$v';

Map<String, dynamic> _asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// "2026-11-23 11:00:00" atau "2026-11-23T11:00:00Z" -> DateTime UTC.
/// String tanpa penanda zona diperlakukan sebagai UTC, sehingga komponen
/// jamnya bisa dipakai apa adanya (dipakai juga untuk "jam dinding" lokal).
DateTime? _parseUtc(String s) {
  var t = s.trim();
  if (t.isEmpty) return null;
  t = t.replaceFirst(' ', 'T');
  if (!t.endsWith('Z') && !t.contains('+')) t = '${t}Z';
  return DateTime.tryParse(t)?.toUtc();
}

/// Mengurai respons JSON `api.bmkg.go.id/publik/prakiraan-cuaca?adm4=...`.
/// Melempar [FormatException] bila struktur tidak dikenali.
ForecastData parseForecast(String body) {
  final dynamic root = jsonDecode(body);
  if (root is! Map) {
    throw const FormatException('format respons BMKG tidak dikenali');
  }
  final data = root['data'];
  if (data is! List || data.isEmpty || data.first is! Map) {
    throw const FormatException('BMKG tidak mengirim data prakiraan untuk wilayah ini');
  }
  final first = data.first as Map;
  final top = _asMap(root['lokasi']);
  final inner = _asMap(first['lokasi']);
  String pick(String key) => _s(top[key] ?? inner[key]);

  DateTime? analysis;
  final slots = <ForecastSlot>[];

  void addSlot(dynamic raw) {
    if (raw is! Map) return;
    final e = Map<String, dynamic>.from(raw);
    final utc = _parseUtc(_s(e['utc_datetime'])) ?? _parseUtc(_s(e['datetime']));
    if (utc == null) return;
    final wall = _parseUtc(_s(e['local_datetime'])) ?? utc.add(const Duration(hours: 7));
    analysis ??= _parseUtc(_s(e['analysis_date']));
    final vs = _d(e['vs']);
    final vsText = _s(e['vs_text']);
    final iconUrl = _s(e['image']);
    slots.add(ForecastSlot(
      utc: utc,
      wall: wall,
      desc: _s(e['weather_desc']).isEmpty ? '—' : _s(e['weather_desc']),
      descEn: _s(e['weather_desc_en']),
      temp: _d(e['t']),
      humidity: _i(e['hu']),
      cloud: _i(e['tcc']),
      rain: _d(e['tp']),
      code: _i(e['weather']),
      windKmh: _d(e['ws']),
      windFrom: _s(e['wd']),
      windTo: _s(e['wd_to']),
      windDeg: _i(e['wd_deg']),
      // Heuristik satuan: nilai >= 100 dianggap meter, selain itu km.
      visibilityKm: vs == null ? null : (vs >= 100 ? vs / 1000 : vs),
      visibilityText: vsText.isEmpty ? null : vsText,
      iconUrl: iconUrl.isEmpty ? null : iconUrl,
    ));
  }

  final cuaca = first['cuaca'];
  if (cuaca is List) {
    for (final group in cuaca) {
      if (group is List) {
        for (final e in group) {
          addSlot(e);
        }
      } else {
        addSlot(group);
      }
    }
  }
  if (slots.isEmpty) {
    throw const FormatException('daftar prakiraan kosong');
  }
  slots.sort((a, b) => a.utc.compareTo(b.utc));
  final seen = <int>{};
  slots.removeWhere((s) => !seen.add(s.utc.millisecondsSinceEpoch));

  // Selisih zona waktu dihitung dari slot itu sendiri (jam lokal - jam UTC).
  final offset = slots.first.wall.difference(slots.first.utc);

  return ForecastData(
    place: PlaceInfo(
      adm4: pick('adm4'),
      desa: pick('desa'),
      kecamatan: pick('kecamatan'),
      kotkab: pick('kotkab'),
      provinsi: pick('provinsi'),
      lat: _d(top['lat'] ?? inner['lat']),
      lon: _d(top['lon'] ?? inner['lon']),
      utcOffset: offset,
    ),
    slots: List<ForecastSlot>.unmodifiable(slots),
    analysisUtc: analysis,
  );
}

// ---------------------------------------------------------------- helper

List<DayForecast> groupByDay(List<ForecastSlot> slots) {
  final map = <DateTime, List<ForecastSlot>>{};
  for (final s in slots) {
    final key = DateTime.utc(s.wall.year, s.wall.month, s.wall.day);
    (map[key] ??= <ForecastSlot>[]).add(s);
  }
  return map.entries.map((e) => DayForecast.from(e.key, e.value)).toList();
}

/// Slot yang waktunya paling dekat dengan [nowUtc].
ForecastSlot currentSlot(List<ForecastSlot> slots, DateTime nowUtc) {
  var best = slots.first;
  var bestDiff = best.utc.difference(nowUtc).abs();
  for (final s in slots) {
    final d = s.utc.difference(nowUtc).abs();
    if (d < bestDiff) {
      best = s;
      bestDiff = d;
    }
  }
  return best;
}

ForecastSlot? nextRainSlot(List<ForecastSlot> slots, DateTime fromUtc) {
  for (final s in slots) {
    if (!s.utc.isBefore(fromUtc) && s.isRain) return s;
  }
  return null;
}
