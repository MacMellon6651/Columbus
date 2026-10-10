import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'api_client.dart';

class ReviewModel {
  final int id;
  final int placeId;
  final int userId;
  final String userEmail;
  final int rating;
  final String? comment;
  final List<String> photoUrls;
  final DateTime createdAt;

  ReviewModel({
    required this.id,
    required this.placeId,
    required this.userId,
    required this.userEmail,
    required this.rating,
    this.comment,
    required this.photoUrls,
    required this.createdAt,
  });

  factory ReviewModel.fromJson(Map<String, dynamic> json) {
    return ReviewModel(
      id: json['id'],
      placeId: json['place_id'],
      userId: json['user_id'],
      userEmail: json['user_email'] ?? '',
      rating: json['rating'],
      comment: json['comment'],
      photoUrls: List<String>.from(json['photo_urls'] ?? []),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class ReviewsService {
  final ApiClient api;
  final ImagePicker _picker = ImagePicker();

  ReviewsService(this.api);

  Future<List<ReviewModel>> getReviews(int placeId) async {
    final data = await api.get('/api/places/$placeId/reviews');
    return (data as List).map((j) => ReviewModel.fromJson(j)).toList();
  }

  Future<ReviewModel> addReview({
    required int placeId,
    required int rating,
    String? comment,
    List<XFile> photos = const [],
  }) async {
    // 1. Загружаем фото по очереди
    final photoUrls = <String>[];
    for (final photo in photos) {
      final bytes = await photo.readAsBytes();
      final url = await api.uploadImage(photo.path, bytes, photo.name);
      photoUrls.add(url);
    }

    // 2. Отправляем отзыв
    final data = await api.post('/api/places/$placeId/reviews', {
      'rating': rating,
      'comment': comment,
      'photo_urls': photoUrls,
    });

    return ReviewModel.fromJson(data);
  }

  Future<List<XFile>> pickPhotos() async {
    return await _picker.pickMultiImage(imageQuality: 80);
  }
}