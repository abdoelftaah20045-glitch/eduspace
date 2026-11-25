import 'dart:io';
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

const _kPrimary = Color(0xFF0F3D6E);
const _kPrimaryDark = Color(0xFF0A2A4D);
const _kGold = Color(0xFFC9A227);

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
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
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
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(6),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _kPrimary, width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(4),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: _kGold, width: 1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.school, size: 44, color: _kPrimary),
                      const SizedBox(height: 4),
                      const Text(
                        'EduSpace',
                        style: TextStyle(
                          color: _kPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        s.t('certificate_of_completion'),
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        s.t('this_certifies'),
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        cert.studentName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        s.t('has_completed'),
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        cert.courseTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _kPrimaryDark,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.t('issued_on'),
                                style: const TextStyle(
                                    color: Colors.black45, fontSize: 11),
                              ),
                              Text(
                                date,
                                style: const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          if (cert.hours != null && cert.hours! > 0)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  s.t('hours_label'),
                                  style: const TextStyle(
                                      color: Colors.black45, fontSize: 11),
                                ),
                                Text(
                                  '${cert.hours}',
                                  style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '${s.t('cert_number')}: ${cert.certificateNumber}',
                        style: const TextStyle(
                            color: Colors.black38, fontSize: 11),
                      ),
                    ],
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
