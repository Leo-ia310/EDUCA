import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/receipt_pdf_service.dart';
import 'domain/report_pdf_service.dart';

final reportPdfServiceProvider =
    Provider<ReportPdfService>((ref) => const ReportPdfService());

final receiptPdfServiceProvider =
    Provider<ReceiptPdfService>((ref) => const ReceiptPdfService());
