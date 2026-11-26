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
import 'certificate_card.dart';
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
  const CertificateViewScreen(
      {super.key, required this.cert, this.siblings = const []});

  final Certificate cert;

  /// All language variants of the same course certificate (incl. [cert]).
  final List<Certificate> siblings;

  @override
  State<CertificateViewScreen> createState() => _CertificateViewScreenState();
}

class _CertificateViewScreenState extends State<CertificateViewScreen> {
  final _captureKey = GlobalKey();
  bool _sharing = false;
  bool _exporting = false;
  Map<String, dynamic>? _settings;
  late Certificate _cert = pickCertLang(
      widget.siblings.isEmpty ? [widget.cert] : widget.siblings, 'en');

  @override
  void initState() {
    super.initState();
    CertificatesRepository.settingsFor(_cert.courseId).then((v) {
      if (mounted) setState(() => _settings = v);
    });
  }

  String get _lang => _cert.lang;

  List<Certificate> get _variants {
    final l = widget.siblings.isEmpty ? [widget.cert] : [...widget.siblings];
    l.sort((a, b) => a.lang == 'en' ? -1 : (b.lang == 'en' ? 1 : 0));
    return l;
  }

  Widget _card(Certificate c) {
    final card = AspectRatio(
      aspectRatio: 960 / 680,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 960,
            height: 680,
            child: CertificateCard(
                cert: c,
                lang: c.lang,
                verifyUrl: '${AppConfig.supabaseUrl}/rest/v1/rpc/verify_certificate'
                    '?apikey=${AppConfig.supabaseAnonKey}'
                    '&p_number=${c.certificateNumber}',
                settings: _settings),
          ),
        ),
      ),
    );
    return c.id == _cert.id
        ? RepaintBoundary(key: _captureKey, child: card)
        : card;
  }

  /// Public verification link encoded in the PDF's QR code.
  String get _verifyUrl =>
      '${AppConfig.supabaseUrl}/rest/v1/rpc/verify_certificate'
      '?apikey=${AppConfig.supabaseAnonKey}'
      '&p_number=${_cert.certificateNumber}';

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
          '${dir.path}/certificate-${_cert.certificateNumber}.png');
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
                        'Certificate: ${_cert.certificateNumber}',
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
        filename: 'certificate-${_cert.certificateNumber}.pdf',
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
    final cert = _cert;
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
          for (final c in _variants)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GestureDetector(
                onTap: () => setState(() => _cert = c),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: (_variants.length > 1 && c.id == _cert.id)
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2),
                  ),
                  child: _card(c),
                ),
              ),
            ),
          if (_variants.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'PDF / share: ${_cert.lang == 'ar' ? 'العربية' : 'English'} (tap a certificate to choose)',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
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

