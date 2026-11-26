import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/l10n.dart';
import 'data/certificates_repo.dart';

const _kGold = Color(0xFFC9A227);

/// Deepen the theme accent for headings and the frame, keeping contrast
/// without going near-black.
Color _deepen(Color c, [double factor = 0.62]) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness * factor).clamp(0.0, 1.0)).toColor();
}

/// Full certificate view. The share button captures the certificate as a PNG
/// (so Arabic text renders correctly, no PDF font issues) and shares it.
class CertificateViewScreen extends StatefulWidget {
  const CertificateViewScreen({super.key, required this.cert});

  final Certificate cert;

  @override
  State<CertificateViewScreen> createState() => _CertificateViewScreenState();
}

class _CertificateViewScreenState extends State<CertificateViewScreen> {
  final _captureKey = GlobalKey();
  bool _sharing = false;
  bool _exporting = false;

  /// Public verification link encoded in the PDF's QR code.
  String get _verifyUrl =>
      '${AppConfig.supabaseUrl}/rest/v1/rpc/verify_certificate'
      '?apikey=${AppConfig.supabaseAnonKey}'
      '&p_number=${widget.cert.certificateNumber}';

  Future<Uint8List?> _capturePng() async {
    final boundary = _captureKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await _capturePng();
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/certificate-${widget.cert.certificateNumber}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (_) {
      // If sharing fails the student can still screenshot.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Exports a printable PDF: the captured certificate image (perfect Arabic
  /// rendering, no font-shaping issues) plus a QR code and the verification
  /// link under it.
  Future<void> _downloadPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final bytes = await _capturePng();
      if (bytes == null) return;
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => pw.Column(
            children: [
              pw.Expanded(
                child: pw.Center(child: pw.Image(pw.MemoryImage(bytes))),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Certificate: ${widget.cert.certificateNumber}',
                        style: const pw.TextStyle(
                            fontSize: 10, color: PdfColors.grey700),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Verify this certificate by scanning the QR code.',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: _verifyUrl,
                    width: 56,
                    height: 56,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'certificate-${widget.cert.certificateNumber}.pdf',
      );
    } catch (_) {
      // PDF export failed; PNG share is still available.
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cert = widget.cert;
    final date =
        DateFormat('d MMMM y', s.locale.languageCode).format(cert.issuedAt);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('certificate_of_completion')),
        actions: [
          IconButton(
            tooltip: s.t('download_pdf'),
            onPressed: _exporting ? null : _downloadPdf,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: s.t('share'),
            onPressed: _sharing ? null : _share,
            icon: _sharing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          RepaintBoundary(
            key: _captureKey,
            child: AspectRatio(
              aspectRatio: 960 / 680,
              child: ClipRect(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: 960,
                    height: 680,
                    child: _CertCard(cert: cert, date: date),
                  ),
                ),
              ),
            ),
          ),
          if (!cert.isValid)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                s.t('status_cancelled'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

/// Landscape certificate in the reference style: theme-accent + gold curves
/// on the edges, gold seal ribbon, signature and date lines.
/// Laid out on a fixed 960x680 canvas and scaled by FittedBox.
class _CertCard extends StatelessWidget {
  const _CertCard({required this.cert, required this.date});

  final Certificate cert;
  final String date;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final primaryDark = _deepen(primary);
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          Positioned.fill(
              child: CustomPaint(painter: _CertCurvesPainter(primary: primary))),
          // Thin double frame like the reference.
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: primary, width: 2),
              ),
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  border: Border.all(color: _kGold, width: 1),
                ),
              ),
            ),
          ),
          // Content.
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(150, 34, 40, 26),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school, size: 30, color: primary),
                      const SizedBox(width: 8),
                      Text(
                        'Deki',
                        style: TextStyle(
                          color: primary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    s.t('certificate_of_completion'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: primaryDark,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  Container(
                    width: 110,
                    height: 3,
                    margin: const EdgeInsets.symmetric(vertical: 14),
                    color: _kGold,
                  ),
                  Text(
                    s.t('this_certifies'),
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cert.studentName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.t('has_completed'),
                    style: const TextStyle(
                        color: Colors.black54, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cert.courseTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: primaryDark,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(left: 90, right: 230),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SignLine(
                          top: cert.hours != null && cert.hours! > 0
                              ? '${cert.hours} ${s.t('hours_label')}'
                              : '',
                          label: s.t('signature_label'),
                        ),
                        _SignLine(top: date, label: s.t('date_label')),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${s.t('cert_number')}: ${cert.certificateNumber}',
                    style: const TextStyle(
                        color: Colors.black38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          // Gold seal ribbon, bottom right over the accent corner.
          const Positioned(
            right: 44,
            bottom: 132,
            child: Icon(Icons.workspace_premium,
                size: 110, color: _kGold),
          ),
        ],
      ),
    );
  }
}

class _SignLine extends StatelessWidget {
  const _SignLine({required this.top, required this.label});

  final String top;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(top,
            style: const TextStyle(color: Colors.black87, fontSize: 14)),
        Container(
          width: 150,
          height: 1.5,
          margin: const EdgeInsets.only(top: 4, bottom: 4),
          color: Colors.black54,
        ),
        Text(label,
            style: const TextStyle(color: Colors.black45, fontSize: 13)),
      ],
    );
  }
}

/// Accent filled curves with a gold offset edge, top-left sweep and
/// bottom-right corner, matching the reference certificate.
class _CertCurvesPainter extends CustomPainter {
  const _CertCurvesPainter({required this.primary});

  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    Path leftShape(double topX, double midX, double bottomY) {
      return Path()
        ..moveTo(0, 0)
        ..lineTo(topX, 0)
        ..quadraticBezierTo(midX, h * 0.30, midX * 0.55, h * 0.55)
        ..quadraticBezierTo(midX * 0.2, h * 0.72, 0, bottomY)
        ..close();
    }

    // Gold edge behind the accent sweep (top-left).
    canvas.drawPath(
      leftShape(w * 0.27, w * 0.16, h * 0.92),
      Paint()..color = _kGold,
    );
    // Accent sweep.
    canvas.drawPath(
      leftShape(w * 0.24, w * 0.13, h * 0.86),
      Paint()..color = primary,
    );

    Path cornerShape(double startY, double ctrlX, double endX) {
      return Path()
        ..moveTo(w, startY)
        ..quadraticBezierTo(ctrlX, h * 0.62, endX, h)
        ..lineTo(w, h)
        ..close();
    }

    // Gold edge behind the accent corner (bottom-right).
    canvas.drawPath(
      cornerShape(h * 0.55, w * 0.90, w * 0.76),
      Paint()..color = _kGold,
    );
    // Accent corner.
    canvas.drawPath(
      cornerShape(h * 0.63, w * 0.93, w * 0.82),
      Paint()..color = primary,
    );
  }

  @override
  bool shouldRepaint(covariant _CertCurvesPainter oldDelegate) =>
      oldDelegate.primary != primary;
}
