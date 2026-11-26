import 'dart:math' as math;

import 'package:barcode/barcode.dart' as bc;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'data/certificates_repo.dart';

const _navy = Color(0xFF14264A);
const _blue = Color(0xFF2563EB);
const _gold = Color(0xFFC99A3C);
const _grey = Color(0xFF6E788C);

/// Fixed 960 x 680 certificate (scaled by the caller). One language per
/// certificate: 'ar' (RTL, Naskh) or 'en' (serif).
class CertificateCard extends StatelessWidget {
  const CertificateCard({
    super.key,
    required this.cert,
    required this.lang,
    required this.verifyUrl,
    this.settings,
  });

  final Certificate cert;
  final String lang;
  final String verifyUrl;
  final Map<String, dynamic>? settings;

  static const double w = 960;
  static const double h = 680;
  static const double k = 960 / 2000; // base design is 2000 px wide

  bool get _ar => lang == 'ar';

  String get _date {
    try {
      return DateFormat('d MMMM y', lang).format(cert.issuedAt);
    } catch (_) {
      return DateFormat('yyyy-MM-dd').format(cert.issuedAt);
    }
  }

  String? get _hours {
    final x = cert.hours;
    if (x == null || x <= 0) return null;
    final n = x == x.roundToDouble() ? x.toInt().toString() : x.toString();
    return _ar ? 'ومدته $n ساعة' : '$n hours';
  }

  Widget _t(String text, double y, double size, Color color,
      {String? family, FontWeight weight = FontWeight.w400, double cx = 1020}) {
    return Positioned(
      left: (cx - 900) * k,
      width: 1800 * k,
      top: y * k,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: family,
          fontSize: size * k,
          color: color,
          fontWeight: weight,
          height: 1.15,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tpl = (settings?['template_url'] as String?) ?? '';
    final children = <Widget>[];
    if (tpl.isNotEmpty) {
      children.add(Positioned.fill(
        child: Image.network(tpl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: Colors.white)),
      ));
      final light = settings?['text_color'] == 'light';
      final fg = light ? Colors.white : const Color(0xFF1B1B1B);
      final sub = light ? Colors.white70 : Colors.black54;
      final pos = (settings?['text_position'] as String?) ?? 'center';
      final off = pos == 'top' ? -140.0 : (pos == 'low' ? 120.0 : 0.0);
      children.addAll(_body(fg, sub, offset: off, decorated: false));
    } else {
      children.add(Positioned.fill(child: CustomPaint(painter: _FramePainter())));
      children.addAll(_body(_navy, _grey, offset: 0, decorated: true));
    }
    children.addAll(_footer(tpl.isEmpty));
    return Directionality(
      textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(clipBehavior: Clip.hardEdge, children: children),
      ),
    );
  }

  List<Widget> _body(Color fg, Color sub,
      {required double offset, required bool decorated}) {
    final fam = _ar ? 'NotoNaskhArabic' : 'serif';
    final out = <Widget>[];
    if (decorated) {
      out.add(Positioned(
        left: (1020 - 80) * k,
        top: 70 * k,
        width: 160 * k,
        height: 160 * k,
        child: Image.asset('assets/brand/logo_t.png', fit: BoxFit.contain),
      ));
    }
    final o = offset;
    if (_ar) {
      out.addAll([
        _t('شهادة إتمام', 215 + o, 140, fg, family: fam, weight: FontWeight.w700),
        _t('المعرفة حق للجميع', 440 + o, 36, _blue, family: 'Marhey'),
        _t('تقدّم منصة ذكي هذه الشهادة بكل فخر إلى', 520 + o, 50, sub, family: fam),
        _t(cert.studentName, 600 + o, 118, fg, family: fam, weight: FontWeight.w700),
        _t('لإتمامه بنجاح كورس', 800 + o, 46, sub, family: fam),
        _t(cert.courseTitle, 860 + o, 62, decorated ? _blue : fg,
            family: fam, weight: FontWeight.w700),
        if (_hours != null) _t(_hours!, 960 + o, 44, sub, family: fam),
      ]);
    } else {
      out.addAll([
        _t('CERTIFICATE', 225 + o, 100, fg, family: fam, weight: FontWeight.w800),
        _t('OF COMPLETION', 355 + o, 58, decorated ? _gold : sub, family: fam),
        _t('Knowledge is a right for everyone', 450 + o, 28, _blue),
        _t('This certificate is proudly presented to', 535 + o, 34, sub),
        _t(cert.studentName, 600 + o, 84, fg, family: fam, weight: FontWeight.w800),
        _t('for successfully completing the course', 770 + o, 34, sub),
        _t(cert.courseTitle, 820 + o, 58, decorated ? _blue : fg,
            weight: FontWeight.w700),
        if (_hours != null) _t(_hours!, 925 + o, 32, sub),
      ]);
    }
    return out;
  }

  List<Widget> _footer(bool decorated) {
    final dark = decorated ? _navy : const Color(0xFF1B1B1B);
    final fam = _ar ? 'NotoNaskhArabic' : null;
    final out = <Widget>[];
    // Signature (app name) and date lines.
    out.add(Positioned(
      left: (690 - 150) * k,
      top: (1210 - 215) * k,
      width: 300 * k,
      height: 200 * k,
      child: Image.asset(
          'assets/brand/sig_en.png',
          fit: BoxFit.contain),
    ));
    for (final x in [690.0, 1350.0]) {
      out.add(Positioned(
          left: (x - 150) * k,
          top: 1210 * k,
          width: 300 * k,
          height: 3 * k,
          child: ColoredBox(color: dark)));
    }
    out.add(_t(_ar ? 'منصة ذكي' : 'Deki', 1225, 30, dark,
        family: fam, cx: 690));
    out.add(_t(_ar ? 'التاريخ $_date' : 'Date: $_date', 1225, 30, dark,
        family: fam, cx: 1350));
    // QR + number.
    out.add(Positioned(
      left: 120 * k,
      top: 1060 * k,
      width: 240 * k,
      height: 270 * k,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16 * k)),
        child: Column(children: [
          Padding(
            padding: EdgeInsets.all(14 * k),
            child: SizedBox(
              width: 212 * k,
              height: 212 * k,
              child: CustomPaint(painter: _QrPainter(verifyUrl)),
            ),
          ),
          Text(cert.certificateNumber,
              style: TextStyle(
                  fontSize: 22 * k,
                  fontWeight: FontWeight.bold,
                  color: _navy)),
        ]),
      ),
    ));
    if (decorated) {
      out.add(Positioned.fill(child: CustomPaint(painter: _MedalPainter())));
      out.add(Positioned(
        left: (1640 - 50) * k,
        top: (1000 - 52) * k,
        width: 100 * k,
        height: 104 * k,
        child: Image.asset('assets/brand/logo_t.png', fit: BoxFit.contain),
      ));
    }
    return out;
  }
}

class _FramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 2000;
    final sy = size.height / 1414;
    Offset p(double x, double y) => Offset(x * sx, y * sy);
    canvas.drawRect(Offset.zero & size, Paint()..color = _navy);
    Path edge(double dx) => Path()
      ..moveTo(640 * sx + dx, 0)
      ..cubicTo(260 * sx + dx, 300 * sy, 70 * sx + dx, 900 * sy, 110 * sx + dx,
          1414 * sy);
    final white = Path()
      ..moveTo(640 * sx, 0)
      ..cubicTo(260 * sx, 300 * sy, 70 * sx, 900 * sy, 110 * sx, 1414 * sy)
      ..lineTo(1500 * sx, 1414 * sy)
      ..cubicTo(1780 * sx, 1100 * sy, 2050 * sx, 500 * sy, 1950 * sx, 0)
      ..close();
    canvas.drawPath(white, Paint()..color = Colors.white);
    final goldP = Paint()
      ..color = _gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * sx;
    canvas.drawPath(edge(0), goldP);
    canvas.drawPath(
        Path()
          ..moveTo(1500 * sx, 1414 * sy)
          ..cubicTo(1780 * sx, 1100 * sy, 2050 * sx, 500 * sy, 1950 * sx, 0),
        goldP..strokeWidth = 11 * sx);
    canvas.drawPath(
        edge(30 * sx),
        Paint()
          ..color = _blue
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * sx);
    canvas.drawRect(
        Rect.fromPoints(p(50, 50), p(1950, 1364)),
        Paint()
          ..color = const Color(0xFFE6CD8C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * sx);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MedalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 2000;
    final cx = 1640 * s;
    final cy = 1000 * s;
    final rib = Paint()..color = const Color(0xFF3A66CD);
    for (final d in [-45.0, 45.0]) {
      final r = d < 0 ? 1.0 : -1.0;
      canvas.drawPath(
          Path()
            ..moveTo((1640 + d - 30) * s, 1060 * s)
            ..lineTo((1640 + d + 30) * s, 1060 * s)
            ..lineTo((1640 + d + 30 - r * 20) * s, 1260 * s)
            ..lineTo((1640 + d) * s, 1215 * s)
            ..lineTo((1640 + d - 30 - r * 20) * s, 1260 * s)
            ..close(),
          rib);
    }
    final rose = Path();
    for (var i = 0; i < 48; i++) {
      final a = i * 2 * math.pi / 48;
      final r = (i % 2 == 0 ? 135 : 118) * s;
      final pt = Offset(cx + r * math.cos(a), cy + r * math.sin(a));
      if (i == 0) {
        rose.moveTo(pt.dx, pt.dy);
      } else {
        rose.lineTo(pt.dx, pt.dy);
      }
    }
    rose.close();
    canvas.drawPath(rose, Paint()..color = const Color(0xFF4879EC));
    canvas.drawCircle(Offset(cx, cy), 98 * s, Paint()..color = const Color(0xFF2454C4));
    canvas.drawCircle(
        Offset(cx, cy),
        86 * s,
        Paint()
          ..color = const Color(0xFFBED4FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 * s);
    canvas.drawCircle(Offset(cx, cy), 84 * s, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);

  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _navy;
    try {
      final els = bc.Barcode.qrCode().make(data,
          width: size.width, height: size.height, drawText: false);
      for (final e in els) {
        if (e is bc.BarcodeBar && e.black) {
          canvas.drawRect(
              Rect.fromLTWH(e.left, e.top, e.width, e.height), paint);
        }
      }
    } catch (_) {}
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
