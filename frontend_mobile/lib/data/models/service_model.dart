class ServiceModel {
  final String id;
  final String partnerId;
  final String serviceName;
  final String description;
  final double price;
  final String? imageUrl;
  final String? videoUrl;
  final String serviceTypeEnum;
  final Map<String, dynamic> user;

  ServiceModel({
    required this.id,
    required this.partnerId,
    required this.serviceName,
    required this.description,
    required this.price,
    this.imageUrl,
    this.videoUrl,
    required this.serviceTypeEnum,
    required this.user,
  });

  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    return ServiceModel(
      id: json['id'] ?? '',
      partnerId: json['partner_id'] ?? '',
      serviceName: json['service_name'] ?? '',
      description: json['description'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      imageUrl: json['image_url'],
      videoUrl: json['video_url'],
      serviceTypeEnum: json['service_type_enum'] ?? 'RELAXATION',
      user: json['users'] ?? {},
    );
  }
}