import 'package:equatable/equatable.dart';

class Institution extends Equatable {
  const Institution({
    required this.id,
    required this.code,
    required this.name,
    this.commercialName,
    this.logoUrl,
    this.primaryColor,
    this.timezone = 'America/Managua',
    this.active = true,
  });

  final int id;
  final String code;
  final String name;

  /// Nombre comercial (el que se muestra en documentos si existe).
  final String? commercialName;
  final String? logoUrl;
  final String? primaryColor;
  final String timezone;
  final bool active;

  factory Institution.fromJson(Map<String, dynamic> json) {
    return Institution(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String,
      name: json['name'] as String,
      commercialName: json['commercial_name'] as String?,
      logoUrl: json['logo_url'] as String?,
      primaryColor: json['primary_color'] as String?,
      timezone: json['timezone'] as String? ?? 'America/Managua',
      active: json['active'] as bool? ?? true,
    );
  }

  /// Nombre a mostrar: el comercial si lo tiene; si no, el legal.
  String get displayName {
    final commercial = commercialName?.trim();
    return commercial == null || commercial.isEmpty ? name : commercial;
  }

  @override
  List<Object?> get props => [id, code, name, commercialName, logoUrl];
}
