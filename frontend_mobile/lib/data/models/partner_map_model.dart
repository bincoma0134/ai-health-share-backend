class PartnerMapModel {
  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;
  final double latitude;
  final double longitude;
  double distance;
  final List<String> tags;
  final List<dynamic> services;

  PartnerMapModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.tags,
    required this.services,
  });

  factory PartnerMapModel.fromJson(Map<String, dynamic> json) {
    return PartnerMapModel(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? 'Đối tác',
      avatarUrl: json['avatar_url'] ?? '',
      // Mặc định tọa độ trung tâm Hà Nội nếu null
      latitude: (json['latitude'] ?? 21.028511).toDouble(),
      longitude: (json['longitude'] ?? 105.804817).toDouble(),
      distance: (json['distance'] ?? 0.0).toDouble(),
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
      services: json['services'] ?? [],
    );
  }
}