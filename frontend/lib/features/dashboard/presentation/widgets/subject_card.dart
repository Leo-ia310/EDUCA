import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/motion.dart';
import '../../../../core/theme/subject_palette.dart';
import '../../../../core/widgets/edu_card.dart';
import '../../domain/dashboard_models.dart';

class SubjectProgressCard extends StatelessWidget {
  const SubjectProgressCard({super.key, required this.subject});
  final SubjectProgress subject;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final pct = (subject.progress * 100).toInt();
    // Cada materia tiene su acento pastel propio (o el que traiga el dato).
    final accent = subject.color ?? subjectColor(subject.name);
    final ink = subject.color ?? subjectInk(subject.name);
    return EduCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              subject.icon ?? Icons.book_outlined,
              size: 20,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subject.name,
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subject.teacher,
            style: context.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: subject.progress),
                    duration: context.motion(AppMotion.slow),
                    curve: AppMotion.standard,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 6,
                      backgroundColor: palette.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation<Color>(ink),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: context.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
