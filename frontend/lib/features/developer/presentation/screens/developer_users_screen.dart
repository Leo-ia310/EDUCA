import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_scaffold.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state.dart';
import '../../domain/entities.dart';
import '../../providers.dart';

/// Área "Usuarios" (solo lectura): usuarios y sus roles sobre
/// `/api/developer/users`.
class DeveloperUsersScreen extends ConsumerWidget {
  const DeveloperUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final async = ref.watch(developerUsersProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Usuarios'),
      ),
      child: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (users) {
            final active = users.where((u) => u.active).length;
            return RefreshIndicator(
              color: palette.limeDeep,
              onRefresh: () async => ref.invalidate(developerUsersProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (users.isNotEmpty)
                    Text(
                      '$active de ${users.length} activos',
                      style: context.textTheme.labelLarge?.copyWith(
                        color: palette.textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (users.isEmpty)
                    const EmptyState(
                      icon: Icons.people_alt_outlined,
                      title: 'Sin usuarios',
                      subtitle: 'No hay usuarios registrados.',
                    )
                  else
                    for (final u in users)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _UserCard(user: u),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});
  final DevUser user;

  String get _initials {
    final base = (user.fullName ?? user.email ?? '?').trim();
    final parts = base.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return base.isEmpty ? '?' : base[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return EduCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: palette.limeDeep.withValues(alpha: 0.18),
                child: Text(
                  _initials,
                  style: context.textTheme.labelLarge?.copyWith(
                    color: palette.limeDeep,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName ?? user.email ?? 'Usuario',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (user.email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        user.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelSmall
                            ?.copyWith(color: palette.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatePill(active: user.active),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (user.roles.isEmpty)
                const _Meta(icon: Icons.shield_outlined, text: 'Sin rol')
              else
                for (final r in user.roles) _RolePill(role: r),
              if (user.lastSignIn != null)
                _Meta(
                  icon: Icons.login_rounded,
                  text: 'Últ. acceso ${_relative(user.lastSignIn!)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shield_outlined, size: 12, color: palette.info),
          const SizedBox(width: 3),
          Text(
            role,
            style: context.textTheme.labelSmall?.copyWith(
              color: palette.info,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = active ? palette.success : palette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'Activo' : 'Inactivo',
        style: context.textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.palette.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: c),
        const SizedBox(width: 3),
        Text(text,
            style: context.textTheme.labelSmall
                ?.copyWith(color: c, fontWeight: FontWeight.w600),),
      ],
    );
  }
}

String _relative(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays < 30) return 'hace ${diff.inDays} d';
  return DateFormat('d MMM y', 'es').format(d);
}
