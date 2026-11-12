import 'package:flutter/material.dart';

/// Saisie de cours avec raccourcis LaTeX compatibles avec RichLessonText.
class MathLessonInput extends StatelessWidget {
  const MathLessonInput({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.minLines = 7,
    this.maxLines = 18,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int minLines;
  final int maxLines;

  static const List<Map<String, String>> _snippets = [
    {'label': 'Fraction', 'value': r'$$\frac{a}{b}$$'},
    {'label': 'Division', 'value': r'$$\frac{a+bi}{c+di}$$'},
    {'label': 'Puissance', 'value': r'$x^{2}$'},
    {'label': 'Racine', 'value': r'$\sqrt{x}$'},
    {'label': 'Intégrale', 'value': r'$$\int_a^b f(x)\,dx$$'},
    {'label': 'Système', 'value': r'$$\begin{aligned}x+y&=5\\2x-y&=1\end{aligned}$$'},
    {'label': 'Limite', 'value': r'$$\lim_{x\to a}f(x)$$'},
    {'label': 'Matrice', 'value': r'$$\begin{pmatrix}a&b\\c&d\end{pmatrix}$$'},
  ];

  void _insert(String value) {
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, value);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final snippet in _snippets)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: OutlinedButton(
                    onPressed: () => _insert('\n' + snippet['value']! + '\n'),
                    child: Text(snippet['label']!),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            helperText:
                r'Formule : $...$  •  Formule centrée : $$...$$  •  Utilisez les boutons pour insérer les structures courantes.',
            helperMaxLines: 3,
          ),
        ),
      ],
    );
  }
}
