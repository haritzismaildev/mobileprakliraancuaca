import 'dart:math' as math;

/// Tingkat wilayah yang dipakai saat menormalkan nama untuk pencocokan.
enum RegionLevel { province, regency, local }

const Set<String> _regencyPrefix = {'kab', 'kabupaten', 'kota', 'adm', 'administrasi'};
const Set<String> _localPrefix = {'kec', 'kecamatan', 'kel', 'kelurahan', 'desa'};
const Set<String> _provincePrefix = {'provinsi', 'prov'};

const Map<String, String> _provinceAlias = {
  'daerah khusus ibukota jakarta': 'dki jakarta',
  'special capital region of jakarta': 'dki jakarta',
  'jakarta': 'dki jakarta',
  'di yogyakarta': 'daerah istimewa yogyakarta',
  'special region of yogyakarta': 'daerah istimewa yogyakarta',
  'yogyakarta': 'daerah istimewa yogyakarta',
  'bangka belitung': 'kepulauan bangka belitung',
  'bangka belitung islands': 'kepulauan bangka belitung',
  'riau islands': 'kepulauan riau',
};

/// Huruf kecil; hanya a-z dan 0-9 yang dipertahankan, selain itu menjadi satu spasi.
String fold(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  var lastSpace = true;
  for (var i = 0; i < lower.length; i++) {
    final c = lower.codeUnitAt(i);
    final isAlnum = (c >= 97 && c <= 122) || (c >= 48 && c <= 57);
    if (isAlnum) {
      buf.writeCharCode(c);
      lastSpace = false;
    } else if (!lastSpace) {
      buf.write(' ');
      lastSpace = true;
    }
  }
  return buf.toString().trim();
}

/// Menghapus awalan jenis wilayah (mis. "kota adm", "kecamatan") sesuai tingkatnya,
/// sehingga "Kota Adm. Jakarta Selatan" dan "Kota Jakarta Selatan" menjadi sama.
/// Hanya awalan di depan yang dibuang, agar nama seperti "Kota Baru" tetap utuh
/// pada tingkat kecamatan/desa.
String normalizeFor(String raw, RegionLevel level) {
  final f = fold(raw);
  switch (level) {
    case RegionLevel.province:
      final s = _stripLeading(f, _provincePrefix, expandKep: false);
      return _provinceAlias[s] ?? s;
    case RegionLevel.regency:
      return _stripLeading(f, _regencyPrefix, expandKep: true);
    case RegionLevel.local:
      return _stripLeading(f, _localPrefix, expandKep: false);
  }
}

String _stripLeading(String folded, Set<String> prefixes, {required bool expandKep}) {
  if (folded.isEmpty) return folded;
  final tokens = folded.split(' ');
  var start = 0;
  while (start < tokens.length - 1 && prefixes.contains(tokens[start])) {
    start++;
  }
  final out = <String>[];
  for (var i = start; i < tokens.length; i++) {
    final t = tokens[i];
    out.add(expandKep && t == 'kep' ? 'kepulauan' : t);
  }
  return out.join(' ');
}

/// +1 jika jenis (kota/kabupaten) cocok, -1 jika bertentangan, 0 jika tidak diketahui.
int regencyTypeHint(String foldedCandidate, String foldedRegion) {
  String? kind(String f) {
    final t = f.split(' ').first;
    if (t == 'kota') return 'kota';
    if (t == 'kab' || t == 'kabupaten') return 'kab';
    return null;
  }

  final a = kind(foldedCandidate);
  final b = kind(foldedRegion);
  if (a == null || b == null) return 0;
  return a == b ? 1 : -1;
}

/// Kemiripan 0..1. 1.0 = sama persis; mendekati 1 = salah ketik kecil;
/// 0.8 = salah satu nama seluruhnya termuat di nama lain; 0 = tidak mirip.
double similarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1.0;
  final maxLen = math.max(a.length, b.length);
  if ((a.length - b.length).abs() <= 0.15 * maxLen) {
    final ratio = 1 - _levenshtein(a, b) / maxLen;
    if (ratio >= 0.85) return ratio;
  }
  final sa = a.split(' ').toSet();
  final sb = b.split(' ').toSet();
  final inter = sa.intersection(sb).length;
  if ((inter == sa.length || inter == sb.length) && math.min(a.length, b.length) >= 5) {
    return 0.8;
  }
  return 0;
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = math.min(math.min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// Nama dari data Kemendagri sering HURUF BESAR; ubah ke huruf judul untuk tampilan.
String prettyName(String name) {
  if (name.contains(RegExp(r'[a-z]'))) return name;
  const keepUpper = {'DKI', 'DI', 'NTB', 'NTT'};
  return name.split(' ').map((w) {
    if (w.isEmpty || keepUpper.contains(w)) return w;
    final lower = w.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }).join(' ');
}
