import 'package:cuaca_kelurahan/core/text_utils.dart';
import 'package:cuaca_kelurahan/data/models.dart';
import 'package:cuaca_kelurahan/data/region.dart';
import 'package:flutter_test/flutter_test.dart';

const String _csv = '''
31,"DKI JAKARTA"
31.01,"KAB. ADM. KEP. SERIBU"
31.01.01,"Kepulauan Seribu Selatan"
31.01.01.1001,"Pulau Tidung"
31.74,"KOTA ADM. JAKARTA SELATAN"
31.74.06,Cilandak
31.74.06.1001,"Cilandak Barat"
31.74.06.1002,"Lebak Bulus"
31.74.06.1003,"Pondok Labu"
32,"JAWA BARAT"
32.04,"KAB. BANDUNG"
32.04.01,Sukasari
32.04.01.2001,Gegerkalong Desa
32.73,"KOTA BANDUNG"
32.73.01,Sukasari
32.73.01.1001,Gegerkalong
32.73.01.1002,Isola
''';

const String _sampleJson = r'''
{
  "lokasi": {"adm1":"31","adm2":"31.74","adm3":"31.74.06","adm4":"31.74.06.1002",
    "desa":"Lebak Bulus","kecamatan":"Cilandak","kotkab":"Kota Adm. Jakarta Selatan",
    "lat":-6.3011231926,"lon":106.7789416104,"provinsi":"DKI Jakarta","timezone":"Asia/Jakarta"},
  "data": [{
    "lokasi": {"adm4":"31.74.06.1002","desa":"Lebak Bulus","timezone":"+0700","type":"adm4"},
    "cuaca": [
      [
        {"datetime":"2026-11-23T11:00:00Z","t":26,"tcc":99,"tp":2.7,"weather":61,
         "weather_desc":"Hujan Ringan","weather_desc_en":"Light Rain","wd_deg":196,"wd":"S","wd_to":"N",
         "ws":3.6,"hu":90,"vs":null,"vs_text":null,"time_index":"11-12",
         "analysis_date":"2026-11-23T00:00:00","image":"https://example.invalid/x.svg",
         "utc_datetime":"2026-11-23 11:00:00","local_datetime":"2026-11-23 18:00:00"},
        {"datetime":"2026-11-23T14:00:00Z","t":25,"tcc":80,"tp":0,"weather":3,
         "weather_desc":"Berawan","weather_desc_en":"Mostly Cloudy","wd_deg":180,"wd":"S","wd_to":"N",
         "ws":5.0,"hu":88,"vs":9000,"vs_text":"< 10 km","time_index":"14-15",
         "analysis_date":"2026-11-23T00:00:00","image":"",
         "utc_datetime":"2026-11-23 14:00:00","local_datetime":"2026-11-23 21:00:00"}
      ],
      [
        {"datetime":"2026-11-23T17:00:00Z","t":24,"tcc":60,"tp":0,"weather":1,
         "weather_desc":"Cerah Berawan","weather_desc_en":"Partly Cloudy","wd_deg":170,"wd":"SE","wd_to":"NW",
         "ws":4.0,"hu":85,"vs":10,"vs_text":"> 10 km","time_index":"17-18",
         "analysis_date":"2026-11-23T00:00:00","image":"",
         "utc_datetime":"2026-11-23 17:00:00","local_datetime":"2026-11-24 00:00:00"}
      ]
    ]
  }]
}
''';

void main() {
  group('text_utils', () {
    test('fold', () {
      expect(fold('Kota Adm. Jakarta Selatan'), 'kota adm jakarta selatan');
    });
    test('normalizeFor kab/kota', () {
      expect(normalizeFor('KAB. ADM. KEP. SERIBU', RegionLevel.regency), 'kepulauan seribu');
      expect(normalizeFor('Kota Jakarta Selatan', RegionLevel.regency), 'jakarta selatan');
    });
    test('normalizeFor menjaga nama "Kota Baru" pada tingkat kecamatan/desa', () {
      expect(normalizeFor('Kota Baru', RegionLevel.local), 'kota baru');
      expect(normalizeFor('Kelurahan Lebak Bulus', RegionLevel.local), 'lebak bulus');
    });
    test('similarity', () {
      expect(similarity('lebak bulus', 'lebak bulus'), 1.0);
      expect(similarity('lebak bulus', 'lebak bulos'), greaterThan(0.85));
      expect(similarity('cilandak', 'pondok labu'), 0);
    });
  });

  group('RegionIndex', () {
    final index = RegionIndex.parse(_csv);

    test('resolve lengkap (nama resmi geocoder)', () {
      final r = index.resolve(['Daerah Khusus Ibukota Jakarta', 'Kota Jakarta Selatan', 'Kecamatan Cilandak', 'Lebak Bulus']);
      expect(r.desa?.code, '31.74.06.1002');
      expect(r.quality, MatchQuality.exact);
    });

    test('resolve dengan awalan "Kelurahan" dan DKI', () {
      final r = index.resolve(['DKI Jakarta', 'Jakarta Selatan', 'Cilandak', 'Kelurahan Lebak Bulus']);
      expect(r.desa?.code, '31.74.06.1002');
    });

    test('hanya kecamatan -> perkiraan', () {
      final r = index.resolve(['Daerah Khusus Ibukota Jakarta', 'Kota Jakarta Selatan', 'Cilandak']);
      expect(r.desa, isNull);
      expect(r.kecamatan?.code, '31.74.06');
      expect(r.fallbackDesa, isNotNull);
      expect(r.quality, MatchQuality.approximate);
    });

    test('membedakan Kota vs Kabupaten Bandung', () {
      final kota = index.resolve(['Jawa Barat', 'Kota Bandung', 'Sukasari', 'Gegerkalong']);
      expect(kota.regency?.code, '32.73');
      expect(kota.desa?.code, '32.73.01.1001');
      final kab = index.resolve(['Jawa Barat', 'Kabupaten Bandung', 'Sukasari']);
      expect(kab.regency?.code, '32.04');
    });

    test('search', () {
      expect(index.search('lebak bulus').first.code, '31.74.06.1002');
      expect(index.search('cilandak').length, 3);
      expect(index.search('x'), isEmpty);
    });
  });

  group('parseForecast', () {
    final data = parseForecast(_sampleJson);

    test('tempat dan zona waktu', () {
      expect(data.place.adm4, '31.74.06.1002');
      expect(data.place.desa, 'Lebak Bulus');
      expect(data.place.zoneLabel, 'WIB');
    });

    test('slot dan field', () {
      expect(data.slots.length, 3);
      final first = data.slots.first;
      expect(first.temp, 26);
      expect(first.humidity, 90);
      expect(first.rain, 2.7);
      expect(first.isRain, isTrue);
      expect(first.windFrom, 'S');
      expect(first.wall.hour, 18);
      expect(data.slots[1].visibilityLabel, '< 10 km');
      expect(data.analysisUtc, DateTime.utc(2026, 11, 23));
    });

    test('pengelompokan per hari lokal', () {
      final days = groupByDay(data.slots);
      expect(days.length, 2);
      expect(days.first.slots.length, 2);
      expect(days.last.date, DateTime.utc(2026, 11, 24));
    });

    test('slot terdekat dan hujan berikutnya', () {
      final cur = currentSlot(data.slots, DateTime.utc(2026, 11, 23, 11, 8));
      expect(cur.temp, 26);
      expect(nextRainSlot(data.slots, DateTime.utc(2026, 11, 23, 12)), isNull);
    });

    test('struktur tidak valid melempar FormatException', () {
      expect(() => parseForecast('{"data": []}'), throwsFormatException);
      expect(() => parseForecast('[]'), throwsFormatException);
    });
  });
}
