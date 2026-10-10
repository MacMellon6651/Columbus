import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';
import '../services/reviews_service.dart';

class ReviewsScreen extends StatefulWidget {
  final int placeId;
  final String placeName;
  final ApiClient api;
  final ReviewModel? editReview;

  const ReviewsScreen({
    super.key,
    required this.placeId,
    required this.placeName,
    required this.api,
    this.editReview,
  });

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  late final ReviewsService _service;
  List<ReviewModel> _reviews = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = ReviewsService(widget.api);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final reviews = await _service.getReviews(widget.placeId);
      setState(() => _reviews = reviews);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openReviewEditor() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _AddReviewSheet(
        service: _service,
        placeId: widget.placeId,
        existing: widget.editReview,
      ),
    );

    if (result != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.placeName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reviews.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reviews.length,
                  itemBuilder: (context, i) =>
                      _buildReviewCard(_reviews[i]),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openReviewEditor,
        icon: Icon(widget.editReview == null
            ? Icons.rate_review
            : Icons.edit),
        label: Text(widget.editReview == null
            ? 'Оставить отзыв'
            : 'Редактировать'),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rate_review_outlined,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('Пока нет отзывов'),
          const SizedBox(height: 8),
          Text(
            'Будьте первым!',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(ReviewModel review) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    review.userEmail.isNotEmpty
                        ? review.userEmail[0].toUpperCase()
                        : '?',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    review.userEmail,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                _buildStars(review.rating),
              ],
            ),
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(review.comment!),
            ],
            if (review.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: review.photoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      '${ApiClient.baseUrl}${review.photoUrls[i]}',
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 100,
                        height: 100,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _formatDate(review.createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStars(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 18,
        );
      }),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year} '
        '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

// ============ ФОРМА ============

class _AddReviewSheet extends StatefulWidget {
  final ReviewsService service;
  final int placeId;
  final ReviewModel? existing;

  const _AddReviewSheet({
    required this.service,
    required this.placeId,
    this.existing,
  });

  @override
  State<_AddReviewSheet> createState() => _AddReviewSheetState();
}

class _AddReviewSheetState extends State<_AddReviewSheet> {
  late int _rating;
  late final TextEditingController _commentController;
  List<XFile> _photos = [];
  List<String> _existingPhotoUrls = [];
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.existing?.rating ?? 5;
    _commentController = TextEditingController(
      text: widget.existing?.comment ?? '',
    );
    _existingPhotoUrls = widget.existing?.photoUrls ?? [];
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final photos = await widget.service.pickPhotos();
    setState(() => _photos = photos);
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      if (widget.existing == null) {
        await widget.service.addReview(
          placeId: widget.placeId,
          rating: _rating,
          comment: _commentController.text.trim().isEmpty
              ? null
              : _commentController.text.trim(),
          photos: _photos,
        );
      } else {
        await widget.service.updateReview(
          reviewId: widget.existing!.id,
          rating: _rating,
          comment: _commentController.text.trim().isEmpty
              ? null
              : _commentController.text.trim(),
          photos: _photos,
          existingPhotoUrls: _existingPhotoUrls,
        );
      }

      if (mounted) Navigator.pop(context, {'success': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить отзыв?'),
        content: const Text('Действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _submitting = true);
    try {
      await widget.service.deleteReview(widget.existing!.id);
      if (mounted) Navigator.pop(context, {'deleted': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing == null
                  ? 'Оставить отзыв'
                  : 'Редактировать отзыв',
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Звёзды
            Row(
              children: List.generate(5, (i) {
                return IconButton(
                  icon: Icon(
                    i < _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                  onPressed: () => setState(() => _rating = i + 1),
                );
              }),
            ),
            const SizedBox(height: 12),

            // Комментарий
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Расскажите о месте...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Кнопка выбора фото
            OutlinedButton.icon(
              onPressed: _pickPhotos,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text('Добавить фото (${_photos.length})'),
            ),

            // Существующие фото (при редактировании)
            if (widget.existing != null &&
                _existingPhotoUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Старые фото:',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _existingPhotoUrls.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      '${ApiClient.baseUrl}${_existingPhotoUrls[i]}',
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 80,
                        height: 80,
                        color: Colors.grey.shade200,
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // Новые фото
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Новые фото:',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: FutureBuilder<Uint8List>(
                          future: _photos[i].readAsBytes(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return Container(
                                width: 80,
                                height: 80,
                                color: Colors.grey.shade200,
                              );
                            }
                            return Image.memory(
                              snapshot.data!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                            );
                          },
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _photos.removeAt(i)),
                          child: Container(
                            color: Colors.black54,
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Отправить
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(widget.existing == null
                        ? 'Отправить'
                        : 'Сохранить'),
              ),
            ),

            // Удалить (только при редактировании)
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _submitting ? null : _delete,
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red),
                  label: const Text(
                    'Удалить отзыв',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}