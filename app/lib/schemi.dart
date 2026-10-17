import 'dart:math';
import 'package:flutter/material.dart';

class QSchema extends CustomPainter {
  final int q;
  QSchema(this.q);

  @override
  void paint(Canvas c, Size s) {
    final t = Paint()
      ..color = const Color(0xFF0F6F61)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final w = Paint()
      ..color = const Color(0xFF10231F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round;
    final f = Paint()..color = const Color(0xFFDDEDE9);
    final d = Paint()..color = const Color(0xFFE8704A);
    final cx = s.width / 2, cy = s.height / 2;
    if (q == 1) {
      for (final r in [12.0, 22.0, 32.0]) {
        c.drawCircle(Offset(cx, cy), r, t);
      }
      c.drawCircle(Offset(cx, cy), 4.5, d);
    } else if (q == 2) {
      final gy = s.height * 0.74;
      c.drawLine(Offset(4, gy), Offset(s.width - 4, gy), w);
      for (final r in [12.0, 24.0, 36.0]) {
        c.drawArc(Rect.fromCircle(center: Offset(cx, gy), radius: r), pi, pi, false, t);
      }
      c.drawCircle(Offset(cx, gy), 4.5, d);
    } else if (q == 4) {
      final gx = s.width * 0.26, gy = s.height * 0.78;
      c.drawLine(Offset(gx, 4), Offset(gx, gy), w);
      c.drawLine(Offset(gx, gy), Offset(s.width - 4, gy), w);
      for (final r in [14.0, 28.0, 42.0]) {
        c.drawArc(Rect.fromCircle(center: Offset(gx, gy), radius: r), -pi / 2, pi / 2, false, t);
      }
      c.drawCircle(Offset(gx, gy), 4.5, d);
    } else {
      final v = Offset(cx, cy + 8);
      final a = v + const Offset(-30, -17), b = v + const Offset(30, -17), dn = v + const Offset(0, 34);
      final top = v + const Offset(0, -34), l2 = v + const Offset(-30, 17), r2 = v + const Offset(30, 17);
      for (final face in [
        [v, a, top, b],
        [v, a, l2, dn],
        [v, b, r2, dn],
      ]) {
        final p = Path()..moveTo(face[0].dx, face[0].dy);
        for (var i = 1; i < face.length; i++) {
          p.lineTo(face[i].dx, face[i].dy);
        }
        p.close();
        c.drawPath(p, f);
        c.drawPath(p, w..strokeWidth = 2);
      }
      c.drawCircle(v, 4.5, d);
    }
  }

  @override
  bool shouldRepaint(QSchema o) => o.q != q;
}

class QSchemi extends StatelessWidget {
  const QSchemi({super.key});
  @override
  Widget build(BuildContext context) {
    const voci = [
      [1, 'Q=1', 'Aria libera'],
      [2, 'Q=2', 'Su un piano'],
      [4, 'Q=4', 'Spigolo (2 piani)'],
      [8, 'Q=8', 'Angolo (3 piani)'],
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          for (final v in voci)
            SizedBox(
              width: 140,
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFCFE0DC))),
                    child: SizedBox(width: 140, height: 84, child: CustomPaint(painter: QSchema(v[0] as int))),
                  ),
                  const SizedBox(height: 4),
                  Text('${v[1]} · ${v[2]}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF10231F))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
