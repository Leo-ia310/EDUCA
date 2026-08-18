import 'package:equatable/equatable.dart';

/// Concepto por el que se genera un cargo (matrícula, mensualidad, uniforme,
/// libro, actividad extra).
class PaymentConcept extends Equatable {
  const PaymentConcept({
    required this.id,
    required this.name,
    required this.baseAmount,
    required this.currencyCode,
    required this.recurring,
    this.description,
    this.periodicity,
  });

  final String id;
  final String name;
  final String? description;
  final double baseAmount;
  final String currencyCode;
  final bool recurring;
  final String? periodicity; // 'monthly', 'yearly', 'one-time'

  @override
  List<Object?> get props => [id, name];
}

/// Estado de un cargo.
enum ChargeStatus {
  pending('Pendiente'),
  partial('Parcial'),
  paid('Pagado'),
  overdue('Vencido'),
  cancelled('Anulado');

  const ChargeStatus(this.label);
  final String label;
}

/// Método usado para un pago concreto.
enum PaymentMethod {
  card('Tarjeta', 'card'),
  transfer('Transferencia', 'transfer'),
  cash('Efectivo', 'cash'),
  wallet('Billetera digital', 'wallet');

  const PaymentMethod(this.label, this.code);
  final String label;
  final String code;
}

/// Estado de un pago.
enum PaymentStatus {
  pending('Procesando'),
  paid('Confirmado'),
  failed('Rechazado'),
  refunded('Reembolsado');

  const PaymentStatus(this.label);
  final String label;
}

/// Cargo generado para un estudiante. Corresponde a `charges` en Supabase.
class Charge extends Equatable {
  const Charge({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.conceptId,
    required this.conceptName,
    required this.description,
    required this.amount,
    required this.discount,
    required this.lateFee,
    required this.dueDate,
    required this.currencyCode,
    required this.status,
    required this.academicYear,
    this.paidAmount = 0,
  });

  final String id;
  final int studentId;
  final String studentName;
  final String conceptId;
  final String conceptName;
  final String description;
  final double amount;
  final double discount;
  final double lateFee;
  final double paidAmount;
  final DateTime dueDate;
  final String currencyCode;
  final ChargeStatus status;
  final String academicYear;

  double get totalAmount => amount - discount + lateFee;
  double get pending => (totalAmount - paidAmount).clamp(0, double.infinity);
  bool get isOverdue =>
      status != ChargeStatus.paid && DateTime.now().isAfter(dueDate);
  int get daysToDue => dueDate.difference(DateTime.now()).inDays;

  Charge copyWith({
    ChargeStatus? status,
    double? paidAmount,
    double? lateFee,
  }) {
    return Charge(
      id: id,
      studentId: studentId,
      studentName: studentName,
      conceptId: conceptId,
      conceptName: conceptName,
      description: description,
      amount: amount,
      discount: discount,
      lateFee: lateFee ?? this.lateFee,
      paidAmount: paidAmount ?? this.paidAmount,
      dueDate: dueDate,
      currencyCode: currencyCode,
      status: status ?? this.status,
      academicYear: academicYear,
    );
  }

  @override
  List<Object?> get props =>
      [id, status, paidAmount, dueDate, totalAmount];
}

/// Pago registrado (parcial o total) contra un [Charge].
class Payment extends Equatable {
  const Payment({
    required this.id,
    required this.uuid,
    required this.chargeId,
    required this.chargeConcept,
    required this.studentName,
    required this.method,
    required this.amount,
    required this.currencyCode,
    required this.status,
    required this.paidAt,
    required this.receiptNumber,
    this.reference,
    this.gatewayName,
    this.payerName,
  });

  final String id;
  final String uuid;
  final String chargeId;
  final String chargeConcept;
  final String studentName;
  final PaymentMethod method;
  final double amount;
  final String currencyCode;
  final PaymentStatus status;
  final DateTime paidAt;
  final String receiptNumber;
  final String? reference;
  final String? gatewayName;
  final String? payerName;

  @override
  List<Object?> get props => [id, status, amount, paidAt];
}

/// Balance consolidado del estudiante para el widget principal del padre.
class StudentBalance extends Equatable {
  const StudentBalance({
    required this.studentId,
    required this.studentName,
    required this.totalPending,
    required this.totalOverdue,
    required this.currencyCode,
    required this.overdueCount,
    required this.upcomingCount,
    this.nextDueCharge,
  });

  final int studentId;
  final String studentName;
  final double totalPending;
  final double totalOverdue;
  final int overdueCount;
  final int upcomingCount;
  final String currencyCode;
  final Charge? nextDueCharge;

  bool get inGoodStanding => totalOverdue == 0;

  @override
  List<Object?> get props => [studentId, totalPending, totalOverdue];
}

/// Datos del recibo que se pasan al PDF service.
class Receipt {
  const Receipt({
    required this.payment,
    required this.charge,
    required this.institutionName,
    required this.payerName,
    required this.gradeLevel,
    required this.issuedAt,
  });

  final Payment payment;
  final Charge charge;
  final String institutionName;
  final String payerName;
  final String gradeLevel;
  final DateTime issuedAt;
}

/// Métricas para el panel administrativo.
class DunningMetrics extends Equatable {
  const DunningMetrics({
    required this.totalOverdueAmount,
    required this.overdueCount,
    required this.collectedThisMonth,
    required this.expectedThisMonth,
    required this.currencyCode,
  });

  final double totalOverdueAmount;
  final int overdueCount;
  final double collectedThisMonth;
  final double expectedThisMonth;
  final String currencyCode;

  double get collectionRate =>
      expectedThisMonth == 0 ? 0 : collectedThisMonth / expectedThisMonth;

  @override
  List<Object?> get props =>
      [totalOverdueAmount, overdueCount, collectedThisMonth];
}
