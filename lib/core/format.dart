// Format tanggal/jam dan teks cuaca dalam Bahasa Indonesia (tanpa paket intl).

const List<String> _hari = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const List<String> _bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

String two(int n) => n.toString().padLeft(2, '0');

/// Semua fungsi di bawah menerima "jam dinding" lokasi (DateTime bertanda UTC
/// yang komponennya = waktu setempat), bukan zona waktu perangkat.
String fmtHm(DateTime wall) => '${two(wall.hour)}:${two(wall.minute)}';
String fmtDayName(DateTime wall) => _hari[wall.weekday - 1];
String fmtDayShort(DateTime wall) => _hari[wall.weekday - 1].substring(0, 3);
String fmtDate(DateTime wall) => '${wall.day} ${_bulan[wall.month - 1]}';
String fmtDateTimeWall(DateTime wall, String zone) =>
    '${fmtDayShort(wall)}, ${fmtDate(wall)} ${fmtHm(wall)} $zone';

String fmtNum(double? v, {int digits = 0, String empty = '—'}) =>
    v == null ? empty : v.toStringAsFixed(digits);

const Map<String, String> _arah = {
  'N': 'Utara',
  'NNE': 'Utara-Timur Laut',
  'NE': 'Timur Laut',
  'ENE': 'Timur-Timur Laut',
  'E': 'Timur',
  'ESE': 'Timur-Tenggara',
  'SE': 'Tenggara',
  'SSE': 'Selatan-Tenggara',
  'S': 'Selatan',
  'SSW': 'Selatan-Barat Daya',
  'SW': 'Barat Daya',
  'WSW': 'Barat-Barat Daya',
  'W': 'Barat',
  'WNW': 'Barat-Barat Laut',
  'NW': 'Barat Laut',
  'NNW': 'Utara-Barat Laut',
};

String windName(String code) => _arah[code.toUpperCase()] ?? code;

/// Emoji dipilih dari teks kondisi BMKG (bukan dari kode angka, karena kode
/// BMKG tidak dijamin konsisten dengan deskripsinya).
String weatherEmoji(String desc, {bool night = false}) {
  final d = desc.toLowerCase();
  if (d.contains('petir')) return '⛈️';
  if (d.contains('lebat')) return '🌧️';
  if (d.contains('hujan')) return d.contains('ringan') ? '🌦️' : '🌧️';
  if (d.contains('kabut') || d.contains('kabur') || d.contains('asap')) return '🌫️';
  if (d.contains('tebal')) return '☁️';
  if (d.contains('cerah berawan')) return night ? '☁️' : '🌤️';
  if (d.contains('berawan')) return night ? '☁️' : '⛅';
  if (d.contains('cerah')) return night ? '🌙' : '☀️';
  return '🌡️';
}
