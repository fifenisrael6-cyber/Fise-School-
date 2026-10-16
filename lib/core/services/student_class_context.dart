import 'package:flutter/foundation.dart';

/// Signals that the authenticated student's active classroom has changed.
/// The student shell listens and reloads the profile without signing out.
class StudentClassContext {
  StudentClassContext._();
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void notifyChanged() => revision.value++;
}
