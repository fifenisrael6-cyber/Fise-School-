import 'package:flutter/material.dart';

import '../../../core/localization/app_texts.dart';
import '../../../core/services/promotion_service.dart';
import '../../../models/student_promotion.dart';

class AdminPromotionPage extends StatefulWidget {
  final Locale locale;
  final PromotionService? promotionService;

  const AdminPromotionPage({
    super.key,
    required this.locale,
    this.promotionService,
  });

  @override
  State<AdminPromotionPage> createState() => _AdminPromotionPageState();
}

class _AdminPromotionPageState extends State<AdminPromotionPage> {
  late final PromotionService _service =
      widget.promotionService ?? PromotionService();

  late Future<List<PromotionReviewItem>> _future = _service
      .getPendingPromotions();

  @override
  Widget build(BuildContext context) {
    final texts = AppTexts(widget.locale);

    return Scaffold(
      appBar: AppBar(title: Text(texts.promotion)),
      body: FutureBuilder<List<PromotionReviewItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text(texts.noPromotionPath));
          }

          final requests = snapshot.data ?? const <PromotionReviewItem>[];

          if (requests.isEmpty) {
            return Center(child: Text(texts.noPendingPromotions));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: requests.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _requestCard(context, texts, requests[index]),
          );
        },
      ),
    );
  }

  Widget _requestCard(
    BuildContext context,
    AppTexts texts,
    PromotionReviewItem item,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.studentName,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              '${item.sourceClassName} → '
              '${item.destinationClassName}',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: [
                OutlinedButton(
                  onPressed: () => _review(
                    context,
                    item.promotion.id,
                    StudentPromotionStatus.rejected,
                  ),
                  child: Text(texts.rejectPromotion),
                ),
                FilledButton(
                  onPressed: () => _review(
                    context,
                    item.promotion.id,
                    StudentPromotionStatus.approved,
                  ),
                  child: Text(texts.approvePromotion),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _review(
    BuildContext context,
    String promotionId,
    StudentPromotionStatus status,
  ) async {
    try {
      await _service.reviewPromotion(promotionId: promotionId, status: status);

      if (!mounted || !context.mounted) {
        return;
      }

      setState(() {
        _future = _service.getPendingPromotions();
      });
    } catch (_) {
      if (!mounted || !context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts(widget.locale).promotionReviewError)),
      );
    }
  }
}
