import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Normalised coordinates of the visible receipt (not fixed camera pixels).
/// Point order: top-left, top-right, bottom-right, bottom-left.
@immutable
class ReceiptCorner {
  const ReceiptCorner(this.x, this.y);
  final double x, y;
  ReceiptCorner shifted(double dx, double dy) =>
      ReceiptCorner((x + dx).clamp(0.0, 1.0), (y + dy).clamp(0.0, 1.0));
}

bool validReceiptQuadrilateral(List<ReceiptCorner> points) {
  if (points.length != 4 ||
      points.any((p) => !p.x.isFinite || !p.y.isFinite ||
          p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1)) {
    return false;
  }
  var area = 0.0;
  double? sign;
  for (var i = 0; i < 4; i++) {
    final a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4];
    area += a.x * b.y - a.y * b.x;
    final cross = (b.x - a.x) * (c.y - b.y) -
        (b.y - a.y) * (c.x - b.x);
    if (cross.abs() < .0001) return false;
    if (sign == null) {
      sign = cross;
    } else if (cross * sign <= 0) {
      return false;
    }
  }
  // Reject crossed, degenerate or almost invisible receipt boundaries.
  return area.abs() >= .12;
}

const initialReceiptCorners = [
  ReceiptCorner(.06, .05),
  ReceiptCorner(.94, .05),
  ReceiptCorner(.94, .95),
  ReceiptCorner(.06, .95),
];

/// The image is EXIF-upright before arriving here. Drag corners onto the
/// actual paper border; this UI never guesses a paper edge or a lottery value.
class ReceiptCornersPage extends StatefulWidget {
  const ReceiptCornersPage({
    super.key,
    required this.path,
    required this.width,
    required this.height,
  });
  final String path;
  final double width, height;

  @override
  State<ReceiptCornersPage> createState() => _ReceiptCornersPageState();
}

class _ReceiptCornersPageState extends State<ReceiptCornersPage> {
  List<ReceiptCorner> points = List.of(initialReceiptCorners);
  static const names = ['Superior esquerdo', 'Superior direito',
    'Inferior direito', 'Inferior esquerdo'];

  @override
  Widget build(BuildContext context) {
    final valid = validReceiptQuadrilateral(points);
    return Scaffold(
      appBar: AppBar(title: const Text('Enquadrar o talão')),
      body: SafeArea(child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'Arraste os quatro pontos verdes até aos cantos do papel. '
            'Todo o talão deve estar visível. Pode ampliar a fotografia noutra '
            'aplicação antes de a importar se estiver desfocada.',
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(child: LayoutBuilder(builder: (context, bounds) {
          final aspect = widget.width / widget.height;
          final width = math.min(bounds.maxWidth - 20, (bounds.maxHeight - 12) * aspect);
          final height = width / aspect;
          return Center(child: SizedBox(
            width: width, height: height,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(widget.path),
                  fit: BoxFit.fill,
                  cacheWidth: 1200,
                  gaplessPlayback: true,
                ),
              )),
              Positioned.fill(child: IgnorePointer(child: CustomPaint(
                painter: _CornersPainter(points),
              ))),
              for (var i = 0; i < 4; i++)
                Positioned(
                  left: points[i].x * width - 24,
                  top: points[i].y * height - 24,
                  child: Semantics(
                    label: names[i],
                    child: GestureDetector(
                      key: Key('receipt-corner-$i'),
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (event) => setState(() {
                        points[i] = points[i].shifted(
                          event.delta.dx / width, event.delta.dy / height,
                        );
                      }),
                      child: Container(
                        width: 48, height: 48,
                        alignment: Alignment.center,
                        child: Container(
                          width: 19, height: 19,
                          decoration: BoxDecoration(
                            color: valid ? const Color(0xff2cbd87) : Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black54)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ));
        })),
        if (!valid)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Moldura inválida: afaste os cantos e evite cruzar os lados.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.orange)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Wrap(alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8, runSpacing: 4, children: [
              TextButton.icon(onPressed: () => setState(() =>
                  points = List.of(initialReceiptCorners)),
                icon: const Icon(Icons.restart_alt), label: const Text('Repor')),
              TextButton(onPressed: () => Navigator.pop(context, <ReceiptCorner>[]),
                child: const Text('Usar original')),
              FilledButton.icon(
                onPressed: valid ? () =>
                    Navigator.pop(context, List<ReceiptCorner>.of(points)) : null,
                icon: const Icon(Icons.check),
                label: const Text('Corrigir perspetiva'),
              ),
            ],
          ),
        ),
      ])),
    );
  }
}

class _CornersPainter extends CustomPainter {
  const _CornersPainter(this.points);
  final List<ReceiptCorner> points;

  @override
  void paint(Canvas canvas, Size size) {
    final vertices = [
      for (final p in points) Offset(p.x * size.width, p.y * size.height),
    ];
    final boundary = Path()..moveTo(vertices.first.dx, vertices.first.dy);
    for (final v in vertices.skip(1)) {
      boundary.lineTo(v.dx, v.dy);
    }
    boundary.close();
    final shade = Path()..addRect(Offset.zero & size)..addPath(boundary, Offset.zero);
    shade.fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = Colors.black.withValues(alpha: .53));
    canvas.drawPath(boundary, Paint()
      ..color = validReceiptQuadrilateral(points)
          ? const Color(0xff2cbd87) : Colors.orange
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _CornersPainter oldDelegate) =>
      oldDelegate.points != points;
}
