import 'package:flutter/material.dart';

/// Tekst z atlasu z pogrubieniami `**…**` (jedyny znacznik Markdown, jaki tam zostaje).
class TekstMd extends StatelessWidget {
  const TekstMd(this.tekst, {super.key, this.styl});

  final String tekst;
  final TextStyle? styl;

  @override
  Widget build(BuildContext context) {
    final bazowy = styl ?? DefaultTextStyle.of(context).style;
    final czesci = tekst.split('**');
    return Text.rich(TextSpan(
      style: bazowy,
      children: [
        for (final (i, c) in czesci.indexed)
          TextSpan(text: c, style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold) : null),
      ],
    ));
  }
}

/// Punkt listy: kropka albo numer.
class Punkt extends StatelessWidget {
  const Punkt(this.tekst, {super.key, this.znak = '•', this.styl});

  final String tekst;
  final String znak;
  final TextStyle? styl;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 28, child: Text(znak, style: styl)),
            Expanded(child: TekstMd(tekst, styl: styl)),
          ],
        ),
      );
}
