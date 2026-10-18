import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/admin_school_service.dart';
import '../../../models/school_class.dart';

class AdminSchoolPage extends StatefulWidget {
  final Locale locale;
  final AdminSchoolService? schoolService;

  const AdminSchoolPage({super.key, required this.locale, this.schoolService});

  @override
  State<AdminSchoolPage> createState() => _AdminSchoolPageState();
}

class _AdminSchoolPageState extends State<AdminSchoolPage> {
  late final AdminSchoolService _service =
      widget.schoolService ?? AdminSchoolService();

  late Future<List<AcademicYear>> _years = _service.listAcademicYears();

  late Future<List<SchoolClass>> _classes = _service.listClasses();

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    return Scaffold(
      appBar: AppBar(title: Text(texts.academicYears)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionTitle(texts.academicYears, () => _addYear(texts)),
          FutureBuilder<List<AcademicYear>>(
            future: _years,
            builder: (context, snapshot) => _yearsList(texts, snapshot),
          ),
          const SizedBox(height: 24),
          _sectionTitle(texts.classes, null),
          FutureBuilder<List<SchoolClass>>(
            future: _classes,
            builder: (context, snapshot) => _classesList(texts, snapshot),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, VoidCallback? onAdd) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      if (onAdd != null)
        IconButton(onPressed: onAdd, icon: const Icon(Icons.add)),
    ],
  );

  Widget _yearsList(
    AppTexts texts,
    AsyncSnapshot<List<AcademicYear>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const LinearProgressIndicator();
    }

    if (snapshot.hasError) {
      return Text(texts.adminLoadError);
    }

    final items = snapshot.data ?? const <AcademicYear>[];

    if (items.isEmpty) {
      return Text(texts.noAcademicYears);
    }

    return Column(
      children: items
          .map(
            (year) => ListTile(
              leading: Icon(
                year.isCurrent ? Icons.check_circle : Icons.calendar_month,
                color: year.isCurrent ? Colors.green : null,
              ),
              title: Text(year.label),
              subtitle: Text(
                year.isCurrent ? texts.currentSchoolYear : texts.nextSchoolYear,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) => _yearAction(texts, year, action),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(texts.edit)),
                  if (!year.isCurrent)
                    PopupMenuItem(
                      value: 'current',
                      child: Text(texts.setCurrent),
                    ),
                  if (!year.isCurrent)
                    PopupMenuItem(value: 'disable', child: Text(texts.disable)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _classesList(
    AppTexts texts,
    AsyncSnapshot<List<SchoolClass>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const LinearProgressIndicator();
    }

    if (snapshot.hasError) {
      return Text(texts.adminLoadError);
    }

    final items = snapshot.data ?? const <SchoolClass>[];

    if (items.isEmpty) {
      return Text(texts.noClasses);
    }

    return Column(
      children: items
          .map(
            (item) => ListTile(
              title: Text(item.displayName),
              subtitle: Text('${item.subsystem.name} • ${item.sector.name}'),
            ),
          )
          .toList(),
    );
  }

  Future<void> _addYear(AppTexts texts) async {
    final controller = TextEditingController();

    final label = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(texts.academicYears),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: texts.yearLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(texts.back),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(texts.save),
          ),
        ],
      ),
    );

    controller.dispose();

    if (label == null || label.isEmpty) {
      return;
    }

    await _service.createAcademicYear(label: label);

    if (!mounted) {
      return;
    }

    setState(() {
      _years = _service.listAcademicYears();
    });
  }

  Future<void> _yearAction(
    AppTexts texts,
    AcademicYear year,
    String action,
  ) async {
    if (action == 'current') {
      await _service.setCurrentAcademicYear(year.id);
    } else if (action == 'disable') {
      final confirmed = await _confirm(texts, texts.confirmDisable);

      if (!confirmed) {
        return;
      }

      await _service.updateAcademicYear(
        year.id,
        label: year.label,
        isCurrent: false,
      );
    } else {
      final controller = TextEditingController(text: year.label);

      final label = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(texts.edit),
          content: TextField(controller: controller),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(texts.back),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(texts.save),
            ),
          ],
        ),
      );

      controller.dispose();

      if (label == null || label.isEmpty) {
        return;
      }

      await _service.updateAcademicYear(
        year.id,
        label: label,
        isCurrent: year.isCurrent,
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _years = _service.listAcademicYears();
      _classes = _service.listClasses();
    });
  }

  Future<bool> _confirm(AppTexts texts, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(texts.confirmation),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(texts.back),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(texts.confirm),
            ),
          ],
        ),
      ) ??
      false;
}
