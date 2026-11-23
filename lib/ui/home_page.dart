import 'package:flutter/material.dart';

import '../core/text_utils.dart';
import '../data/bmkg_service.dart';
import '../data/location_service.dart';
import '../data/models.dart';
import '../data/region.dart';
import '../state/app_controller.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.start();
  }

  Future<void> _openSearch() async {
    final index = c.index;
    if (index == null) return;
    final picked = await Navigator.of(context).push<Region>(
      MaterialPageRoute(builder: (_) => SearchPage(index: index)),
    );
    if (picked != null) await c.selectManual(picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final busy = c.locating || c.loading;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cuaca Kelurahan'),
            bottom: busy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(3),
                    child: LinearProgressIndicator(minHeight: 3),
                  )
                : null,
            actions: [
              IconButton(
                tooltip: 'Gunakan lokasi GPS saya',
                icon: const Icon(Icons.my_location),
                onPressed: c.locating || c.index == null ? null : c.detectLocation,
              ),
              IconButton(
                tooltip: 'Cari kelurahan/desa',
                icon: const Icon(Icons.search),
                onPressed: c.index == null ? null : _openSearch,
              ),
            ],
          ),
          body: _body(context),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    if (c.booting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Menyiapkan data wilayah…'),
          ],
        ),
      );
    }
    final result = c.forecast;
    if (result == null) return _emptyState(context);
    return RefreshIndicator(
      onRefresh: c.refresh,
      child: _content(context, result),
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    if (c.locating || c.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(c.locating ? 'Mendeteksi lokasi presisi lewat GPS…' : 'Mengambil prakiraan dari BMKG…'),
          ],
        ),
      );
    }
    final kind = c.failureKind;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🌤️', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 12),
            Text(
              c.error ?? 'Pilih lokasi untuk melihat prakiraan cuaca.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (kind == LocationFailureKind.deniedForever)
                  FilledButton(onPressed: c.openAppSettings, child: const Text('Buka pengaturan aplikasi'))
                else if (kind == LocationFailureKind.serviceOff)
                  FilledButton(onPressed: c.openLocationSettings, child: const Text('Aktifkan GPS'))
                else
                  FilledButton(
                    onPressed: c.place != null ? () => c.loadForecast(force: true) : c.detectLocation,
                    child: const Text('Coba lagi'),
                  ),
                OutlinedButton(
                  onPressed: c.index == null ? null : _openSearch,
                  child: const Text('Cari kelurahan/desa'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ForecastResult result) {
    final data = result.data;
    final place = data.place;
    final zone = place.zoneLabel;
    final nowUtc = DateTime.now().toUtc();
    final cur = currentSlot(data.slots, nowUtc);
    final upcoming = data.slots.where((s) => !s.utc.isBefore(cur.utc)).toList();
    final hourly = upcoming.take(9).toList();
    final days = groupByDay(data.slots);
    final wallNow = nowUtc.add(place.utcOffset);
    final todayKey = DateTime.utc(wallNow.year, wallNow.month, wallNow.day);
    DayForecast? today;
    for (final d in days) {
      if (d.date == todayKey) today = d;
    }
    final fix = c.fix;
    final analysis = data.analysisUtc;
    final lastSlot = data.slots.last;

    final notices = <Widget>[];
    final warning = result.warning;
    if (warning != null) {
      notices.add(NoticeBanner(
        text: 'Menampilkan data tersimpan. $warning',
        icon: Icons.cloud_off,
      ));
    }
    if (c.approxNote != null) {
      notices.add(NoticeBanner(text: c.approxNote!, icon: Icons.near_me_disabled));
    }
    if (fix != null && fix.mocked) {
      notices.add(const NoticeBanner(
        text: 'Perangkat memakai lokasi palsu (mock location). Prakiraan mungkin bukan untuk tempat Anda berada.',
        color: Colors.red,
        icon: Icons.warning_amber,
      ));
    }
    if (fix != null && fix.accuracyM > 100) {
      notices.add(NoticeBanner(
        text: 'Akurasi GPS rendah (±${fix.accuracyM.round()} m). Pindah ke area terbuka lalu tekan tombol lokasi '
            'agar kelurahan terdeteksi lebih tepat.',
        icon: Icons.gps_not_fixed,
      ));
    }
    if (analysis != null && nowUtc.difference(analysis) > const Duration(hours: 36)) {
      notices.add(const NoticeBanner(
        text: 'Analisis BMKG ini sudah lebih dari 36 jam. Kemungkinan data belum diperbarui; tarik layar ke bawah untuk memuat ulang.',
        icon: Icons.schedule,
      ));
    }
    if (lastSlot.utc.isBefore(nowUtc)) {
      notices.add(const NoticeBanner(
        text: 'Seluruh periode prakiraan yang tersimpan sudah lewat. Muat ulang saat terhubung internet.',
        icon: Icons.history,
      ));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        PlaceHeader(place: place, fix: fix),
        ...notices,
        const SizedBox(height: 8),
        CurrentCard(slot: cur, zone: zone),
        const SizedBox(height: 8),
        SummaryCard(
          nextRain: nextRainSlot(data.slots, cur.utc),
          today: today,
          zone: zone,
          horizonEnd: lastSlot.wall,
        ),
        const SectionTitle('Per 3 jam ke depan'),
        HourlyStrip(slots: hourly),
        const SectionTitle('Grafik suhu dan hujan (3 hari)'),
        TempChart(slots: upcoming.isEmpty ? data.slots : upcoming),
        const SectionTitle('Prakiraan harian'),
        for (final d in days) DayCard(day: d, isToday: d.date == todayKey),
        const SectionTitle('Satelit'),
        const SatelliteCard(),
        SourceFooter(result: result),
      ],
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.index});
  final RegionIndex index;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _ctl = TextEditingController();
  List<Region> _results = const <Region>[];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    setState(() => _results = widget.index.search(q));
  }

  @override
  Widget build(BuildContext context) {
    final query = _ctl.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Ketik nama kelurahan/desa…',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: query.length < 2
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Ketik minimal 2 huruf. Contoh: "lebak bulus" atau "sukasari bandung".',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _results.isEmpty
              ? const Center(child: Text('Tidak ada kelurahan/desa yang cocok.'))
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = _results[i];
                    return ListTile(
                      title: Text(prettyName(r.name)),
                      subtitle: Text(r.pathLabel),
                      trailing: Text(r.code, style: Theme.of(context).textTheme.labelSmall),
                      onTap: () => Navigator.of(context).pop(r),
                    );
                  },
                ),
    );
  }
}
