import 'package:flutter/material.dart';

import '../data/climbs.dart';
import '../data/peaks_data.dart';
import '../data/peaks.dart';
import 'format.dart';
import 'peak_screen.dart';

/// Kółko przy szczycie na listach: zielone z ptaszkiem albo szare
class ClimbDot extends StatelessWidget {
  const ClimbDot({super.key, required this.climbed, this.custom = false, this.variant = false});

  final bool climbed;
  final bool custom;
  final bool variant;

  @override
  Widget build(BuildContext context) {
    final color = custom ? customColor : (climbed ? climbedColor : unclimbedColor);
    return CircleAvatar(
      radius: variant ? 15 : 18,
      backgroundColor: climbed || custom ? color : color.withValues(alpha: 0.15),
      child: Icon(
        climbed || custom ? Icons.check : Icons.landscape_outlined,
        size: variant ? 16 : 20,
        color: climbed || custom ? Colors.white : color,
      ),
    );
  }
}

/// Wiersz szczytu: zdobyty z datą, niezdobyty szary z wysokością
class PeakTile extends StatelessWidget {
  const PeakTile({super.key, required this.data, required this.peak, this.showRange = true});

  final PeaksData data;
  final Peak peak;
  final bool showRange;

  @override
  Widget build(BuildContext context) {
    final climb = data.climbOf(peak.id);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final details = [
      formatHeight(peak.h),
      if (showRange && peak.range.isNotEmpty) peak.range,
      ?peak.wikiNote,
    ].join(' · ');
    return ListTile(
      leading: ClimbDot(climbed: climb != null, variant: peak.isVariant),
      title: Text(
        peak.name,
        style: climb == null ? TextStyle(color: muted) : const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(details),
      trailing: climb == null ? null : ClimbDate(climb: climb),
      onTap: () => openPeak(context, data, peak),
    );
  }
}

/// Data zdobycia + ikona: satelita (GPS na szczycie) albo ołówek (dodany ręcznie)
class ClimbDate extends StatelessWidget {
  const ClimbDate({super.key, required this.climb});

  final Climb climb;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(formatShortDay(climb.date)),
        const SizedBox(width: 4),
        GpsIcon(gps: climb.gps),
      ],
    );
  }
}

class GpsIcon extends StatelessWidget {
  const GpsIcon({super.key, required this.gps, this.size = 16});

  final bool gps;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: gps ? 'Zaliczony na szczycie (GPS)' : 'Dodany ręcznie',
      child: Icon(
        gps ? Icons.satellite_alt_outlined : Icons.edit_calendar_outlined,
        size: size,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Pasek postępu z liczbą „12 / 28”
class ProgressLine extends StatelessWidget {
  const ProgressLine({super.key, required this.climbed, required this.counted, this.big = false});

  final int climbed;
  final int counted;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = counted == 0 ? 0.0 : (climbed / counted).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$climbed', style: (big ? theme.textTheme.displaySmall : theme.textTheme.headlineMedium)
                ?.copyWith(fontWeight: FontWeight.bold, color: climbedColor)),
            Text(' / $counted', style: big ? theme.textTheme.headlineSmall : theme.textTheme.titleLarge),
            const Spacer(),
            Text('${(fraction * 100).round()}%', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: big ? 12 : 8,
            color: climbedColor,
            backgroundColor: unclimbedColor.withValues(alpha: 0.25),
          ),
        ),
      ],
    );
  }
}

void openPeak(BuildContext context, PeaksData data, Peak peak) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PeakScreen(data: data, peak: peak)));
}

void openCustom(BuildContext context, PeaksData data, CustomPeak custom) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PeakScreen(data: data, custom: custom)));
}
