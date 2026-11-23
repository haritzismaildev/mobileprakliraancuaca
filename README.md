# Cuaca Kelurahan

Aplikasi Android dan iOS/iPadOS (Flutter/Dart) untuk prakiraan cuaca tingkat **kelurahan/desa** dari data terbuka BMKG.
Lokasi dideteksi otomatis lewat GPS perangkat, lalu dipetakan ke kode wilayah (`adm4`) yang dipakai API BMKG.

## Status (baca dulu)

- Kode ini **belum dikompilasi dan belum dijalankan di perangkat**. Lingkungan tempat kode ditulis tidak punya
  Flutter, Android SDK, maupun Xcode. Yang sudah diperiksa: sintaksis semua berkas Dart lolos parser, dan algoritma
  pemetaan GPS ke kelurahan sudah diuji pada data Kemendagri asli (9 skenario, termasuk Kota vs Kabupaten Bandung).
- Build pertama di GitHub Actions sekaligus menjadi uji kompilasi pertama (`flutter analyze` + `flutter test`
  dijalankan sebelum APK dibuat). Bila ada galat, log-nya menunjuk baris yang perlu diperbaiki; biasanya kecil.
- Format JSON BMKG sudah dicocokkan dengan respons asli (`api.bmkg.go.id/publik/prakiraan-cuaca?adm4=31.74.06.1002`).

## Cara paling mudah: satu kali jalan di GitHub Actions (APK + IPA)

Tidak perlu memasang Flutter, Android Studio, ataupun Mac.

1. Buat repositori GitHub baru (privat boleh), unggah **seluruh isi folder ini** ke cabang `main`
   (termasuk folder tersembunyi `.github`).
2. Buka tab **Actions** → **Build APK dan IPA** → **Run workflow**. Tunggu sekitar 10–20 menit.
3. Setelah selesai, buka hasil run tersebut dan unduh dua artifact:
   - `cuaca-kelurahan-apk` → berisi `app-release.apk` (Android)
   - `cuaca-kelurahan-ipa` → berisi `cuaca_kelurahan_unsigned.ipa` (iPhone/iPad, **belum bertanda tangan**)

Catatan biaya: job iOS berjalan di mesin macOS. Repositori publik gratis; repositori privat memakai kuota menit
gratis GitHub dengan tarif macOS yang lebih mahal, tetapi cukup untuk beberapa kali build.

## Memasang di HP Android

1. Pindahkan `app-release.apk` ke HP (kabel USB, Drive, atau unduh langsung dari browser HP).
2. Buka berkasnya, izinkan **pasang dari sumber tidak dikenal** untuk aplikasi yang Anda pakai membukanya.
3. Buka **Cuaca Kelurahan**, izinkan lokasi (pilih "Presisi/Tepat" bila diminta), tunggu GPS terkunci.

## Memasang di iPad Air 2 (atau iPhone) tanpa App Store

IPA hasil build belum ditandatangani, jadi harus ditandatangani ulang dengan Apple ID Anda memakai **Sideloadly**
di laptop. Cara ini gratis, tetapi ada batasan dari Apple.

**Persiapan satu kali di laptop (Windows/macOS)**

1. Pasang **iTunes** dan **iCloud** dari situs apple.com (bukan versi Microsoft Store; Sideloadly memerlukan
   versi dari Apple di Windows).
2. Pasang **Sideloadly** dari sideloadly.io.
3. Siapkan Apple ID biasa (disarankan Apple ID khusus untuk ini).

**Pemasangan**

1. Sambungkan iPad ke laptop dengan kabel, pilih **Percayai** di iPad, lalu buka Sideloadly.
2. Seret `cuaca_kelurahan_unsigned.ipa` ke Sideloadly, masukkan Apple ID, klik **Start**.
3. Di iPad: **Pengaturan → Umum → VPN & Pengelolaan Perangkat** → pilih Apple ID Anda → **Percayai**.
4. Buka **Cuaca Kelurahan** di iPad.

**Batasan yang harus diketahui**

- Dengan Apple ID gratis, aplikasi **kedaluwarsa setelah 7 hari** dan harus dipasang ulang dengan cara yang sama.
  Maksimal 3 aplikasi sideload aktif per Apple ID.
- iPad Air 2 mentok di iPadOS 15.8.x. Aplikasi ini diatur untuk target iOS 15.0 (batas minimum Flutter), jadi
  seharusnya cocok, tetapi belum diuji di perangkat itu.
- **iPad Air 2 versi Wi-Fi saja tidak punya chip GPS.** Posisi hanya diperkirakan dari jaringan Wi-Fi sehingga bisa
  meleset ratusan meter sampai beberapa kilometer; aplikasi menampilkan peringatan bila akurasi > 100 m. Pada
  perangkat seperti itu, gunakan tombol cari untuk memilih kelurahan secara manual. Versi Wi-Fi + Cellular punya GPS.
- Build iOS dibuat dalam mode rilis (wajib untuk aplikasi sideload). Tidak ada mode debug/hot reload di perangkat.

## Build lokal (opsional)

**Android (Flutter terpasang)**

1. `flutter create --org id.cuaca --project-name cuaca_kelurahan --platforms android cuaca_app`
2. Salin `lib/`, `assets/`, `test/`, `tool/`, `pubspec.yaml`, `analysis_options.yaml` dari paket ini ke dalam
   `cuaca_app/` (timpa yang sudah ada).
3. Di dalam `cuaca_app/`:
   ```
   dart run tool/patch_project.dart
   flutter pub get
   flutter test
   flutter build apk --release
   ```
4. APK: `build/app/outputs/flutter-apk/app-release.apk`.

**iOS** memerlukan macOS + Xcode. Langkahnya sama, dengan `--platforms ios` pada `flutter create`, lalu
`flutter build ios --release --no-codesign`. Tanpa Mac, pakai jalur GitHub Actions di atas.

`tool/patch_project.dart` penting: di Android ia menambah izin INTERNET dan lokasi ke manifest utama (tanpa izin
INTERNET di manifest utama, APK release tidak bisa mengambil data); di iOS ia menambah teks izin lokasi
(`NSLocationWhenInUseUsageDescription`, tanpa ini iOS menutup aplikasi saat meminta lokasi) dan membatasi target
iOS maksimal 15.0.

## Cara kerja

1. GPS: `geolocator` mendengarkan posisi hingga akurasi ≤ 25 m (maksimal 20 detik), memakai fix terbaik.
2. Nama wilayah: reverse geocoding bawaan sistem (`geocoding`, locale `id_ID` bila didukung).
3. Pemetaan: `RegionIndex.resolve` mencocokkan nama secara berjenjang provinsi → kab/kota → kecamatan →
   kelurahan/desa terhadap `assets/wilayah_2022.csv` (91.589 baris, 83.761 kelurahan/desa). Awalan seperti
   "Kota Adm.", "Kecamatan", "Kelurahan" diabaikan; salah ketik kecil ditoleransi.
4. Data: `GET https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=<kode>`. Hasil disimpan di perangkat
   (30 menit segar; cadangan bila offline).
5. Tampilan: kondisi terdekat, 6 metrik, ringkasan hujan berikutnya, strip 3 jam, grafik suhu dan hujan,
   prakiraan 3 hari yang bisa dibuka per slot, waktu analisis BMKG, dan atribusi "Sumber: BMKG".

## Batasan yang jujur

- **Akurasi 99% tidak bisa dijanjikan.** Akurasi ditentukan oleh model prakiraan BMKG; aplikasi hanya
  menyajikannya apa adanya (interval 3 jam, tanpa interpolasi) dan menampilkan waktu analisisnya.
- **Tidak ada koneksi langsung ke satelit BMKG.** Citra Himawari-9 adalah produk BMKG berhak cipta, jadi
  aplikasi hanya membuka halaman satelit resmi BMKG. Menyematkan citra di dalam aplikasi butuh izin tertulis BMKG.
- **Deteksi kelurahan bergantung pada geocoder perangkat.** Tidak ada dataset koordinat per kelurahan yang sah dan
  terverifikasi. Bila nama tidak cocok persis, aplikasi menampilkan kelurahan pertama di kecamatan itu dan
  **menandainya sebagai perkiraan**; pengguna bisa memilih lewat tombol cari. Tanpa Google Play Services (Android)
  atau tanpa internet, geocoder bisa gagal, lalu pencarian manual yang dipakai.
- **Data BMKG**: diperbarui 2x sehari, batas 60 permintaan/menit/IP. Peringatan dini, jarak pandang, dan
  sebagian field bisa kosong (`null`) sehingga ditampilkan "—".
- **Izin penggunaan.** Ketentuan BMKG menyebut integrasi ke aplikasi pihak ketiga dan penggunaan komersial
  memerlukan izin tertulis resmi. Untuk pemakaian pribadi, pasang langsung; sebelum rilis publik
  (Play Store/App Store), urus izin ke BMKG.
- Tidak ada ikon aplikasi kustom; aplikasi memakai ikon Flutter bawaan.

## Sumber data dan atribusi

- Prakiraan cuaca: BMKG, data.bmkg.go.id (wajib mencantumkan "Sumber: BMKG"; sudah ada di layar utama).
- Kode wilayah: Kepmendagri 100.1.1-6117 Tahun 2022 (acuan resmi API BMKG), berkas CSV dari repositori
  `Tooya12/Kode-Wilayah-Indonesia` yang bersumber dari `cahyadsn/wilayah` (MIT). Periksa lisensi sebelum rilis publik.
- Aplikasi ini tidak resmi dan tidak berafiliasi dengan BMKG.
