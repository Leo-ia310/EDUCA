import 'package:flutter/material.dart';
import '../../../../core/network/paginated_response.dart';

class PageControls extends StatelessWidget {
  const PageControls({super.key, required this.pageInfo, required this.onPage});
  final PageInfo pageInfo;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => pageInfo.totalPages <= 1
      ? const SizedBox.shrink()
      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              tooltip: 'Página anterior',
              onPressed: pageInfo.hasPreviousPage
                  ? () => onPage(pageInfo.page - 1)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),),
          Text('${pageInfo.page} / ${pageInfo.totalPages}'),
          IconButton(
              tooltip: 'Página siguiente',
              onPressed:
                  pageInfo.hasNextPage ? () => onPage(pageInfo.page + 1) : null,
              icon: const Icon(Icons.chevron_right_rounded),),
        ],);
}
