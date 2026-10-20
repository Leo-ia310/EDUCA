import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/admin_backend_repository.dart';

/// Bounded, searchable choices. Selections remain intact across pages/filters.
class DirectoryPicker extends ConsumerStatefulWidget {
  const DirectoryPicker(
      {super.key,
      required this.kind,
      required this.selected,
      required this.onChanged,
      this.multiple = false,
      this.onOption,});
  final String kind;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool multiple;
  final ValueChanged<JsonMap>? onOption;
  @override
  ConsumerState<DirectoryPicker> createState() => _DirectoryPickerState();
}

class _DirectoryPickerState extends ConsumerState<DirectoryPicker> {
  final _labels = <String, String>{};
  List<JsonMap> _items = const [];
  String _query = '';
  String? _error;
  bool _loading = false, _more = false;
  int _page = 1, _revision = 0;
  int? _retryPage;
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load(1));
    });
  }

  @override
  void didUpdateWidget(covariant DirectoryPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _labels.clear();
      _items = const [];
      unawaited(_load(1));
    }
  }

  @override
  void dispose() {
    _revision++;
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load(int page) async {
    final repository = ref.read(adminBackendRepositoryProvider);
    if (repository == null) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await repository.directoryOptions(widget.kind,
          search: _query, page: page, includeIds: widget.selected,);
      if (!mounted || revision != _revision) return;
      final items = (data['items'] as List).cast<JsonMap>();
      for (final option in [
        ...items,
        ...(data['selected'] as List).cast<JsonMap>(),
      ]) {
        _labels[option['id'].toString()] = option['label'].toString();
      }
      setState(() {
        final byId = {
          if (page > 1)
            for (final item in _items) item['id'].toString(): item,
          for (final item in items) item['id'].toString(): item,
        };
        _items = byId.values.toList();
        _page = page;
        _more = (data['pageInfo'] as Map)['hasNextPage'] == true;
      });
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() {
          _error = '$error';
          _retryPage = page;
        });
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.selected.isNotEmpty)
          Row(children: [
            Expanded(
                child: Text(widget.selected.length == 1
                    ? _labels[widget.selected.first] ?? '1 seleccionado'
                    : '${widget.selected.length} seleccionados',),),
            TextButton(
                onPressed: _loading ? null : () => widget.onChanged({}),
                child: const Text('Quitar selección'),),
          ],),
        TextField(
            decoration: const InputDecoration(
                hintText: 'Buscar…', prefixIcon: Icon(Icons.search_rounded),),
            onChanged: (value) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                _query = value.trim();
                unawaited(_load(1));
              });
            },),
        for (final item in _items)
          Material(
            type: MaterialType.transparency,
            child: CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item['label'].toString()),
              value: widget.selected.contains(item['id'].toString()),
              onChanged: _loading
                  ? null
                  : (selected) {
                      final id = item['id'].toString(),
                          values = {...widget.selected};
                      if (selected == true) {
                        if (!widget.multiple) values.clear();
                        values.add(id);
                        widget.onOption?.call(item);
                      } else {
                        values.remove(id);
                      }
                      widget.onChanged(values);
                    },),
          ),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
              onPressed: () => _load(_retryPage ?? _page),
              child: const Text('Reintentar'),),
        ],
        if (!_loading && _error == null && _items.isEmpty)
          const Text('Sin coincidencias.'),
        if (_more)
          TextButton(
              onPressed: _loading ? null : () => _load(_page + 1),
              child: const Text('Cargar más'),),
      ],);
}
