import 'package:flutter/material.dart';

import 'app/app.dart';

export 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Afficher l'interface tout de suite : l'initialisation distante ne doit
  // jamais retenir runApp au démarrage.
  runApp(const FiseSchoolApp());
}
