import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/brutal.dart';
import '../../../core/widgets/educa_bottom_nav.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../dashboard/data/dashboard_data.dart';
import '../../dashboard/presentation/widgets/grades_block.dart';
import '../../dashboard/providers.dart';
import 'widgets/account_settings_menu.dart';

/// Perfil del alumno: identidad (avatar + nombre) + cuenta y notas. Las opciones de configuración viven en un menú
/// desplegable en la esquina.
class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final institution = ref.watch(authControllerProvider).institution;
    final data = ref.watch(studentDashboardProvider).valueOrNull ??
        StudentDashboardData.mock();

    return AppScaffold(
      padding: const EdgeInsets.only(bottom: 24),
      bottomNav: const EducaBottomNav(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero de identidad (full-bleed).
          _ProfileHero(
            name: user?.fullName ?? 'Invitado',
            role: user?.activeRole.label,
            institutionName: institution?.name,
            avatarUrl: user?.avatarUrl,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cuenta y ajustes
                const SectionHeader(title: 'Cuenta', accent: false),
                const SizedBox(height: 10),
                const AccountSettingsList(),
                const SizedBox(height: 24),

                // Notas
                const SectionHeader(title: 'Mis Notas', accent: false),
                const SizedBox(height: 8),
                GradesBlock(
                  grades: data.grades,
                  average: data.averageScore,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Identidad del perfil, sin fondo: avatar grande centrado, nombre, rol y chip
/// del colegio.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    this.role,
    this.institutionName,
    this.avatarUrl,
  });

  final String name;
  final String? role;
  final String? institutionName;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ink = Brutal.ink(context);
    // Ancho completo: el padre alinea a la izquierda y sin esto el bloque
    // se encogía a su contenido.
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          MediaQuery.paddingOf(context).top + 28,
          20,
          8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            UserAvatar(
              name: name,
              imageUrl: avatarUrl,
              size: 92,
              ringColor: palette.accentDeep,
            ),
            const SizedBox(height: 12),
            Text(
              name,
              textAlign: TextAlign.center,
              style: context.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (role != null) ...[
              const SizedBox(height: 2),
              Text(
                role!,
                style: context.textTheme.bodyMedium
                    ?.copyWith(color: palette.textMuted),
              ),
            ],
            if (institutionName != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  border: Border.all(color: ink, width: Brutal.border),
                ),
                child: Text(
                  institutionName!,
                  style: context.textTheme.labelMedium?.copyWith(
                    color: palette.accentDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
