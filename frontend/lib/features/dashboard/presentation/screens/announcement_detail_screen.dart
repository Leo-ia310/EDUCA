import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/route_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/floating_card.dart';
import '../../data/mock_dashboard_data.dart';
import '../widgets/student_chrome.dart';

/// Detalle de un anuncio. Destino del container-transform desde la tarjeta de
/// anuncio del dashboard del admin.
class AnnouncementDetailScreen extends StatelessWidget {
  const AnnouncementDetailScreen({super.key, required this.announcement});
  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return StudentDetailScaffold(
      title: 'Anuncio',
      bottomNav: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FloatingCard(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: palette.accentSoft,
                borderRadius: BorderRadius.circular(Radii.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: palette.accentDeep.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Icon(Icons.campaign_rounded,
                        color: palette.accentDeep, size: 26,),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    announcement.title,
                    style: context.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            announcement.body,
            style: context.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.announcements),
            icon: const Icon(Icons.list_alt_rounded),
            label: const Text('Ver todos los anuncios'),
          ),
        ],
      ),
    );
  }
}
