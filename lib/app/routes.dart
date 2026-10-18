import 'package:flutter/widgets.dart';

import '../features/auth/pages/auth_page.dart';

class FiseSchoolRoutes {
  static const home = '/';
  static const login = '/login';
  static const register = '/register';
  static const student = '/student';
  static const teacher = '/teacher';
  static const courses = '/courses';
  static const course = '/course';
  static const lesson = '/lesson';
  static const messages = '/messages';
  static const assignments = '/assignments';
  static const assignment = '/assignment';
  static const profile = '/profile';

  static const privateRoutes = {
    student,
    teacher,
    courses,
    course,
    lesson,
    messages,
    assignments,
    assignment,
    profile,
  };

  static bool isPrivate(String? routeName) =>
      routeName != null && privateRoutes.contains(routeName);

  static Map<String, WidgetBuilder> publicRoutes({
    required Locale locale,
    required ValueChanged<Locale> onLanguageChanged,
  }) {
    // '/' n'est volontairement pas déclaré ici : MaterialApp.home (AuthGate)
    // gère la route racine. Déclarer les deux déclenche une assertion Flutter.
    return {
      login: (_) => AuthPage(locale: locale),
      register: (_) => AuthPage(locale: locale, startInRegisterMode: true),
    };
  }
}
