import 'package:flutter/material.dart';

import '../../../models/school_class.dart';

/// Sélecteur de salles : « toutes les salles » ou une ou plusieurs salles précises.
/// Avec [allowAll] à false, seule la sélection précise est proposée.
class ClassTargetPicker extends StatelessWidget {
  final bool fr;
  final List<SchoolClass> classes;
  final bool allClasses;
  final Set<String> selected;
  final bool allowAll;
  final ValueChanged<bool> onAllChanged;
  final ValueChanged<Set<String>> onSelectionChanged;

  const ClassTargetPicker({
    super.key,
    required this.fr,
    required this.classes,
    required this.allClasses,
    required this.selected,
    required this.onAllChanged,
    required this.onSelectionChanged,
    this.allowAll = true,
  });

  @override
  Widget build(BuildContext context) {
    final showList = !allowAll || !allClasses;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allowAll)
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment<bool>(
                value: true,
                label: Text(fr ? 'Toutes les salles' : 'All classrooms'),
              ),
              ButtonSegment<bool>(
                value: false,
                label: Text(fr ? 'Salles précises' : 'Chosen classrooms'),
              ),
            ],
            selected: {allClasses},
            onSelectionChanged: (value) => onAllChanged(value.first),
          ),
        if (showList) ...[
          if (allowAll) const SizedBox(height: 8),
          Text(
            fr
                ? '${selected.length} salle(s) sélectionnée(s)'
                : '${selected.length} classroom(s) selected',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (classes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(fr ? 'Aucune salle disponible.' : 'No classroom available.'),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: classes.map((room) {
                  final checked = selected.contains(room.id);
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: checked,
                    title: Text(room.displayName),
                    onChanged: (value) {
                      final next = Set<String>.from(selected);
                      if (value == true) {
                        next.add(room.id);
                      } else {
                        next.remove(room.id);
                      }
                      onSelectionChanged(next);
                    },
                  );
                }).toList(growable: false),
              ),
            ),
        ],
      ],
    );
  }
}
