import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/push_service.dart';

export 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw a lightweight first frame immediately; Supabase initialization must
  // not block Flutter from displaying anything to the user.
  runApp(const FiseSchoolBootstrap());
}

class FiseSchoolBootstrap extends StatefulWidget {
  const FiseSchoolBootstrap({super.key});

  @override
  State<FiseSchoolBootstrap> createState() => _FiseSchoolBootstrapState();
}

class _FiseSchoolBootstrapState extends State<FiseSchoolBootstrap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await initializeFiseSchool();
    if (!mounted) return;
    setState(() => _ready = true);
    // Notification setup is non-critical and must not delay the first screen.
    unawaited(_initializePushService());
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const FiseSchoolApp();

    // Keep the first frame lightweight and branded instead of showing a
    // blank screen or an indeterminate spinner while Supabase initializes.
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFF6FBF7),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.school_rounded,
                size: 64,
                color: Color(0xFF166534),
              ),
              SizedBox(height: 16),
              Text(
                'Fise School',
                style: TextStyle(
                  color: Color(0xFF14532D),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _initializePushService() async {
  try {
    await PushService.initialize();
  } catch (error) {
    debugPrint('Push notifications initialization failed: $error');
  }
}
