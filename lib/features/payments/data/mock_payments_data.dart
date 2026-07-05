import 'package:uuid/uuid.dart';

import '../domain/entities.dart';

const _uuid = Uuid();

DateTime _daysFromNow(int d) => DateTime.now().add(Duration(days: d));
DateTime _daysAgo(int d) => DateTime.now().subtract(Duration(days: d));

class PaymentsMockSeed {
  PaymentsMockSeed._();

  // ---------- Conceptos ----------
  static const concepts = <PaymentConcept>[
    PaymentConcept(
      id: 'c-matricula',
      name: 'Matrícula anual',
      description: 'Inscripción y derecho a matrícula 2026',
      baseAmount: 3500,
      currencyCode: 'NIO',
      recurring: false,
      periodicity: 'one-time',
    ),
    PaymentConcept(
      id: 'c-mensualidad',
      name: 'Mensualidad',
      description: 'Colegiatura mensual',
      baseAmount: 2500,
      currencyCode: 'NIO',
      recurring: true,
      periodicity: 'monthly',
    ),
    PaymentConcept(
      id: 'c-uniforme',
      name: 'Uniforme',
      description: 'Kit de uniforme escolar',
      baseAmount: 1200,
      currencyCode: 'NIO',
      recurring: false,
    ),
    PaymentConcept(
      id: 'c-libros',
      name: 'Libros de texto',
      description: 'Paquete anual de libros',
      baseAmount: 2100,
      currencyCode: 'NIO',
      recurring: false,
    ),
    PaymentConcept(
      id: 'c-actividad',
      name: 'Actividad extracurricular',
      description: 'Cuota especial de fin de bimestre',
      baseAmount: 350,
      currencyCode: 'NIO',
      recurring: false,
    ),
  ];

  // ---------- Cargos por estudiante ----------
  /// Cargos iniciales por estudiante. Ids estables para navegación.
  static List<Charge> initialCharges({required int studentId, required String studentName}) {
    final base = <Charge>[
      // Matrícula ya pagada
      Charge(
        id: 'chg-$studentId-matricula',
        studentId: studentId,
        studentName: studentName,
        conceptId: 'c-matricula',
        conceptName: 'Matrícula anual',
        description: 'Inscripción año lectivo 2026',
        amount: 3500,
        discount: 0,
        lateFee: 0,
        paidAmount: 3500,
        dueDate: _daysAgo(120),
        currencyCode: 'NIO',
        status: ChargeStatus.paid,
        academicYear: '2026',
      ),
      // Mensualidad mes anterior (pagada)
      Charge(
        id: 'chg-$studentId-mes-06',
        studentId: studentId,
        studentName: studentName,
        conceptId: 'c-mensualidad',
        conceptName: 'Mensualidad Junio',
        description: 'Colegiatura de junio 2026',
        amount: 2500,
        discount: 0,
        lateFee: 0,
        paidAmount: 2500,
        dueDate: _daysAgo(35),
        currencyCode: 'NIO',
        status: ChargeStatus.paid,
        academicYear: '2026',
      ),
      // Mensualidad vencida (con mora)
      Charge(
        id: 'chg-$studentId-mes-07',
        studentId: studentId,
        studentName: studentName,
        conceptId: 'c-mensualidad',
        conceptName: 'Mensualidad Julio',
        description: 'Colegiatura de julio 2026',
        amount: 2500,
        discount: 0,
        lateFee: 125,
        paidAmount: 0,
        dueDate: _daysAgo(3),
        currencyCode: 'NIO',
        status: ChargeStatus.overdue,
        academicYear: '2026',
      ),
      // Mensualidad próxima
      Charge(
        id: 'chg-$studentId-mes-08',
        studentId: studentId,
        studentName: studentName,
        conceptId: 'c-mensualidad',
        conceptName: 'Mensualidad Agosto',
        description: 'Colegiatura de agosto 2026',
        amount: 2500,
        discount: 0,
        lateFee: 0,
        paidAmount: 0,
        dueDate: _daysFromNow(12),
        currencyCode: 'NIO',
        status: ChargeStatus.pending,
        academicYear: '2026',
      ),
      // Actividad extracurricular
      Charge(
        id: 'chg-$studentId-actividad',
        studentId: studentId,
        studentName: studentName,
        conceptId: 'c-actividad',
        conceptName: 'Feria de Ciencias',
        description: 'Aporte a la Feria de Ciencias 2026',
        amount: 350,
        discount: 0,
        lateFee: 0,
        paidAmount: 0,
        dueDate: _daysFromNow(5),
        currencyCode: 'NIO',
        status: ChargeStatus.pending,
        academicYear: '2026',
      ),
    ];
    return base;
  }

  /// Pagos históricos ligados a los cargos ya pagados.
  static List<Payment> initialPayments({required int studentId, required String studentName}) {
    return [
      Payment(
        id: 'pay-$studentId-1',
        uuid: _uuid.v4(),
        chargeId: 'chg-$studentId-matricula',
        chargeConcept: 'Matrícula anual',
        studentName: studentName,
        method: PaymentMethod.transfer,
        amount: 3500,
        currencyCode: 'NIO',
        status: PaymentStatus.paid,
        paidAt: _daysAgo(118),
        receiptNumber: 'RC-2026-000132',
        reference: 'BAC-8837291',
        gatewayName: 'BAC Credomatic',
      ),
      Payment(
        id: 'pay-$studentId-2',
        uuid: _uuid.v4(),
        chargeId: 'chg-$studentId-mes-06',
        chargeConcept: 'Mensualidad Junio',
        studentName: studentName,
        method: PaymentMethod.card,
        amount: 2500,
        currencyCode: 'NIO',
        status: PaymentStatus.paid,
        paidAt: _daysAgo(33),
        receiptNumber: 'RC-2026-000284',
        reference: 'STR-889110023',
        gatewayName: 'Stripe',
      ),
    ];
  }

  /// Múltiples estudiantes para el panel admin de morosidad.
  static const _adminStudents = <({int id, String name, String grade})>[
    (id: 1001, name: 'Ana Martínez', grade: '4°A'),
    (id: 1002, name: 'Bruno García', grade: '4°A'),
    (id: 1003, name: 'Carla López', grade: '4°A'),
    (id: 1004, name: 'Diego Rivas', grade: '4°A'),
    (id: 1005, name: 'Elena Soto', grade: '4°A'),
    (id: 2001, name: 'María Castillo', grade: '4°B'),
    (id: 2002, name: 'Nicolás Ruiz', grade: '4°B'),
    (id: 3001, name: 'Vanessa Acosta', grade: '5°A'),
  ];

  static List<({int id, String name, String grade})> adminStudents() =>
      _adminStudents;
}
