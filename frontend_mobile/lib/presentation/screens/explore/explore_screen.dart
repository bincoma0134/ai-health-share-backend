import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../data/models/service_model.dart';
import '../../../data/services/explore_api_service.dart';
import '../../widgets/auth_bottom_sheet.dart';
import '../../widgets/service_booking_bottom_sheet.dart';
import '../../widgets/mini_video_player.dart'; // Import Trình phát Video

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<ServiceModel> _services = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _activeFilter = 'ALL';
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    final services = await ExploreApiService.fetchServices();
    setState(() {
      _services = services;
      _isLoading = false;
    });
  }

  List<ServiceModel> get _filteredServices {
    return _services.where((s) {
      final matchesSearch = s.serviceName.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                            s.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesFilter = _activeFilter == 'ALL' || s.serviceTypeEnum == _activeFilter;
      return matchesSearch && matchesFilter;
    }).toList();
  }

  Future<void> _handleBookingClick(ServiceModel service) async {
    final token = await _storage.read(key: 'ai-health-token');
    if (token == null || token.isEmpty) {
      if (mounted) {
        showModalBottomSheet(
          context: context,
          useRootNavigator: true, // <--- ÉP HIỂN THỊ ĐÈ LÊN NAVIGATION BAR
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => AuthBottomSheet(onSuccess: () {}),
        );
      }
    } else {
      if (mounted) {
        showModalBottomSheet(
          context: context,
          useRootNavigator: true, // <--- ÉP HIỂN THỊ ĐÈ LÊN NAVIGATION BAR
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => ServiceBookingBottomSheet(service: service),
        );
      }
    }
  }

  void _showServiceDetails(ServiceModel service) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true, // <--- ÉP HIỂN THỊ ĐÈ LÊN NAVIGATION BAR
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail Chi tiết
            Container(
              height: 200,
              width: double.infinity,
              decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(top: Radius.circular(32)), color: Colors.black),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                child: service.imageUrl != null 
                    ? Image.network(service.imageUrl!, fit: BoxFit.cover)
                    : service.videoUrl != null
                        ? MiniVideoPlayer(videoUrl: service.videoUrl!) // Hiển thị Video nếu không có ảnh
                        : const Center(child: Icon(Icons.spa, size: 60, color: Colors.white24)),
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFF80BF84).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                      child: Text(service.serviceTypeEnum == 'TREATMENT' ? 'TRỊ LIỆU' : 'THƯ GIÃN', style: const TextStyle(color: Color(0xFF80BF84), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    Text(service.serviceName, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        CircleAvatar(backgroundImage: NetworkImage(service.user['avatar_url'] ?? 'https://via.placeholder.com/150')),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(service.user['full_name'] ?? 'Đối tác', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              Text(service.user['physical_address'] ?? 'Cơ sở xác thực', style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(service.description, style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5)),
                  ],
                ),
              ),
            ),
            
            // Thanh Bottom Giá & Nút đặt
            Container(
              padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom + 10 : 20),
              decoration: const BoxDecoration(color: Colors.black, border: Border(top: BorderSide(color: Colors.white10))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('GIÁ DỊCH VỤ', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text('${service.price} VND', style: const TextStyle(color: Color(0xFF80BF84), fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                    onPressed: () {
                      // 1. Đóng bảng chi tiết dịch vụ trước (Giống setExpandedService(null) trên Web)
                      Navigator.of(context, rootNavigator: true).pop(); 
                      
                      // 2. Chờ hiệu ứng đóng hoàn tất rồi mới mở Form Đặt Lịch
                      Future.delayed(const Duration(milliseconds: 200), () {
                        if (mounted) _handleBookingClick(service);
                      });
                    },
                    child: const Text('ĐẶT LỊCH NGAY', style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Text('Khám phá ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
            Icon(Icons.auto_awesome, color: Color(0xFF80BF84), size: 24),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Bạn đang tìm dịch vụ gì hôm nay?...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                _buildFilterChip('ALL', 'Tất cả dịch vụ'),
                const SizedBox(width: 12),
                _buildFilterChip('RELAXATION', 'Thư giãn & Phục hồi'),
                const SizedBox(width: 12),
                _buildFilterChip('TREATMENT', 'Trị liệu chuyên sâu'),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)))
              : _filteredServices.isEmpty
                  ? const Center(child: Text('Không có dịch vụ nào', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 150, top: 10), // Tăng bottom padding để tránh đè Nav
                      itemCount: _filteredServices.length,
                      itemBuilder: (context, index) {
                        final service = _filteredServices[index];
                        return GestureDetector(
                          onTap: () => _showServiceDetails(service),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF121214),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.05)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thumbnail ngoài thẻ
                                Container(
                                  height: 180,
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                                    child: service.imageUrl != null 
                                        ? Image.network(service.imageUrl!, fit: BoxFit.cover)
                                        : service.videoUrl != null
                                            ? MiniVideoPlayer(videoUrl: service.videoUrl!) // Tự phát Video Preview
                                            : const Center(child: Icon(Icons.spa, color: Colors.white24, size: 50)),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(service.serviceName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 8),
                                      Text(service.description, style: const TextStyle(color: Colors.white54, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 16),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('${service.price} VND', style: const TextStyle(color: Color(0xFF80BF84), fontSize: 16, fontWeight: FontWeight.bold)),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: const CircleBorder(), padding: const EdgeInsets.all(12)),
                                            onPressed: () => _handleBookingClick(service),
                                            child: const Icon(Icons.calendar_month, size: 20),
                                          )
                                        ],
                                      )
                                    ],
                                  ),
                                )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String filterValue, String label) {
    final isActive = _activeFilter == filterValue;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filterValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Text(
          label, 
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 13
          )
        ),
      ),
    );
  }
}