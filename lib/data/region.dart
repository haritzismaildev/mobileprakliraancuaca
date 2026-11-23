import 'package:flutter/services.dart' show rootBundle;

import '../core/text_utils.dart';

/// Satu entri wilayah Kemendagri (provinsi, kab/kota, kecamatan, atau kelurahan/desa).
/// Kode kelurahan/desa (13 karakter, mis. 31.74.06.1002) = parameter `adm4` BMKG.
class Region {
  Region(this.code, this.name) : norm = fold(name);

  final String code;
  final String name;
  final String norm;
  Region? parent;

  late final String normProvince = normalizeFor(name, RegionLevel.province);
  late final String normRegency = normalizeFor(name, RegionLevel.regency);
  late final String normLocal = normalizeFor(name, RegionLevel.local);

  /// 1 = provinsi, 2 = kab/kota, 3 = kecamatan, 4 = kelurahan/desa.
  int get level {
    switch (code.length) {
      case 2:
        return 1;
      case 5:
        return 2;
      case 8:
        return 3;
      default:
        return 4;
    }
  }

  /// "Kec. X, Kota Y, Provinsi Z"
  String get pathLabel {
    final kec = parent;
    final reg = kec?.parent;
    final prov = reg?.parent;
    return [
      if (kec != null) 'Kec. ${prettyName(kec.name)}',
      if (reg != null) prettyName(reg.name),
      if (prov != null) prettyName(prov.name),
    ].join(', ');
  }
}

enum MatchQuality { exact, approximate, none }

class ResolveResult {
  const ResolveResult({
    this.province,
    this.regency,
    this.kecamatan,
    this.desa,
    this.fallbackDesa,
    this.quality = MatchQuality.none,
  });

  final Region? province;
  final Region? regency;
  final Region? kecamatan;

  /// Kelurahan/desa yang cocok dengan nama dari geocoder (jika ditemukan).
  final Region? desa;

  /// Bila hanya kecamatan yang cocok: kelurahan/desa pertama di kecamatan itu,
  /// dipakai sebagai perkiraan (UI wajib menandainya).
  final Region? fallbackDesa;
  final MatchQuality quality;
}

class RegionIndex {
  RegionIndex._(this.byCode, this._children, this.provinces, this.regencies, this.villages);

  final Map<String, Region> byCode;
  final Map<String, List<Region>> _children;
  final List<Region> provinces;
  final List<Region> regencies;
  final List<Region> villages;

  static Future<RegionIndex> loadFromAsset() async {
    final text = await rootBundle.loadString('assets/wilayah_2022.csv');
    return RegionIndex.parse(text);
  }

  /// Format baris: `kode,nama` (nama boleh diapit tanda kutip).
  factory RegionIndex.parse(String csv) {
    final byCode = <String, Region>{};
    final children = <String, List<Region>>{};
    final provinces = <Region>[];
    final regencies = <Region>[];
    final villages = <Region>[];

    final text = csv.startsWith('﻿') ? csv.substring(1) : csv;
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final comma = line.indexOf(',');
      if (comma <= 0) continue;
      final code = line.substring(0, comma).trim();
      var name = line.substring(comma + 1).trim();
      if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
        name = name.substring(1, name.length - 1);
      }
      final region = Region(code, name);
      byCode[code] = region;
      switch (code.length) {
        case 2:
          provinces.add(region);
          break;
        case 5:
          regencies.add(region);
          break;
        case 13:
          villages.add(region);
          break;
      }
      final dot = code.lastIndexOf('.');
      if (dot > 0) {
        final parentCode = code.substring(0, dot);
        (children[parentCode] ??= <Region>[]).add(region);
        region.parent = byCode[parentCode];
      }
    }
    // Pengaman bila urutan berkas tidak hierarkis.
    for (final r in byCode.values) {
      if (r.parent == null) {
        final dot = r.code.lastIndexOf('.');
        if (dot > 0) r.parent = byCode[r.code.substring(0, dot)];
      }
    }
    return RegionIndex._(byCode, children, provinces, regencies, villages);
  }

  List<Region> childrenOf(String code) => _children[code] ?? const <Region>[];

  /// Cari kelurahan/desa dari teks bebas. Setiap kata harus muncul di nama
  /// kelurahan, kecamatan, kab/kota, atau provinsi. Urutan: sama persis,
  /// diawali, memuat, lalu cocok lewat hierarki.
  List<Region> search(String query, {int limit = 40}) {
    final q = fold(query);
    if (q.length < 2) return const <Region>[];
    final tokens = q.split(' ');
    final b0 = <Region>[];
    final b1 = <Region>[];
    final b2 = <Region>[];
    final b3 = <Region>[];
    for (final v in villages) {
      final kec = v.parent;
      final reg = kec?.parent;
      final prov = reg?.parent;
      final vn = v.norm;
      var ok = true;
      for (final t in tokens) {
        if (vn.contains(t)) continue;
        if (kec != null && kec.norm.contains(t)) continue;
        if (reg != null && reg.norm.contains(t)) continue;
        if (prov != null && prov.norm.contains(t)) continue;
        ok = false;
        break;
      }
      if (!ok) continue;
      if (vn == q) {
        b0.add(v);
      } else if (vn.startsWith(q)) {
        b1.add(v);
      } else if (vn.contains(q)) {
        b2.add(v);
      } else {
        b3.add(v);
      }
    }
    final out = <Region>[...b0, ...b1, ...b2, ...b3];
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  /// Memetakan nama-nama dari reverse geocoding (urutan bebas, boleh bercampur
  /// tingkat) ke kode wilayah, menurun: provinsi -> kab/kota -> kecamatan -> desa.
  ResolveResult resolve(List<String> rawNames) {
    final folded = <String>[];
    for (final r in rawNames) {
      final f = fold(r);
      if (f.isNotEmpty && !folded.contains(f)) folded.add(f);
    }
    if (folded.isEmpty) return const ResolveResult();

    final candProvince = folded.map((c) => normalizeFor(c, RegionLevel.province)).toList();
    final candRegency = folded.map((c) => normalizeFor(c, RegionLevel.regency)).toList();
    final candLocal = folded.map((c) => normalizeFor(c, RegionLevel.local)).toList();

    // 1. Provinsi
    Region? prov;
    var provBest = 0.0;
    for (final p in provinces) {
      for (final c in candProvince) {
        final s = similarity(p.normProvince, c);
        if (s > provBest) {
          provBest = s;
          prov = p;
        }
      }
    }
    if (provBest < 0.8) prov = null;

    // 2. Kabupaten/kota
    final regencyPool = prov != null ? childrenOf(prov.code) : regencies;
    Region? reg;
    var regBest = 0.0;
    for (final k in regencyPool) {
      for (var i = 0; i < folded.length; i++) {
        var s = similarity(k.normRegency, candRegency[i]);
        if (s <= 0) continue;
        s += 0.02 * regencyTypeHint(folded[i], k.norm);
        if (s > regBest) {
          regBest = s;
          reg = k;
        }
      }
    }
    if (regBest < 0.8) reg = null;
    if (reg == null) return ResolveResult(province: prov);

    // 3. Kecamatan
    final kecPool = childrenOf(reg.code);
    Region? kec;
    var kecBest = 0.0;
    for (final k in kecPool) {
      for (final c in candLocal) {
        final s = similarity(k.normLocal, c);
        if (s > kecBest) {
          kecBest = s;
          kec = k;
        }
      }
    }
    if (kecBest < 0.85) kec = null;

    // 4. Kelurahan/desa. Kandidat dibaca dari belakang agar subLocality
    //    (biasanya kelurahan) menang atas locality saat skornya sama.
    final villagePool = <Region>[];
    if (kec != null) {
      villagePool.addAll(childrenOf(kec.code));
    } else {
      for (final k in kecPool) {
        villagePool.addAll(childrenOf(k.code));
      }
    }
    Region? desa;
    var desaBest = 0.0;
    final reversed = candLocal.reversed.toList();
    for (final v in villagePool) {
      for (final c in reversed) {
        final s = similarity(v.normLocal, c);
        if (s > desaBest) {
          desaBest = s;
          desa = v;
        }
      }
    }
    if (desaBest < 0.85) desa = null;
    if (desa != null) kec = desa.parent;

    if (desa != null) {
      return ResolveResult(
        province: prov,
        regency: reg,
        kecamatan: kec,
        desa: desa,
        quality: MatchQuality.exact,
      );
    }
    if (kec != null) {
      final siblings = childrenOf(kec.code);
      return ResolveResult(
        province: prov,
        regency: reg,
        kecamatan: kec,
        fallbackDesa: siblings.isEmpty ? null : siblings.first,
        quality: siblings.isEmpty ? MatchQuality.none : MatchQuality.approximate,
      );
    }
    return ResolveResult(province: prov, regency: reg);
  }
}
