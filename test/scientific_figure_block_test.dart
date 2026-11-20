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

  testWidgets('renders a geometry diagram block', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ScientificFigureBlock(
            block: {
              'type': 'diagram',
              'diagram_kind': 'circle',
              'title_fr': 'Cercle',
            },
            isEnglish: false,
          ),
        ),
      ),
    ));

    expect(find.text('Cercle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
