import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fise_school/core/widgets/scientific_figure_block.dart';

void main() {
  testWidgets('renders a read-only exponential graph block', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScientificFigureBlock(
            block: {
              'type': 'graph',
              'function': 'exp',
              'title_fr': 'Fonction exponentielle',
            },
            isEnglish: false,
          ),
        ),
      ),
    ));

    expect(find.text('Fonction exponentielle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders geometry, physics and biology diagram blocks', (tester) async {
    const kinds = [
      'circle', 'unit_circle', 'triangle', 'right_triangle', 'geom_square',
      'geom_parallel', 'geom_coordinate', 'geom_cube', 'geom_pyramid',
      'geom_cylinder', 'geom_prism', 'gravity_pair', 'gravity_altitude',
      'weight', 'cell', 'plant_cell', 'animal_cell', 'svt_neuron',
      'svt_synapse', 'circuit', 'converging_lens',
    ];

    for (final kind in kinds) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ScientificFigureBlock(
              block: {'type': 'diagram', 'diagram_kind': kind, 'title_fr': kind},
              isEnglish: false,
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text(kind), findsOneWidget, reason: 'diagram: $kind');
      expect(tester.takeException(), isNull, reason: 'diagram: $kind');
    }
  });
}
