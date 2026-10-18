import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/promotion_service.dart';
import '../../../models/school_class.dart';
import '../../../models/student_promotion.dart';
import '../../../models/user_profile.dart';

class PromotionPage extends StatefulWidget {
  final Locale locale;
  final UserProfile profile;
  final PromotionService? promotionService;

  const PromotionPage({
    super.key,
    required this.locale,
    required this.profile,
    this.promotionService,
  });

  @override
  State<PromotionPage> createState() => _PromotionPageState();
}

class _PromotionPageState extends State<PromotionPage> {
  late final PromotionService _service =
      widget.promotionService ?? PromotionService();

  late Future<PromotionContext> _contextFuture = _service.loadContext(
    widget.profile,
  );

  SchoolClass? _selectedClass;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    return Scaffold(
      appBar: AppBar(title: Text(texts.promotion)),
      body: FutureBuilder<PromotionContext>(
        future: _contextFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _Message(texts.noPromotionPath);
          }

          final data = snapshot.data!;
          return _body(context, texts, data);
        },
      ),
    );
  }

  Widget _body(BuildContext context, AppTexts texts, PromotionContext data) {
    final currentClass = data.currentClass;
    final nextYear = data.nextYear;

    if (currentClass == null) {
      return _Message(texts.noCurrentClass);
    }

    if (nextYear == null) {
      return _Message(texts.noPromotionPath);
    }

    final activeRequest = data.request;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _InfoCard(
          label: texts.currentSchoolYear,
          value: data.currentYear.label,
          icon: Icons.calendar_today_rounded,
        ),
        const SizedBox(height: 12),
        _InfoCard(
          label: texts.currentClass,
          value: currentClass.displayName,
          icon: Icons.school_rounded,
        ),
        const SizedBox(height: 24),
        if (activeRequest != null)
          _requestState(context, texts, activeRequest, data)
        else ...[
          Text(
            '${texts.nextSchoolYear}: ${nextYear.label}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(texts.chooseNextClass),
          const SizedBox(height: 12),
          if (data.destinationClasses.isEmpty)
            Text(texts.noDestinationClasses)
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedClass?.id,
              decoration: InputDecoration(labelText: texts.schoolClass),
              items: data.destinationClasses
                  .map(
                    (schoolClass) => DropdownMenuItem<String>(
                      value: schoolClass.id,
                      child: Text(schoolClass.displayName),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                final match = data.destinationClasses.firstWhere(
                  (schoolClass) => schoolClass.id == value,
                );

                setState(() => _selectedClass = match);
              },
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: data.destinationClasses.isEmpty || _isSubmitting
                  ? null
                  : () => _submit(context, texts, data),
              icon: const Icon(Icons.upgrade_rounded),
              label: Text(texts.requestPromotion),
            ),
          ],
        ],
      ],
    );
  }

  Widget _requestState(
    BuildContext context,
    AppTexts texts,
    StudentPromotion request,
    PromotionContext data,
  ) {
    final message = switch (request.status) {
      StudentPromotionStatus.pending => texts.promotionPending,
      StudentPromotionStatus.approved => texts.promotionApproved,
      StudentPromotionStatus.rejected => texts.promotionRejected,
      StudentPromotionStatus.cancelled => texts.promotionCancelled,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('${texts.nextSchoolYear}: ${data.nextYear!.label}'),
            if (request.status == StudentPromotionStatus.pending) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _isSubmitting
                    ? null
                    : () => _cancel(context, texts, request),
                child: Text(texts.cancelPromotion),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit(
    BuildContext context,
    AppTexts texts,
    PromotionContext data,
  ) async {
    final destination = _selectedClass;

    if (destination == null) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _service.requestPromotion(
        profile: widget.profile,
        context: data,
        destinationClass: destination,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedClass = null;
        _contextFuture = _service.loadContext(widget.profile);
      });
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, texts.noPromotionPath);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _cancel(
    BuildContext context,
    AppTexts texts,
    StudentPromotion request,
  ) async {
    setState(() => _isSubmitting = true);

    try {
      await _service.cancelPromotion(request.id);

      if (!mounted) {
        return;
      }

      setState(() => _contextFuture = _service.loadContext(widget.profile));
    } catch (_) {
      if (context.mounted) {
        _showMessage(context, texts.noPromotionPath);
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF166534)),
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String message;

  const _Message(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
