import 'package:equatable/equatable.dart';

class Institution extends Equatable {
  const Institution({
    required this.id,
    required this.code,
    required this.name,
    this.logoUrl,
    this.primaryColor,
    this.timezone = 'America/Managua',
    this.active = true,
  });

  final int id;
  final String code;
  final String name;
  final String? logoUrl;
  final String? primaryColor;
  final String timezone;
  final bool active;

  factory Institution.fromJson(Map<String, dynamic> json) {
    return Institution(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      primaryColor: json['primary_color'] as String?,
      timezone: json['timezone'] as String? ?? 'America/Managua',
      active: json['active'] as bool? ?? true,
    );
  }

  @override
  List<Object?> get props => [id, code, name];
}
