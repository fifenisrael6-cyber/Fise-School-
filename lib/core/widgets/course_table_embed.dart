import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// JSON-backed table embed stored as a Quill custom block.
class CourseTableEmbed extends CustomBlockEmbed {
  const CourseTableEmbed(String value) : super('courseTable', value);

  static const String embedType = 'courseTable';

  factory CourseTableEmbed.fromCells({
    required List<List<String>> cells,
    required bool firstRowHeader,
  }) {
    return CourseTableEmbed(jsonEncode({
      'rows': cells.length,
      'columns': cells.isEmpty ? 0 : cells.first.length,
      'cells': cells,
      'firstRowHeader': firstRowHeader,
    }));
  }

  Map<String, dynamic> get tableData {
    final decoded = jsonDecode(data);
    if (decoded is! Map) {
      throw const FormatException('Invalid course table data');
    }
    final rawCells = decoded['cells'];
    final cells = rawCells is List
        ? rawCells.map((row) => row is List
            ? row.map((cell) => cell?.toString() ?? '').toList()
            : <String>[]).toList()
        : <List<String>>[];
    return {
      'rows': cells.length,
      'columns': cells.isEmpty ? 0 : cells.map((r) => r.length).reduce((a, b) => a > b ? a : b),
      'cells': cells,
      'firstRowHeader': decoded['firstRowHeader'] == true,
    };
  }
}

Future<Map<String, dynamic>?> showCourseTableDialog(
  BuildContext context, {
  Map<String, dynamic>? initialData,
  int initialRows = 3,
  int initialColumns = 3,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _CourseTableDialog(
      initialData: initialData,
      initialRows: initialRows,
      initialColumns: initialColumns,
    ),
  );
}

class CourseTableEmbedBuilder extends EmbedBuilder {
  CourseTableEmbedBuilder({this.onChanged});

  final VoidCallback? onChanged;

  @override
  String get key => CourseTableEmbed.embedType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final raw = embedContext.node.value.data;
    final table = CourseTableEmbed(raw.toString()).tableData;
    final cells = (table['cells'] as List).cast<List<String>>();
    final isHeader = table['firstRowHeader'] == true;
    final readOnly = embedContext.readOnly;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: readOnly
            ? null
            : () async {
                final updated = await showCourseTableDialog(
                  context,
                  initialData: table,
                );
                if (updated == null) return;
                final controller = embedContext.controller;
                final offset = embedContext.node.documentOffset;
                controller.replaceText(
                  offset,
                  1,
                  BlockEmbed.custom(CourseTableEmbed.fromCells(
                    cells: (updated['cells'] as List)
                        .map((r) => (r as List).map((v) => v.toString()).toList())
                        .toList(),
                    firstRowHeader: updated['firstRowHeader'] == true,
                  )),
                  TextSelection.collapsed(offset: offset + 1),
                );
                onChanged?.call();
              },
        child: _CourseTableView(cells: cells, firstRowHeader: isHeader),
      ),
    );
  }
}

class _CourseTableView extends StatelessWidget {
  const _CourseTableView({
    required this.cells,
    required this.firstRowHeader,
  });

  final List<List<String>> cells;
  final bool firstRowHeader;

  @override
  Widget build(BuildContext context) {
    if (cells.isEmpty) return const SizedBox.shrink();
    final columns = cells.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    final border = TableBorder.all(
      color: Theme.of(context).colorScheme.outline,
      width: 1,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: border,
        children: List.generate(cells.length, (row) {
          return TableRow(
            decoration: firstRowHeader && row == 0
                ? BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest)
                : null,
            children: List.generate(columns, (column) {
              final value = column < cells[row].length ? cells[row][column] : '';
              return Padding(
                padding: const EdgeInsets.all(10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72, minHeight: 28),
                  child: Text(
                    value,
                    style: TextStyle(
                      fontWeight: firstRowHeader && row == 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          );
        }),
      ),
    );
  }
}

class _CourseTableDialog extends StatefulWidget {
  const _CourseTableDialog({
    this.initialData,
    required this.initialRows,
    required this.initialColumns,
  });

  final Map<String, dynamic>? initialData;
  final int initialRows;
  final int initialColumns;

  @override
  State<_CourseTableDialog> createState() => _CourseTableDialogState();
}

class _CourseTableDialogState extends State<_CourseTableDialog> {
  late List<List<TextEditingController>> _cells;
  bool _firstRowHeader = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.initialData?['cells'];
    final values = raw is List
        ? raw.map((r) => r is List ? r.map((v) => v.toString()).toList() : <String>[]).toList()
        : List.generate(widget.initialRows, (_) => List<String>.filled(widget.initialColumns, ''));
    final columnCount = values.isEmpty
        ? widget.initialColumns
        : values.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
    _cells = values.map((row) {
      final padded = List<String>.generate(columnCount, (i) => i < row.length ? row[i] : '');
      return padded.map((value) => TextEditingController(text: value)).toList();
    }).toList();
    if (_cells.isEmpty) {
      _cells = List.generate(widget.initialRows, (_) => List.generate(widget.initialColumns, (_) => TextEditingController()));
    }
    _firstRowHeader = widget.initialData?['firstRowHeader'] == true;
  }

  int get _columns => _cells.isEmpty ? 0 : _cells.first.length;

  void _addRow() => setState(() => _cells.add(List.generate(_columns, (_) => TextEditingController())));
  void _removeRow() {
    if (_cells.length <= 1) return;
    final removed = _cells.removeLast();
    for (final c in removed) { c.dispose(); }
    setState(() {});
  }
  void _addColumn() => setState(() {
    for (final row in _cells) { row.add(TextEditingController()); }
  });
  void _removeColumn() {
    if (_columns <= 1) return;
    for (final row in _cells) { row.removeLast().dispose(); }
    setState(() {});
  }

  @override
  void dispose() {
    for (final row in _cells) { for (final c in row) { c.dispose(); } }
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop({
      'rows': _cells.length,
      'columns': _columns,
      'cells': _cells.map((row) => row.map((c) => c.text).toList()).toList(),
      'firstRowHeader': _firstRowHeader,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier le tableau'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _firstRowHeader,
              onChanged: (v) => setState(() => _firstRowHeader = v ?? false),
              title: const Text('Première ligne = en-tête'),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                TextButton.icon(onPressed: _addRow, icon: const Icon(Icons.add), label: const Text('Ligne')),
                TextButton.icon(onPressed: _removeRow, icon: const Icon(Icons.remove), label: const Text('Ligne')),
                TextButton.icon(onPressed: _addColumn, icon: const Icon(Icons.add), label: const Text('Colonne')),
                TextButton.icon(onPressed: _removeColumn, icon: const Icon(Icons.remove), label: const Text('Colonne')),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Table(
                    defaultColumnWidth: const FixedColumnWidth(132),
                    border: TableBorder.all(color: Theme.of(context).colorScheme.outline),
                    children: _cells.asMap().entries.map((entry) {
                      final rowIndex = entry.key;
                      return TableRow(
                        children: entry.value.map((controller) => Padding(
                          padding: const EdgeInsets.all(4),
                          child: TextField(
                            controller: controller,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.all(8),
                            ),
                          ),
                        )).toList(),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _save, child: const Text('Valider')),
      ],
    );
  }
}
