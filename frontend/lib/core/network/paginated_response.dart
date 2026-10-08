class PageInfo {
  const PageInfo({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
    required this.hasNextPage,
    required this.hasPreviousPage,
  });

  final int page;
  final int pageSize;
  final int total;
  final int totalPages;
  final bool hasNextPage;
  final bool hasPreviousPage;

  factory PageInfo.fromMap(Map<String, dynamic> map) {
    int readInt(String key, [int fallback = 0]) {
      final value = map[key];
      return value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
    }

    bool readBool(String key) => map[key] == true || map[key] == 'true';

    return PageInfo(
      page: readInt('page', 1),
      pageSize: readInt('pageSize', readInt('page_size', 20)),
      total: readInt('total'),
      totalPages: readInt('totalPages', readInt('total_pages', 1)),
      hasNextPage: readBool('hasNextPage') || readBool('has_next_page'),
      hasPreviousPage:
          readBool('hasPreviousPage') || readBool('has_previous_page'),
    );
  }
}

class PaginatedResponse<T> {
  const PaginatedResponse({required this.items, required this.pageInfo});

  final List<T> items;
  final PageInfo pageInfo;

  factory PaginatedResponse.fromMap(
    dynamic data,
    T Function(Map<String, dynamic> map) parse,
  ) {
    final map = (data as Map?)?.cast<String, dynamic>() ?? const {};
    final rawItems = (map['items'] as List?) ?? const [];
    return PaginatedResponse(
      items: rawItems
          .map((item) => parse((item as Map).cast<String, dynamic>()))
          .toList(),
      pageInfo: PageInfo.fromMap(
        (map['pageInfo'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}

List<T> itemsFromBackend<T>(
  dynamic data,
  T Function(Map<String, dynamic> map) parse,
) {
  if (data is List) {
    return data
        .map((item) => parse((item as Map).cast<String, dynamic>()))
        .toList();
  }
  return PaginatedResponse<T>.fromMap(data, parse).items;
}
