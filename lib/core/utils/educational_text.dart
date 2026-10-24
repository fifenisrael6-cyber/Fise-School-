/// Converts common LaTeX-style formulas returned by AI into readable
/// plain text for Flutter widgets. This intentionally avoids a math renderer
/// so quiz questions remain readable on every supported device.
String readableEducationalText(String input) {
  var text = input;

  text = text.replaceAllMapped(
    RegExp(r'\\vec\{([^{}]+)\}'),
    (match) => '${match[1]}⃗',
  );
  // Accept simple and one-level nested braces, as commonly returned by AI
  // for fractions such as \frac{M_T \cdot M_L}{TL^2}.
  text = text.replaceAllMapped(
    RegExp(r'\\frac\{((?:[^{}]|\{[^{}]*\})*)\}\{((?:[^{}]|\{[^{}]*\})*)\}'),
    (match) => 'fraction ${match[1]} sur ${match[2]}',
  );
  text = text.replaceAllMapped(
    RegExp(r'\\sqrt\{([^{}]+)\}'),
    (match) => 'racine carrée de (${match[1]})',
  );

  const replacements = <String, String>{
    r'\mathbb{R}': 'ensemble des nombres réels',
    r'\cdot': '×',
    r'\times': '×',
    r'\div': '÷',
    r'\pi': 'π',
    r'\infty': 'infini',
    r'\leq': '≤',
    r'\le': '≤',
    r'\geq': '≥',
    r'\ge': '≥',
    r'\neq': '≠',
    r'\approx': '≈',
    r'\pm': '±',
    r'\to': 'vers',
    r'\rightarrow': 'vers',
    r'\exp': 'exp',
    r'\sin': 'sin',
    r'\cos': 'cos',
    r'\tan': 'tan',
    r'\ln': 'ln',
    r'\log': 'log',
    r'\left': '',
    r'\right': '',
    r'\mathrm': '',
    r'\mathbf': '',
    r'\mathit': '',
    r'\text': '',
    r'\,': ' ',
    r'\;': ' ',
    r'\!': '',
  };
  for (final entry in replacements.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }

  text = text.replaceAllMapped(
    RegExp(r'\^\{([^{}]+)\}'),
    (match) => ' puissance ${match[1]}',
  );
  text = text.replaceAllMapped(
    RegExp(r'_\{([^{}]+)\}'),
    (match) => ' indice ${match[1]}',
  );
  text = text.replaceAllMapped(
    RegExp(r'\^([0-9]+)'),
    (match) => ' puissance ${match[1]}',
  );
  text = text.replaceAllMapped(
    RegExp(r'_([A-Za-z0-9]+)'),
    (match) => ' indice ${match[1]}',
  );

  // Remove any remaining TeX command markers and delimiters rather than
  // showing source-code-like notation to students.
  text = text
      .replaceAll(r'\', '')
      .replaceAll(r'$', '')
      .replaceAll('{', '')
      .replaceAll('}', '')
      .replaceAll(RegExp(r'\\([A-Za-z]+)'), r'$1')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .trim();
  return text;
}
