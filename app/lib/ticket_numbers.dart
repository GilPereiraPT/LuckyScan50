import 'package:flutter/material.dart';

class TicketNumbers extends StatelessWidget {
  const TicketNumbers({super.key, required this.numbers, required this.stars});
  final List<int> numbers, stars;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget ball(int value, bool star) => Semantics(
      label: '${star ? 'Estrela' : 'Número'} $value',
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: star
              ? const Color(0xffe7c77f)
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(star ? 10 : 18),
        ),
        child: Text(
          value.toString().padLeft(2, '0'),
          style: TextStyle(
            color: star ? const Color(0xff172841) : colors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 8,
          children: [for (final value in numbers) ball(value, false)],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.star_rounded, size: 18, color: Color(0xffe7c77f)),
            for (final value in stars) ball(value, true),
          ],
        ),
      ],
    );
  }
}
