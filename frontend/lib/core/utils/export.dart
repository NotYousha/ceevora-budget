import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_saver/file_saver.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Tabular export shared by every grid and report. Cells are already formatted strings except
/// numeric cells, which are passed as num for Excel so totals stay calculable.
class ExportTable {
  final String title;
  final List<String>
  subtitle; // company, branch, period, currency, generation date
  final List<String> headers;
  final List<List<Object?>> rows;
  ExportTable(this.title, this.subtitle, this.headers, this.rows);
}

String _fileName(String title) =>
    title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

Uint8List buildExcel(ExportTable t) {
  final book = xl.Excel.createExcel();
  final sheet = book[book.getDefaultSheet()!];
  sheet.appendRow([xl.TextCellValue(t.title)]);
  for (final s in t.subtitle) {
    sheet.appendRow([xl.TextCellValue(s)]);
  }
  sheet.appendRow([]);
  sheet.appendRow(t.headers.map((h) => xl.TextCellValue(h)).toList());
  for (final r in t.rows) {
    sheet.appendRow(
      r
          .map<xl.CellValue?>(
            (c) => c == null
                ? null
                : c is num
                ? xl.DoubleCellValue(c.toDouble())
                : xl.TextCellValue('$c'),
          )
          .toList(),
    );
  }
  return Uint8List.fromList(book.encode()!);
}

Future<void> exportExcel(ExportTable t) async {
  await FileSaver.instance.saveFile(
    name: _fileName(t.title),
    bytes: buildExcel(t),
    fileExtension: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}

Future<Uint8List> buildPdf(
  ExportTable t,
  PdfPageFormat format, {
  pw.Font? font,
}) async {
  final theme = font == null
      ? null
      : pw.ThemeData.withFont(base: font, bold: font);
  final doc = pw.Document(theme: theme);
  doc.addPage(
    pw.MultiPage(
      pageFormat: format.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (c) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            t.title,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          ...t.subtitle.map(
            (s) => pw.Text(s, style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.SizedBox(height: 8),
        ],
      ),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${c.pageNumber} / ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
      build: (c) => [
        pw.TableHelper.fromTextArray(
          headers: t.headers,
          data: t.rows
              .map(
                (r) => r
                    .map(
                      (c) => c == null
                          ? ''
                          : (c is num ? c.toStringAsFixed(2) : '$c'),
                    )
                    .toList(),
              )
              .toList(),
          headerStyle: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFF14284B),
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignments: {
            for (var i = 1; i < t.headers.length; i++)
              i: pw.Alignment.centerRight,
          },
        ),
      ],
    ),
  );
  return doc.save();
}

/// Print preview with print / save / share (works on Windows and web).
Future<void> previewPdf(BuildContext context, ExportTable t) async {
  pw.Font? font;
  try {
    // Arabic-capable font; needs internet the first time. Falls back to the built-in font offline.
    font = await PdfGoogleFonts.notoNaskhArabicRegular();
  } catch (_) {}
  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (c) => Dialog(
      child: SizedBox(
        width: 1000,
        height: 760,
        child: PdfPreview(
          build: (f) => buildPdf(t, f, font: font),
          pdfFileName: '${_fileName(t.title)}.pdf',
          canChangeOrientation: false,
          canDebug: false,
        ),
      ),
    ),
  );
}
