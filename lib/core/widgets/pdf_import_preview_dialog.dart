import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'course_table_embed.dart';

class PdfImportPreviewDialog extends StatefulWidget {
  const PdfImportPreviewDialog({super.key, required this.blocks});
  final List<Map<String, dynamic>> blocks;

  @override
  State<PdfImportPreviewDialog> createState() => _PdfImportPreviewDialogState();
}

class _PdfImportPreviewDialogState extends State<PdfImportPreviewDialog> {
  late List<Map<String, dynamic>> _blocks;

  @override
  void initState() {
    super.initState();
    _blocks = widget.blocks.map((b) => Map<String, dynamic>.from(b)).toList();
  }

  int get _selectedCount => _blocks.where((b) => b['selected'] == true).length;

  void _editText(int index) async {
    final controller = TextEditingController(text: _blocks[index]['text']?.toString() ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le contenu extrait'),
        content: TextField(controller: controller, minLines: 3, maxLines: 10, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Enregistrer')),
        ],
      ),
    );
    controller.dispose();
    if (value != null) setState(() => _blocks[index]['text'] = value);
  }

  Widget _blockPreview(Map<String, dynamic> block) {
    final type = block['type'];
    if (type == 'table') {
      final rows = (block['cells'] as List? ?? const [])
          .map((row) => (row as List).map((cell) => cell.toString()).toList())
          .toList();
      if (rows.isEmpty) return const Text('Tableau vide');
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: Theme.of(context).colorScheme.outline),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: List.generate(rows.length, (r) => TableRow(
            decoration: block['firstRowHeader'] == true && r == 0
                ? BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest)
                : null,
            children: rows[r].map((cell) => Padding(
              padding: const EdgeInsets.all(8),
              child: Text(cell, style: TextStyle(fontWeight: block['firstRowHeader'] == true && r == 0 ? FontWeight.bold : FontWeight.normal)),
            )).toList(),
          )),
        ),
      );
    }
    if (type == 'image') {
      final data = block['data']?.toString() ?? '';
      try {
        final bytes = base64Decode(data.split(',').last);
        return Image.memory(Uint8List.fromList(bytes), height: 150, fit: BoxFit.contain);
      } catch (_) {
        return const Text('Aperçu de l’image indisponible');
      }
    }
    final text = block['text']?.toString() ?? '';
    if (type == 'heading') {
      return Text(text, style: TextStyle(fontSize: 20.0 - ((block['level'] as int? ?? 1) * 2), fontWeight: FontWeight.bold));
    }
    if (type == 'list') {
      return Text('${block['ordered'] == true ? '1.' : '•'} $text');
    }
    return Text(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aperçu de l’import PDF'),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text('${_selectedCount} / ${_blocks.length} blocs sélectionnés')),
                TextButton(onPressed: () => setState(() { for (final b in _blocks) { b['selected'] = true; } }), child: const Text('Tout')),
                TextButton(onPressed: () => setState(() { for (final b in _blocks) { b['selected'] = false; } }), child: const Text('Aucun')),
              ],
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _blocks.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (context, index) {
                  final block = _blocks[index];
                  final type = block['type']?.toString() ?? 'paragraph';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text('${type.toUpperCase()} · page ${block['page'] ?? '-'}', style: Theme.of(context).textTheme.labelMedium)),
                              Checkbox(value: block['selected'] == true, onChanged: (v) => setState(() => block['selected'] = v == true)),
                              IconButton(tooltip: 'Supprimer', onPressed: () => setState(() => _blocks.removeAt(index)), icon: const Icon(Icons.delete_outline)),
                            ],
                          ),
                          _blockPreview(block),
                          if (type == 'table')
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final updated = await showCourseTableDialog(
                                    context,
                                    initialData: {
                                      'cells': block['cells'],
                                      'firstRowHeader': block['firstRowHeader'] == true,
                                    },
                                  );
                                  if (updated != null) setState(() {
                                    block['cells'] = updated['cells'];
                                    block['firstRowHeader'] = updated['firstRowHeader'];
                                  });
                                },
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Modifier le tableau'),
                              ),
                            ),
                          if (type != 'image' && type != 'table') Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 4,
                            children: [
                              TextButton(onPressed: () => _editText(index), child: const Text('Modifier')),
                              PopupMenuButton<String>(
                                tooltip: 'Changer le type',
                                onSelected: (value) => setState(() {
                                  block['type'] = value;
                                  if (value == 'heading') block['level'] = 2;
                                  if (value == 'list') block['ordered'] = false;
                                }),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'paragraph', child: Text('Paragraphe')),
                                  PopupMenuItem(value: 'heading', child: Text('Titre H2')),
                                  PopupMenuItem(value: 'list', child: Text('Liste à puces')),
                                ],
                                child: const Padding(padding: EdgeInsets.all(8), child: Text('Type')),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        TextButton(onPressed: () => Navigator.pop(context, _blocks.where((b) => b['selected'] == true).toList()), child: const Text('Insérer la sélection')),
        FilledButton(onPressed: () => Navigator.pop(context, _blocks), child: const Text('Tout insérer')),
      ],
    );
  }
}
