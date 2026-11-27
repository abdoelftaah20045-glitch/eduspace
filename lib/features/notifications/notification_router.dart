import 'package:flutter/material.dart';

import '../../core/recovery.dart';
import '../certificates/my_certificates_screen.dart';
import '../courses/course_details_screen.dart';
import '../courses/courses_screen.dart';
import '../exams/exams_screen.dart';
import '../lives/lives_screen.dart';
import '../support/support_screen.dart';

/// Opens the screen a notification refers to. Returns false when there is
/// no matching screen (the caller then just shows the text).
bool openNotificationTarget({
  BuildContext? context,
  required String type,
  required String title,
  Map<String, dynamic>? data,
}) {
  final nav = context != null
      ? Navigator.of(context)
      : rootNavigatorKey.currentState;
  if (nav == null) return false;
  final t = type.toLowerCase();
  final ti = title.toLowerCase();
  final courseId = '${data?['course_id'] ?? ''}';
  Widget? page;
  if (courseId.isNotEmpty && courseId != 'null') {
    page = CourseDetailsScreen(courseId: courseId);
  } else if (t.contains('certificate')) {
    page = const MyCertificatesScreen();
  } else if (t.contains('exam')) {
    page = const ExamsScreen();
  } else if (t.contains('live')) {
    page = const LivesScreen();
  } else if (t.contains('support') ||
      ti.contains('الدعم') ||
      ti.contains('support')) {
    page = const SupportScreen();
  } else if (t.contains('course') || t.contains('assignment')) {
    page = const CoursesScreen();
  }
  if (page == null) return false;
  nav.push(MaterialPageRoute<void>(builder: (_) => page!));
  return true;
}
