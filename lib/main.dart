import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/push_service.dart';

export 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFiseSchool();
  // Render the app as soon as its required local/Supabase setup is complete.
  // Push permissions and token registration must never hold the first screen.
  runApp(const FiseSchoolApp());
  unawaited(_initializePushService());
}

Future<void> _initializePushService() async {
  try {
    await PushService.initialize();
  } catch (error) {
    debugPrint('Push notifications initialization failed: $error');
  }
}
