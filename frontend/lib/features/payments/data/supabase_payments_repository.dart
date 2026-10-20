import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/backend_api_client.dart';
import '../../../core/network/read_all.dart';
import '../domain/entities.dart';
import '../domain/payments_repository.dart';

/// Implementación real contra Supabase.
///
/// Tablas usadas (ver `supabase/migrations/0002_init_academic_extras.sql`):
/// `payment_concepts`, `charges`, `payments`. La pasarela de pago real
/// (procesador externo tipo Stripe) queda fuera de alcance — este repo solo
/// persiste el resultado de un cobro ya procesado por [PaymentGateway]
/// (sigue siendo `DemoPaymentGateway` hasta que se integre un proveedor real).
///
/// Nota: `payments` no tiene columnas para `payerName`/`gatewayName` (solo
/// `parent_id`, sin texto libre) — esos dos campos del dominio se devuelven
/// tal cual los pasó quien llama, pero no se persisten.
class SupabasePaymentsRepository implements PaymentsRepository {
  SupabasePaymentsRepository({
    required SupabaseClient client,
    required BackendApiClient api,
    required this.institutionId,
  })  : _c = client,
        _api = api;

  final SupabaseClient _c;
  final BackendApiClient _api;
  final int institutionId;

  static const _uuid = Uuid();

  static const _chargeSelect =
      'id, student_id, concept_id, description, amount, discount, late_fee, '
      'due_at, status, '
      'payment_concepts(name, catalog_currencies(iso_code)), '
      'students(persons(first_name, last_name)), academic_years(name)';

  static const _paymentSelect =
      'id, uuid, charge_id, student_id, payment_method, amount, reference, '
      'receipt_number, status, paid_at, catalog_currencies(iso_code), '
      'charges(description, payment_concepts(name)), '
      'students(persons(first_name, last_name))';

  // ---------- Padre / estudiante ----------
  @override
  Future<StudentBalance> balanceFor(int studentId) async {
    final charges = await chargesFor(studentId);
    final name = charges.isEmpty
        ? await _studentName(studentId)
        : charges.first.studentName;
    return _balanceFromCharges(studentId, charges, name);
  }

  StudentBalance _balanceFromCharges(
      int studentId, List<Charge> charges, String studentName,) {
    final active = charges
        .where(
          (c) =>
              c.status != ChargeStatus.paid &&
              c.status != ChargeStatus.cancelled,
        )
        .toList();
    final overdue = active.where((c) => c.isOverdue).toList();
    final upcoming = active.where((c) => !c.isOverdue).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    final currencyCode =
        charges.isNotEmpty ? charges.first.currencyCode : 'USD';

    return StudentBalance(
      studentId: studentId,
      studentName: studentName,
      totalPending: active.fold<double>(0, (a, c) => a + c.pending),
      totalOverdue: overdue.fold<double>(0, (a, c) => a + c.pending),
      currencyCode: currencyCode,
      overdueCount: overdue.length,
      upcomingCount: upcoming.length,
      nextDueCharge: upcoming.isEmpty ? null : upcoming.first,
    );
  }

  Future<String> _studentName(int studentId) async {
    final row = await _c
        .from('students')
        .select('persons(first_name, last_name)')
        .eq('id', studentId)
        .maybeSingle();
    final person = row?['persons'] as Map<String, dynamic>?;
    final name =
        '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''}'.trim();
    return name.isEmpty ? 'Estudiante' : name;
  }

  @override
  Future<List<Charge>> chargesFor(int studentId) async {
    return _charges(studentId: studentId);
  }

  Future<List<Charge>> _charges({int? studentId}) async {
    final charges = await readAllPages<Map<String, dynamic>>((from, to) async {
      var query = _c
          .from('charges')
          .select(_chargeSelect)
          .eq('institution_id', institutionId);
      if (studentId != null) query = query.eq('student_id', studentId);
      return await query.order('due_at').order('id').range(from, to);
    });
    final paidByCharge =
        await _paidAmountsByCharge(charges.map((c) => c['id']).toList());
    return charges
        .map((c) => _chargeFromRow(c, paidByCharge[c['id'].toString()] ?? 0))
        .toList();
  }

  @override
  Future<Charge?> chargeById(String id) async {
    final row = await _c
        .from('charges')
        .select(_chargeSelect)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final paid = await _paidAmountsByCharge([row['id']]);
    return _chargeFromRow(row, paid[row['id'].toString()] ?? 0);
  }

  Future<Map<String, double>> _paidAmountsByCharge(
    List<dynamic> chargeIds,
  ) async {
    if (chargeIds.isEmpty) return {};
    final map = <String, double>{};
    for (var i = 0; i < chargeIds.length; i += 200) {
      final rows = await _c.rpc('payment_charge_totals', params: {
        'p_charge_ids':
            chargeIds.sublist(i, (i + 200).clamp(0, chargeIds.length)),
      },);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final cid = r['charge_id']?.toString();
        if (cid == null) continue;
        map[cid] = (r['paid'] as num?)?.toDouble() ?? 0;
      }
    }
    return map;
  }

  Charge _chargeFromRow(Map<String, dynamic> row, double paidAmount) {
    final concept = row['payment_concepts'] as Map<String, dynamic>?;
    final currencyCode =
        (concept?['catalog_currencies'] as Map?)?['iso_code'] as String? ??
            'USD';
    final person = (row['students'] as Map?)?['persons'] as Map?;
    final studentName =
        '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''}'.trim();
    return Charge(
      id: row['id'].toString(),
      studentId: (row['student_id'] as num).toInt(),
      studentName: studentName.isEmpty ? 'Estudiante' : studentName,
      conceptId: row['concept_id'].toString(),
      conceptName: concept?['name'] as String? ?? 'Cargo',
      description: (row['description'] as String?) ??
          (concept?['name'] as String?) ??
          '',
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      discount: (row['discount'] as num?)?.toDouble() ?? 0,
      lateFee: (row['late_fee'] as num?)?.toDouble() ?? 0,
      paidAmount: paidAmount,
      dueDate:
          DateTime.tryParse(row['due_at'] as String? ?? '') ?? DateTime.now(),
      currencyCode: currencyCode,
      status: _chargeStatusFromDb(row['status'] as String?),
      academicYear: (row['academic_years'] as Map?)?['name'] as String? ?? '',
    );
  }

  ChargeStatus _chargeStatusFromDb(String? v) {
    for (final s in ChargeStatus.values) {
      if (s.name == v) return s;
    }
    return ChargeStatus.pending;
  }

  @override
  Future<List<Payment>> paymentsFor(int studentId) async {
    final rows = await readAllPages<Map<String, dynamic>>((from, to) async =>
        await _c
            .from('payments')
            .select(_paymentSelect)
            .eq('student_id', studentId)
            .eq('institution_id', institutionId)
            .order('paid_at', ascending: false)
            .order('id', ascending: false)
            .range(from, to),);
    return rows.map(_paymentFromRow).toList();
  }

  Payment _paymentFromRow(Map<String, dynamic> row) {
    final person = (row['students'] as Map?)?['persons'] as Map?;
    final studentName =
        '${person?['first_name'] ?? ''} ${person?['last_name'] ?? ''}'.trim();
    final charge = row['charges'] as Map<String, dynamic>?;
    final conceptName =
        (charge?['payment_concepts'] as Map?)?['name'] as String?;
    return Payment(
      id: row['id'].toString(),
      uuid: row['uuid'].toString(),
      chargeId: row['charge_id']?.toString() ?? '',
      chargeConcept:
          conceptName ?? (charge?['description'] as String?) ?? 'Pago',
      studentName: studentName.isEmpty ? 'Estudiante' : studentName,
      method: _methodFromDb(row['payment_method'] as String?),
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      currencyCode:
          (row['catalog_currencies'] as Map?)?['iso_code'] as String? ?? 'USD',
      status: _paymentStatusFromDb(row['status'] as String?),
      paidAt:
          DateTime.tryParse(row['paid_at'] as String? ?? '') ?? DateTime.now(),
      receiptNumber: row['receipt_number'] as String? ?? '',
      reference: row['reference'] as String?,
    );
  }

  PaymentMethod _methodFromDb(String? v) {
    for (final m in PaymentMethod.values) {
      if (m.code == v) return m;
    }
    return PaymentMethod.cash;
  }

  PaymentStatus _paymentStatusFromDb(String? v) {
    for (final s in PaymentStatus.values) {
      if (s.name == v) return s;
    }
    return PaymentStatus.pending;
  }

  // ---------- Escritura ----------
  @override
  Future<Payment> registerPayment({
    required String chargeId,
    required double amount,
    required PaymentMethod method,
    required String payerName,
    String? reference,
    String? gatewayName,
    String? idempotencyKey,
  }) async {
    final response = await _api.call(
      'payments.register',
      {
        'chargeId': chargeId,
        'amount': amount,
        'method': method.code,
        'payerName': payerName,
        'reference': reference,
        'gatewayName': gatewayName,
        'idempotencyKey': idempotencyKey ?? _uuid.v4(),
      },
    );
    final data = Map<String, dynamic>.from(response as Map);
    return _paymentFromApi(Map<String, dynamic>.from(data['payment'] as Map));
  }

  @override
  Future<void> cancelCharge(String chargeId) async {
    await _api.call('payments.cancelCharge', {'chargeId': chargeId});
  }

  // ---------- Admin ----------
  @override
  Future<List<StudentBalance>> allBalances() async {
    final byStudent = <int, List<Charge>>{};
    for (final charge in await _charges()) {
      byStudent.putIfAbsent(charge.studentId, () => []).add(charge);
    }
    return byStudent.entries
        .map((entry) => _balanceFromCharges(
            entry.key, entry.value, entry.value.first.studentName,),)
        .toList();
  }

  @override
  Future<DunningMetrics> dunningMetrics() async {
    final data =
        Map<String, dynamic>.from(await _api.get('/payments/summary') as Map);
    return DunningMetrics(
      totalOverdueAmount: (data['overdueAmount'] as num?)?.toDouble() ?? 0,
      overdueCount: (data['overdueCount'] as num?)?.toInt() ?? 0,
      collectedThisMonth: (data['collectedThisMonth'] as num?)?.toDouble() ?? 0,
      expectedThisMonth: (data['expectedThisMonth'] as num?)?.toDouble() ?? 0,
      currencyCode: data['currencyCode'] as String? ?? 'USD',
    );
  }

  Payment _paymentFromApi(Map<String, dynamic> row) {
    return Payment(
      id: row['id'].toString(),
      uuid: row['uuid'].toString(),
      chargeId: row['chargeId']?.toString() ?? '',
      chargeConcept: row['chargeConcept'] as String? ?? 'Pago',
      studentName: row['studentName'] as String? ?? 'Estudiante',
      method: _methodFromDb(row['method'] as String?),
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      currencyCode: row['currencyCode'] as String? ?? 'USD',
      status: _paymentStatusFromDb(row['status'] as String?),
      paidAt:
          DateTime.tryParse(row['paidAt'] as String? ?? '') ?? DateTime.now(),
      receiptNumber: row['receiptNumber'] as String? ?? '',
      reference: row['reference'] as String?,
      gatewayName: row['gatewayName'] as String?,
      payerName: row['payerName'] as String?,
    );
  }
}
