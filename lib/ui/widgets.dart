import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../data/bmkg_service.dart';
import '../data/models.dart';
import '../state/app_controller.dart';

const String satellitePageUrl = 'https://www.bmkg.go.id/cuaca/satelit';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    );
  }
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.text,
    this.color = Colors.amber,
    this.icon = Icons.info_outline,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        border: Border.all(color: color.withAlpha(140)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class PlaceHeader extends StatelessWidget {
  const PlaceHeader({super.key, required this.place, required this.fix});
  final PlaceInfo place;
  final GpsFix? fix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = fix;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(place.desa, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Kec. ${place.kecamatan} · ${place.kotkab} · ${place.provinsi}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Text('📍'),
                  label: Text('Kode ${place.adm4}'),
                ),
                if (f != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Text('🛰️'),
                    label: Text('GPS ±${f.accuracyM.round()} m'),
                  ),
                if (place.lat != null && place.lon != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('Titik BMKG ${place.lat!.toStringAsFixed(3)}, ${place.lon!.toStringAsFixed(3)}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.emoji, this.label, this.value, {this.sub});
  final String emoji;
  final String label;
  final String value;
  final String? sub;
}

class CurrentCard extends StatelessWidget {
  const CurrentCard({super.key, required this.slot, required this.zone});
  final ForecastSlot slot;
  final String zone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = <_Metric>[
      _Metric('💧', 'Kelembapan', slot.humidity == null ? '—' : '${slot.humidity}%'),
      _Metric(
        '🌬️',
        'Angin',
        slot.windKmh == null ? '—' : '${slot.windKmh!.toStringAsFixed(1)} km/j',
        sub: slot.windFrom.isEmpty ? null : 'dari ${windName(slot.windFrom)}',
      ),
      _Metric('☁️', 'Tutupan awan', slot.cloud == null ? '—' : '${slot.cloud}%'),
      _Metric('🌧️', 'Curah hujan', slot.rain == null ? '—' : '${slot.rain!.toStringAsFixed(1)} mm'),
      _Metric('👁️', 'Jarak pandang', slot.visibilityLabel),
      _Metric(
        '🧭',
        'Arah angin',
        slot.windDeg == null ? '—' : '${slot.windDeg}°',
        sub: slot.windTo.isEmpty ? null : 'menuju ${windName(slot.windTo)}',
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(weatherEmoji(slot.desc, night: slot.isNight), style: const TextStyle(fontSize: 64)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        slot.temp == null ? '—' : '${slot.temp!.round()}°C',
                        style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(slot.desc, style: theme.textTheme.titleMedium),
                      Text('Prakiraan ${fmtDateTimeWall(slot.wall, zone)}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                final w = (c.maxWidth - 16) / 3;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final m in tiles) SizedBox(width: w, child: _MetricTile(metric: m))],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(140),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(metric.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(metric.value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(metric.label, style: theme.textTheme.bodySmall),
          if (metric.sub != null)
            Text(metric.sub!, style: theme.textTheme.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.nextRain,
    required this.today,
    required this.zone,
    required this.horizonEnd,
  });

  final ForecastSlot? nextRain;
  final DayForecast? today;
  final String zone;
  final DateTime horizonEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rain = nextRain;
    final t = today;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rain == null
                  ? '☀️ Tidak ada hujan diprakirakan hingga ${fmtDateTimeWall(horizonEnd, zone)}.'
                  : '🌧️ Hujan berikutnya: ${fmtDateTimeWall(rain.wall, zone)} (${rain.desc}'
                      '${rain.rain == null ? '' : ', ${rain.rain!.toStringAsFixed(1)} mm'}).',
              style: theme.textTheme.bodyLarge,
            ),
            if (t != null) ...[
              const SizedBox(height: 8),
              Text(
                'Hari ini: ${fmtNum(t.minTemp)}°–${fmtNum(t.maxTemp)}°C · '
                'potensi hujan di ${t.rainSlots} dari ${t.slots.length} slot prakiraan',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HourlyStrip extends StatelessWidget {
  const HourlyStrip({super.key, required this.slots});
  final List<ForecastSlot> slots;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 142,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slots.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = slots[i];
          final rain = s.rain;
          return Container(
            width: 78,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(i == 0 ? 220 : 120),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(i == 0 ? 'Terdekat' : fmtHm(s.wall), style: theme.textTheme.labelMedium),
                Text(fmtDayShort(s.wall), style: theme.textTheme.labelSmall),
                Text(weatherEmoji(s.desc, night: s.isNight), style: const TextStyle(fontSize: 28)),
                Text(s.temp == null ? '—' : '${s.temp!.round()}°',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(rain != null && rain > 0 ? '💧${rain.toStringAsFixed(1)}' : ' ',
                    style: theme.textTheme.labelSmall),
              ],
            ),
          );
        },
      ),
    );
  }
}

class TempChart extends StatelessWidget {
  const TempChart({super.key, required this.slots});
  final List<ForecastSlot> slots;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screen = MediaQuery.of(context).size.width;
    final width = math.max(screen - 64, slots.length * 54.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 214,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: CustomPaint(
              size: Size(width, 214),
              painter: _ChartPainter(
                slots: slots,
                line: cs.primary,
                rain: cs.tertiary,
                text: cs.onSurface,
                grid: cs.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.slots,
    required this.line,
    required this.rain,
    required this.text,
    required this.grid,
  });

  final List<ForecastSlot> slots;
  final Color line;
  final Color rain;
  final Color text;
  final Color grid;

  void _label(Canvas canvas, String s, Offset center, double size, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: text, fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.isEmpty) return;
    final temps = slots.map((s) => s.temp).whereType<double>().toList();
    if (temps.isEmpty) return;

    const top = 34.0;
    const labelsH = 40.0;
    const rainH = 26.0;
    final rainBase = size.height - labelsH;
    final chartBottom = rainBase - rainH - 10;
    final minT = temps.reduce(math.min);
    final maxT = temps.reduce(math.max);
    final span = math.max(maxT - minT, 2.0);
    final stepX = size.width / slots.length;

    double yOf(double t) => chartBottom - (t - minT) / span * (chartBottom - top);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, rainBase), Offset(size.width, rainBase), gridPaint);

    final path = Path();
    var started = false;
    for (var i = 0; i < slots.length; i++) {
      final t = slots[i].temp;
      if (t == null) continue;
      final p = Offset(stepX * (i + 0.5), yOf(t));
      if (started) {
        path.lineTo(p.dx, p.dy);
      } else {
        path.moveTo(p.dx, p.dy);
        started = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    final maxRain = slots.fold<double>(0.0, (m, s) => math.max(m, s.rain ?? 0.0));
    final dotPaint = Paint()..color = line;
    final rainPaint = Paint()..color = rain.withAlpha(170);

    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      final x = stepX * (i + 0.5);

      if (i > 0 && s.wall.day != slots[i - 1].wall.day) {
        canvas.drawLine(Offset(x - stepX / 2, top - 14), Offset(x - stepX / 2, size.height - 6), gridPaint);
      }
      final t = s.temp;
      if (t != null) {
        final y = yOf(t);
        canvas.drawCircle(Offset(x, y), 4, dotPaint);
        _label(canvas, '${t.round()}°', Offset(x, y - 14), 12, bold: true);
      }
      final r = s.rain ?? 0;
      if (r > 0 && maxRain > 0) {
        final h = math.max(3.0, rainH * (r / maxRain));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(x - 8, rainBase - h, x + 8, rainBase),
            const Radius.circular(3),
          ),
          rainPaint,
        );
      }
      _label(canvas, fmtHm(s.wall), Offset(x, rainBase + 12), 11);
      final newDay = i == 0 || s.wall.day != slots[i - 1].wall.day;
      if (newDay) {
        _label(canvas, '${fmtDayShort(s.wall)} ${s.wall.day}', Offset(x, rainBase + 28), 11, bold: true);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}

class DayCard extends StatelessWidget {
  const DayCard({super.key, required this.day, required this.isToday});
  final DayForecast day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rainText = day.rainSlots > 0
        ? ' · hujan di ${day.rainSlots}/${day.slots.length} slot (maks ${day.maxRain.toStringAsFixed(1)} mm)'
        : '';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Text(weatherEmoji(day.dominant.desc), style: const TextStyle(fontSize: 30)),
        title: Text(
          '${fmtDayName(day.date)}, ${fmtDate(day.date)}${isToday ? ' · Hari ini' : ''}',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${day.dominant.desc} · ${fmtNum(day.minTemp)}°–${fmtNum(day.maxTemp)}°C$rainText'),
        children: [for (final s in day.slots) _SlotRow(slot: s)],
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot});
  final ForecastSlot slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[
      if (slot.humidity != null) '💧${slot.humidity}%',
      if (slot.windKmh != null) '🌬️${slot.windKmh!.toStringAsFixed(0)} km/j ${slot.windFrom}',
      if (slot.rain != null && slot.rain! > 0) '🌧️${slot.rain!.toStringAsFixed(1)} mm',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(fmtHm(slot.wall), style: theme.textTheme.bodyMedium)),
          Text(weatherEmoji(slot.desc, night: slot.isNight), style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.desc, style: theme.textTheme.bodyMedium),
                if (parts.isNotEmpty) Text(parts.join('  '), style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          Text(slot.temp == null ? '—' : '${slot.temp!.round()}°',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class SatelliteCard extends StatelessWidget {
  const SatelliteCard({super.key});

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(Uri.parse(satellitePageUrl), mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger.showSnackBar(const SnackBar(content: Text('Tidak dapat membuka peramban.')));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Tidak dapat membuka peramban.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🛰️ Citra satelit Himawari-9', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Citra satelit adalah produk BMKG yang berhak cipta. Aplikasi ini membukanya di situs '
              'resmi BMKG (lengkap dengan logo dan atribusi) dan tidak menyalin atau memotong citranya.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: () => _open(context),
              child: const Text('Buka citra satelit BMKG'),
            ),
          ],
        ),
      ),
    );
  }
}

class SourceFooter extends StatelessWidget {
  const SourceFooter({super.key, required this.result});
  final ForecastResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = result.data;
    final zone = data.place.zoneLabel;
    final analysis = data.analysisUtc;
    final fetched = result.fetchedAt.toUtc().add(data.place.utcOffset);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sumber: BMKG', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'Data prakiraan cuaca terbuka BMKG (api.bmkg.go.id), tingkat kelurahan/desa, '
            'interval 3 jam, diperbarui BMKG dua kali sehari.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          if (analysis != null)
            Text('Analisis BMKG: ${fmtDateTimeWall(analysis.add(data.place.utcOffset), zone)}',
                style: theme.textTheme.bodySmall),
          Text(
            'Diambil: ${fmtDateTimeWall(fetched, zone)}${result.fromCache ? ' (dari penyimpanan perangkat)' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Aplikasi ini tidak resmi dan tidak berafiliasi dengan BMKG. Untuk peringatan dini dan '
            'keputusan keselamatan, rujuk kanal resmi BMKG. Kode wilayah: Kepmendagri 100.1.1-6117/2022.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
