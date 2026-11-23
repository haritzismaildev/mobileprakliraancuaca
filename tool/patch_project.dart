// Menyesuaikan proyek hasil `flutter create` (Android dan/atau iOS):
//  Android: izin INTERNET + lokasi di manifest utama (template Flutter hanya menaruh
//           INTERNET di manifest debug, sehingga APK release tidak bisa online tanpa ini),
//           <queries> untuk url_launcher, dan nama aplikasi.
//  iOS:     NSLocationWhenInUseUsageDescription di Info.plist (tanpa ini aplikasi ditutup
//           iOS saat meminta lokasi), nama aplikasi, dan target iOS dibatasi maksimal 15.0
//           agar bisa dipasang di perangkat dengan iPadOS 15 (mis. iPad Air 2).
//  Umum:    menghapus test/widget_test.dart bawaan (merujuk ke aplikasi contoh).
//
// Jalankan dari akar proyek:  dart run tool/patch_project.dart
import 'dart:io';

const double _maxIosTarget = 15.0;

void main() {
  var touched = false;

  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (manifest.existsSync()) {
    _patchAndroid(manifest);
    touched = true;
  }

  final plist = File('ios/Runner/Info.plist');
  if (plist.existsSync()) {
    _patchIos(plist);
    touched = true;
  }

  if (!touched) {
    stderr.writeln('Folder android/ maupun ios/ belum ada. Jalankan dulu: '
        'flutter create --org id.cuaca --project-name cuaca_kelurahan --platforms android,ios .');
    exit(1);
  }

  final sample = File('test/widget_test.dart');
  if (sample.existsSync()) sample.deleteSync();
}

void _patchAndroid(File manifest) {
  var xml = manifest.readAsStringSync();

  const permissions = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
  ];
  final missing = permissions.where((p) => !xml.contains('"$p"')).toList();
  if (missing.isNotEmpty) {
    final lines = missing.map((p) => '    <uses-permission android:name="$p"/>').join('\n');
    final open = RegExp(r'<manifest[^>]*>').firstMatch(xml);
    if (open == null) {
      stderr.writeln('Tag <manifest> tidak ditemukan.');
      exit(1);
    }
    xml = '${xml.substring(0, open.end)}\n$lines${xml.substring(open.end)}';
  }

  if (!xml.contains('<queries>')) {
    const queries = '''
<queries>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
    </queries>
    ''';
    final app = xml.indexOf('<application');
    if (app < 0) {
      stderr.writeln('Tag <application> tidak ditemukan.');
      exit(1);
    }
    xml = '${xml.substring(0, app)}$queries${xml.substring(app)}';
  }

  xml = xml.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Cuaca Kelurahan"');
  manifest.writeAsStringSync(xml);
  stdout.writeln('Android: manifest disesuaikan (izin ditambahkan: ${missing.length}).');
}

void _patchIos(File plist) {
  var xml = plist.readAsStringSync();

  if (!xml.contains('NSLocationWhenInUseUsageDescription')) {
    const entry = '''
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Lokasi dipakai untuk menentukan kelurahan/desa Anda dan menampilkan prakiraan cuaca setempat.</string>
''';
    final end = xml.lastIndexOf('</dict>');
    if (end < 0) {
      stderr.writeln('Info.plist tidak valid (tag </dict> tidak ditemukan).');
      exit(1);
    }
    xml = '${xml.substring(0, end)}$entry${xml.substring(end)}';
  }

  xml = xml.replaceFirstMapped(
    RegExp(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)'),
    (m) => '${m[1]}Cuaca Kelurahan${m[2]}',
  );
  plist.writeAsStringSync(xml);

  // Target iOS: hanya diturunkan (maks 15.0), tidak pernah dinaikkan.
  final pbx = File('ios/Runner.xcodeproj/project.pbxproj');
  if (pbx.existsSync()) {
    final src = pbx.readAsStringSync();
    final out = src.replaceAllMapped(RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);'), (m) {
      final v = double.tryParse(m[1]!) ?? _maxIosTarget;
      return v > _maxIosTarget ? 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;' : m[0]!;
    });
    if (out != src) pbx.writeAsStringSync(out);
  }
  final podfile = File('ios/Podfile');
  if (podfile.existsSync()) {
    final src = podfile.readAsStringSync();
    final out = src.replaceFirstMapped(
      RegExp(r"^(\s*)#?\s*platform :ios,\s*'([\d.]+)'", multiLine: true),
      (m) {
        final v = double.tryParse(m[2]!) ?? _maxIosTarget;
        return "${m[1]}platform :ios, '${v > _maxIosTarget ? '15.0' : m[2]}'";
      },
    );
    if (out != src) podfile.writeAsStringSync(out);
  }
  stdout.writeln('iOS: Info.plist dan target iOS (maks 15.0) disesuaikan.');
}
