import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/backend_reports_repository.dart';
import 'domain/receipt_pdf_service.dart';
import 'domain/report_pdf_service.dart';

final reportPdfServiceProvider =
    Provider<ReportPdfService>((ref) => const ReportPdfService());

final receiptPdfServiceProvider =
    Provider<ReceiptPdfService>((ref) => const ReceiptPdfService());

final reportsRepositoryProvider = backendReportsRepositoryProvider;
