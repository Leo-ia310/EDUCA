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

/// Área "Instituciones" (solo lectura): inventario de instituciones sobre
/// `/api/developer/institutions`.
class DeveloperInstitutionsScreen extends ConsumerWidget {
  const DeveloperInstitutionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final async = ref.watch(developerInstitutionsProvider);

    return AppScaffold(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Instituciones'),
      ),
      child: SafeArea(
        bottom: false,
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorStateView(message: '$e'),
          data: (items) => RefreshIndicator(
            color: palette.limeDeep,
            onRefresh: () async =>
                ref.invalidate(developerInstitutionsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (items.isEmpty)
                  const EmptyState(
                    icon: Icons.apartment_rounded,
                    title: 'Sin instituciones',
                    subtitle: 'No hay instituciones registradas.',
                  )
                else
                  for (final i in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _InstitutionCard(institution: i),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InstitutionCard extends StatelessWidget {
  const _InstitutionCard({required this.institution});
  final DevInstitution institution;

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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.apartment_rounded,
                    color: palette.info, size: 20,),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      institution.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      institution.code,
                      style: context.textTheme.labelSmall?.copyWith(
                        color: palette.textMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatePill(active: institution.active),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (institution.commercialName != null)
                _Meta(
                    icon: Icons.storefront_outlined,
                    text: institution.commercialName!,),
              if (institution.subdomain != null)
                _Meta(
                    icon: Icons.link_rounded, text: institution.subdomain!,),
              if (institution.email != null)
                _Meta(
                    icon: Icons.mail_outline_rounded,
                    text: institution.email!,),
              if (institution.timezone != null)
                _Meta(
                    icon: Icons.schedule_rounded, text: institution.timezone!,),
              if (institution.createdAt != null)
                _Meta(
                  icon: Icons.event_outlined,
                  text: DateFormat('d MMM y', 'es')
                      .format(institution.createdAt!),
                ),
            ],
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
        active ? 'Activa' : 'Inactiva',
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
