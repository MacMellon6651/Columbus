import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/places_service.dart';
import '../services/reviews_service.dart';
import '../services/auth_service.dart';
import '../screens/reviews_screen.dart';

class PlaceDetailsPanel extends StatefulWidget {
  final int placeId;
  final ApiClient api;
  final VoidCallback onClose;

  const PlaceDetailsPanel({
    super.key,
    required this.placeId,
    required this.api,
    required this.onClose,
  });

  @override
  State<PlaceDetailsPanel> createState() => _PlaceDetailsPanelState();
}

class _PlaceDetailsPanelState extends State<PlaceDetailsPanel> {
  late final PlacesService _placesService = PlacesService(widget.api);
  late final ReviewsService _reviewsService = ReviewsService(widget.api);

  Map<String, dynamic>? _place;
  List<ReviewModel> _reviews = [];
  ReviewModel? _myReview;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final place = await _placesService.getPlaceDetails(widget.placeId);
      final reviews = await _reviewsService.getReviews(widget.placeId);

      final auth = context.read<AuthService>();
      final userEmail = auth.currentUserEmail;
      ReviewModel? myReview;
      if (userEmail != null) {
        for (final r in reviews) {
          if (r.userEmail == userEmail) {
            myReview = r;
            break;
          }
        }
      }

      setState(() {
        _place = place;
        _reviews = reviews;
        _myReview = myReview;
      });
    } catch (e) {
      debugPrint('=== ОШИБКА ЗАГРУЗКИ МЕСТА: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openReviews() async {
    if (_place == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewsScreen(
          placeId: widget.placeId,
          placeName: _place!['name'] ?? 'Место',
          api: widget.api,
          editReview: _myReview,
        ),
      ),
    );

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _place == null
              ? const Center(child: Text('Место не найдено'))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final photos = (_place!['photo_urls'] as List?)?.cast<String>() ?? [];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _place!['name'] ?? 'Без названия',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Закрыть',
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openReviews,
              icon: Icon(
                _myReview == null ? Icons.rate_review : Icons.edit,
              ),
              label: Text(
                _myReview == null
                    ? 'Оставить отзыв'
                    : 'Редактировать отзыв',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _myReview == null ? Colors.blue : Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (photos.isNotEmpty) ...[
                SizedBox(
                  height: 160,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        '${ApiClient.baseUrl}${photos[i]}',
                        width: 200,
                        height: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 200,
                          height: 160,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if ((_place!['avg_rating'] ?? 0) > 0)
                Row(
                  children: [
                    ...List.generate(5, (i) {
                      final r = (_place!['avg_rating'] as num).toDouble();
                      return Icon(
                        i < r.round() ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 20,
                      );
                    }),
                    const SizedBox(width: 8),
                    Text(
                      '${(_place!['avg_rating'] as num).toStringAsFixed(1)} '
                      '(${_place!['review_count']})',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              const SizedBox(height: 12),

              if (_place!['category'] != null)
                _buildInfoRow(Icons.category, _place!['category']),
              if (_place!['address'] != null)
                _buildInfoRow(Icons.location_on, _place!['address']),
              if (_place!['opening_hours'] != null)
                _buildInfoRow(Icons.access_time, _place!['opening_hours']),
              if (_place!['phone'] != null)
                _buildInfoRow(Icons.phone, _place!['phone']),
              if (_place!['website'] != null)
                _buildInfoRow(Icons.language, _place!['website']),

              if (_place!['description'] != null) ...[
                const SizedBox(height: 16),
                const Text(
                  'Описание',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(_place!['description']),
              ],

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              Row(
                children: [
                  const Text(
                    'Отзывы',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  Text(
                    '${_reviews.length}',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (_reviews.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.rate_review_outlined,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        const Text('Пока нет отзывов'),
                      ],
                    ),
                  ),
                )
              else
                ..._reviews.map(_buildReviewCard),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildReviewCard(ReviewModel review) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
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
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < review.rating
                          ? Icons.star
                          : Icons.star_border,
                      color: Colors.amber,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(review.comment!),
            ],
          ],
        ),
      ),
    );
  }
}