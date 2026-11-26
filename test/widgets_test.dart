import 'package:eduspace_app/core/l10n.dart';
import 'package:eduspace_app/features/courses/data/course_models.dart';
import 'package:eduspace_app/features/home/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  final long = List.filled(40, 'word').join(' ');

  testWidgets('ExpandableText toggles show more / less', (t) async {
    await t.pumpWidget(_wrap(ExpandableText(long)));
    final more = S(const Locale('ar')).t('show_more');
    final less = S(const Locale('ar')).t('show_less');
    expect(find.text(more), findsOneWidget);
    await t.tap(find.text(more));
    await t.pumpAndSettle();
    expect(find.text(less), findsOneWidget);
  });

  testWidgets('ExpandableText short text has no toggle', (t) async {
    await t.pumpWidget(_wrap(const ExpandableText('short')));
    expect(find.text(S(const Locale('ar')).t('show_more')), findsNothing);
  });

  testWidgets('CategoryChips reports the tapped field', (t) async {
    String? picked = 'none';
    await t.pumpWidget(_wrap(CategoryChips(
      fields: const ['Design', 'Code'],
      selected: null,
      onSelect: (f) => picked = f,
    )));
    await t.tap(find.text('Code'));
    expect(picked, 'Code');
    await t.tap(find.text(S(const Locale('ar')).t('all_label')));
    expect(picked, null);
  });

  testWidgets('FeaturedCourseCard shows title, instructor and price',
      (t) async {
    final c = Course(
        id: '1',
        title: 'UX Basics',
        description: 'd',
        instructorName: 'Sara',
        price: 120,
        currency: 'EGP');
    await t.pumpWidget(_wrap(FeaturedCourseCard(course: c)));
    expect(find.text('UX Basics'), findsOneWidget);
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('120 EGP'), findsOneWidget);
  });

  testWidgets('FeaturedCourseCard free course shows the free label',
      (t) async {
    final c = Course(id: '2', title: 'Free one', description: 'd');
    await t.pumpWidget(_wrap(FeaturedCourseCard(course: c)));
    expect(find.text(S(const Locale('ar')).t('free')), findsOneWidget);
  });

  testWidgets('TopMentors lists each instructor once', (t) async {
    final a = Course(id: '1', title: 'a', description: '', instructorName: 'Sara');
    final b = Course(id: '2', title: 'b', description: '', instructorName: 'Sara');
    final c = Course(id: '3', title: 'c', description: '', instructorName: 'Omar');
    await t.pumpWidget(_wrap(TopMentors(courses: [a, b, c])));
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Omar'), findsOneWidget);
  });

  testWidgets('TopMentors with no instructors renders nothing', (t) async {
    final a = Course(id: '1', title: 'a', description: '');
    await t.pumpWidget(_wrap(TopMentors(courses: [a])));
    expect(find.byType(CircleAvatar), findsNothing);
  });
}
