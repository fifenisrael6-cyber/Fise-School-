import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/push_service.dart';

export 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFiseSchool();
  await PushService.initialize();
  runApp(const FiseSchoolApp());
}
