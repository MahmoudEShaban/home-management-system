import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models.dart';
import '../l10n/strings.dart';
import 'common.dart' show formatMoney;

pw.Font? _regular;
pw.Font? _bold;

/// Renders an A4 invoice. Arabic invoices are laid out right-to-left with the
/// bundled Cairo font, so they render correctly offline.
Future<Uint8List> buildInvoicePdf({
  required Invoice invoice,
  required BusinessProfile profile,
  required bool arabic,
  Unit? unit,
  Property? property,
  String? billToName,
}) async {
  _regular ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Regular.ttf'));
  _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo-Bold.ttf'));

  final t = L10n(arabic);
  final locale = arabic ? 'ar' : 'en';
  final dir = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final endAlign = arabic ? pw.TextAlign.left : pw.TextAlign.right;
  final brand = PdfColor.fromInt(0xFF1F6F5C);
  final muted = PdfColors.grey700;
  String m(double v) => formatMoney(v, profile.currency, locale);
  String d(DateTime v) => DateFormat.yMMMd(locale).format(v);

  final doc = pw.Document(
    title: '${t.invoice} ${invoice.number}',
    author: profile.name,
    theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
  );

  pw.Widget label(String s) => pw.Text(s, style: pw.TextStyle(color: muted, fontSize: 9));
  pw.Widget value(String s, {bool bold = false}) => pw.Text(s,
      style: pw.TextStyle(fontSize: 11, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));

  final rentFor = invoice.period.isEmpty
      ? ''
      : DateFormat.yMMMM(locale).format(periodStart(invoice.period));

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    textDirection: dir,
    build: (context) => [
      // Header band
      pw.Container(
        padding: const pw.EdgeInsets.all(18),
        decoration: pw.BoxDecoration(color: brand, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(profile.name.isEmpty ? t.appName : profile.name,
                      style: pw.TextStyle(
                          color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  if (profile.address.isNotEmpty)
                    pw.Text(profile.address,
                        style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
                  if (profile.phone.isNotEmpty || profile.email.isNotEmpty)
                    pw.Text([profile.phone, profile.email].where((s) => s.isNotEmpty).join('  ·  '),
                        style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(t.invoice.toUpperCase(),
                    style: pw.TextStyle(
                        color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.Text(invoice.number,
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 20),

      // Bill-to and dates
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                label(t.billTo),
                value(
                    invoice.isMaintenance && invoice.requestedByName.isNotEmpty
                        ? invoice.requestedByName
                        : (billToName ?? unit?.name ?? ''),
                    bold: true),
                if (unit != null || property != null)
                  value([unit?.name, property?.name].whereType<String>().join(' · ')),
                if (property != null && property.address.isNotEmpty)
                  pw.Text(property.address, style: pw.TextStyle(color: muted, fontSize: 9)),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              label(t.issueDate),
              value(d(invoice.issueDate)),
              pw.SizedBox(height: 6),
              label(t.dueDate),
              value(d(invoice.dueDate)),
              if (rentFor.isNotEmpty) ...[
                pw.SizedBox(height: 6),
                label(t.forMonth),
                value(rentFor),
              ],
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 24),

      // Approved maintenance request: who asked, what, when, how much.
      if (invoice.isMaintenance) ...[
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: brand, width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(t.maintenanceRequest,
                style: pw.TextStyle(color: brand, fontWeight: pw.FontWeight.bold, fontSize: 12)),
            pw.SizedBox(height: 8),
            pw.Row(children: [
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  label(t.submittedByLabel),
                  value(invoice.requestedByName, bold: true),
                ]),
              ),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  label(t.category),
                  value(invoice.category == null ? '' : t.expenseCategory(invoice.category!)),
                ]),
              ),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  label(t.date),
                  value(invoice.workDate == null ? '' : d(invoice.workDate!)),
                ]),
              ),
              pw.Expanded(
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  label(t.totalCost),
                  value(m(invoice.total), bold: true),
                ]),
              ),
            ]),
          ]),
        ),
        pw.SizedBox(height: 20),
      ],

      // Items
      pw.Table(
        columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1.6)},
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(t.description, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(t.amount,
                    textAlign: endAlign, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
            ],
          ),
          for (final item in invoice.items)
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(item.description)),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(m(item.amount), textAlign: endAlign),
              ),
            ]),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        pw.Spacer(),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: brand, width: 1),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(children: [
            pw.Text('${t.total}   ', style: pw.TextStyle(color: muted)),
            pw.Text(m(invoice.total),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: brand)),
          ]),
        ),
      ]),
      if (invoice.status == InvoiceStatus.paid) ...[
        pw.SizedBox(height: 16),
        pw.Text(t.paid.toUpperCase(),
            style: pw.TextStyle(
                color: PdfColors.green700, fontSize: 16, fontWeight: pw.FontWeight.bold)),
      ],
      if (invoice.notes.isNotEmpty) ...[
        pw.SizedBox(height: 24),
        label(t.notes),
        pw.Text(invoice.notes),
      ],
      pw.SizedBox(height: 32),
      pw.Text(t.thankYou, style: pw.TextStyle(color: muted)),
    ],
  ));

  return doc.save();
}
