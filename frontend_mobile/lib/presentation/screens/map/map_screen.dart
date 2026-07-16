import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart'; // Trục kết nối mạng lõi
import '../../widgets/booking_bottom_sheet.dart';
import '../../../data/models/partner_map_model.dart';
import '../../../data/services/map_api_service.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/auth_guard.dart';
import '../../widgets/shimmer_wrapper.dart';
import '../../widgets/notification_notifier.dart'; // 🚀 Bổ sung thư viện quản lý State thông báo

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with AutomaticKeepAliveClientMixin {
  
  // 🚀 THUẬT TOÁN KEEPALIVE ENGINE: Chống reset Tab Map (Giữ nguyên tọa độ)
  @override
  bool get wantKeepAlive => true;

  final MapController _mapController = MapController();
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  final TextEditingController _searchController = TextEditingController();
  
  List<PartnerMapModel> _partners = [];
  List<PartnerMapModel> _filteredPartners = [];
  PartnerMapModel? _selectedPartner;
  bool _isLoading = true;
  
  String _selectedCategory = 'Tất cả';
  LatLng _currentCenter = const LatLng(21.028511, 105.804817); // Mặc định Hà Nội
  LatLng? _userRealLocation;
  String? _userAvatarUrl; // Lưu avatar động của người dùng đăng nhập

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Tất cả', 'icon': Icons.grid_view_rounded},
    {'name': 'Spa & Clinic', 'icon': Icons.spa_rounded},
    {'name': 'Xét nghiệm', 'icon': Icons.science_rounded},
    {'name': 'Trị liệu Đông Y', 'icon': Icons.wheelchair_pickup_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _initMapDataLocationAndProfile();
  }

  @override
  void dispose() {
    _mapController.dispose();
    _sheetController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _isFetchingLock = false;
  // --- LUỒNG KHỞI TẠO ĐA LUỒNG SONG SONG KHÔNG CHẶN (NON-BLOCKING DECOUPLED PIPELINE) ---
  Future<void> _initMapDataLocationAndProfile() async {
    if (_isFetchingLock) return;
    _isFetchingLock = true;
    try {
      // 1. LUỒNG NGẦM A: Xin quyền và cập nhật tọa độ GPS thiết bị (Không dùng await để tránh nghẽn luồng)
      _determineUserLocation().catchError((error) {
        debugPrint("⚠️ Hệ thống GPS phản hồi chậm hoặc bị tắt: $error");
      });

      // 2. LUỒNG NGẦM B: Gọi trực tiếp cổng ApiClient đồng bộ với định dạng Swagger của hệ thống
      ApiClient.instance.get('/user/profile').then((response) {
        if (mounted && response.statusCode == 200 && response.data != null) {
          setState(() {
            // Sửa lỗi bóc tách JSON sai tầng cấu trúc
            final dynamic resData = response.data;
            final profileData = (resData is Map && resData.containsKey('data')) ? resData['data'] : resData;
            _userAvatarUrl = profileData['avatar_url']?.toString();
          });
        }
      }).catchError((e) => debugPrint("⚠️ Không thể tải avatar người dùng: $e"));

      // 3. LUỒNG CHÍNH ĐỐI TÁC: Gọi API lấy kho dữ liệu cơ sở Partner ngay lập tức
      final data = await MapApiService.fetchMapPartners();
      
      if (mounted) {
        setState(() {
          _partners = data;
          _filteredPartners = data;
          _isLoading = false; // Tắt trạng thái chờ, giải phóng dữ liệu thật lên giao diện
        });
        
        AppToast.show(context: context, message: '⚡ Đồng bộ thành công ${data.length} cơ sở quanh bạn!', isSuccess: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint("❌ SỰ CỐ TẠI LUỒNG KHỞI TẠO MAP: $e");
      AppToast.show(context: context, message: 'Mạng trục trặc, vui lòng kiểm tra lại!', isSuccess: false);
    } finally {
      _isFetchingLock = false;
    }
  }

  // Luồng xin quyền phần cứng và định vị GPS của thiết bị thật
  Future<void> _determineUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    
    if (permission == LocationPermission.deniedForever) return;

    final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    if (mounted) {
      setState(() {
        _userRealLocation = LatLng(position.latitude, position.longitude);
        _currentCenter = _userRealLocation!;
      });
      _mapController.move(_currentCenter, 14.5);
    }
  }

  // Tìm kiếm thời gian thực (Real-time Filter Search)
  void _performSearch(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredPartners = _selectedCategory == 'Tất cả' 
            ? _partners 
            : _partners.where((p) => p.tags.any((t) => t.toLowerCase().contains(_selectedCategory.toLowerCase()))).toList();
      } else {
        _filteredPartners = _partners.where((p) {
          final matchesQuery = p.fullName.toLowerCase().contains(query.toLowerCase()) || 
                               p.username.toLowerCase().contains(query.toLowerCase());
          final matchesCategory = _selectedCategory == 'Tất cả' || p.tags.any((t) => t.toLowerCase().contains(_selectedCategory.toLowerCase()));
          return matchesQuery && matchesCategory;
        }).toList();
      }
      _selectedPartner = null;
    });
  }

  void _filterCategory(String catName) {
    setState(() {
      _selectedCategory = catName;
      _searchController.clear();
      _filteredPartners = catName == 'Tất cả' 
          ? _partners 
          : _partners.where((p) => p.tags.any((t) => t.toLowerCase().contains(catName.toLowerCase()))).toList();
      _selectedPartner = null;
    });
  }

  void _selectPartnerFromMarker(PartnerMapModel partner) {
    setState(() {
      _selectedPartner = partner;
      _filteredPartners = [partner]; // Cô lập danh sách trên Bottom Sheet hiển thị duy nhất đối tác được chọn
    });
    _mapController.move(LatLng(partner.latitude, partner.longitude), 14.5);
    
    // Khi chọn Marker, đẩy nhẹ Bottom Sheet lên tầng Half-Expanded (0.55) để lộ thông tin rõ ràng
    _sheetController.animateTo(
      0.55, 
      duration: const Duration(milliseconds: 300), 
      curve: Curves.easeOutCubic
    );
    AppToast.show(context: context, message: '📍 Đã định vị cơ sở: ${partner.fullName}', isSuccess: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // BẮT BUỘC: Khởi động cơ chế KeepAlive
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: _isLoading
          ? ShimmerWrapper(
              child: Stack(
                children: [
                  // 1. Skeleton Nền Bản Đồ
                Container(color: const Color(0xFFE2ECEB)), 
                // 2. Skeleton Thanh Tìm Kiếm Lơ Lửng
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 10, left: 16, right: 16,
                  child: Container(height: 50, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30))),
                ),
                // 3. Skeleton Khối Half-BottomSheet
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: size.height * 0.55,
                    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10))),
                        const SizedBox(height: 20),
                        // Skeleton Bộ lọc Chips
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (index) => Container(margin: const EdgeInsets.symmetric(horizontal: 4), height: 36, width: 80, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(20))))),
                        const SizedBox(height: 32),
                        // Skeleton Thẻ Gợi Ý
                    Container(margin: const EdgeInsets.symmetric(horizontal: 16), height: 160, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(20))),
                  ],
                ),
              ),
            )
          ],
        ),
      )
      : Stack(
              children: [
                
                // LỚP 1: BẢN ĐỒ NỀN FULLSCREEN ĐẰNG SAU BẢNG ĐIỀU KHIỂN
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: size.height * 0.1),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentCenter,
                        initialZoom: 14.0,
                        minZoom: 4.0,
                        maxZoom: 18.0,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.aihealth.share',
                          tileProvider: NetworkTileProvider(), // Khắc phục dứt điểm lỗi build gối đầu
                        ),
                        
                        // LỚP MARKERS (GỒM CẢ ĐỐI TÁC VÀ USER AVATAR MỚI)
                          MarkerLayer(
                            markers: [
                              // VẼ MARKER ĐỊNH VỊ CHO CHÍNH NGƯỜI DÙNG (USER AVATAR HOẶC ICON HOLOGRAM)
                              if (_userRealLocation != null)
                                Marker(
                                  point: _userRealLocation!,
                                  width: 48,
                                  height: 48,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF80BF84).withOpacity(0.2),
                                      border: Border.all(color: Colors.white, width: 2.5),
                                      boxShadow: [
                                        BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.5), blurRadius: 10, spreadRadius: 3)
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(100),
                                      child: _userAvatarUrl != null
                                          ? GlobalCacheImage(
                                              imageUrl: _userAvatarUrl!, 
                                              fit: BoxFit.cover,
                                              memCacheWidth: 100, // 🚀 Tối ưu RAM cho Marker Bản đồ
                                              memCacheHeight: 100,
                                            )
                                          : const Icon(Icons.person_pin_circle_rounded, color: Color(0xFF4C8D50), size: 28),
                                    ),
                                  ),
                                ),

                              // Vẽ các Marker của Đối tác phòng khám
                              ..._filteredPartners.map((partner) {
                                final isSelected = _selectedPartner?.id == partner.id;
                                return Marker(
                                  point: LatLng(partner.latitude, partner.longitude),
                                  width: isSelected ? 52 : 42,
                                  height: isSelected ? 52 : 42,
                                  child: GestureDetector(
                                    onTap: () {
                                      _selectPartnerFromMarker(partner);
                                    },
                                    onDoubleTap: () {
                                      // 🚀 ĐỘC QUYỀN LUXURY: Double Tap vào Ghim trên bản đồ để phi thẳng vào Hồ sơ công khai
                                      context.push('/public-profile/${partner.username}');
                                    },
                                    child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: isSelected ? const Color(0xFF4C8D50) : Colors.white, width: isSelected ? 3.5 : 2),
                                      boxShadow: [BoxShadow(color: isSelected ? const Color(0xFF80BF84).withOpacity(0.6) : Colors.black26, blurRadius: isSelected ? 12 : 6)],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(100),
                                      child: GlobalCacheImage(
                                        imageUrl: partner.avatarUrl.isNotEmpty ? partner.avatarUrl : "https://ui-avatars.com/api/?name=${partner.username}&background=80BF84&color=fff",
                                        fit: BoxFit.cover,
                                        memCacheWidth: 150, // 🚀 Tối ưu RAM cho Marker Đối tác
                                        memCacheHeight: 150,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // LỚP 2: THANH TÌM KIẾM LƠ LỬNG TRÊN ĐỈNH APP
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 10,
                  left: 16,
                  right: 16,
                  child: _buildFloatingSearchBar(),
                ),

                // LỚP 3: NÚT Floating GPS ĐỊNH VỊ THIẾT BỊ NATIVE GÓC PHẢI MAP
                Positioned(
                  top: size.height * 0.28,
                  right: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'map_gps_action',
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF4C8D50),
                    elevation: 5,
                    shape: const CircleBorder(),
                    onPressed: () {
                      if (_userRealLocation != null) {
                        _mapController.move(_userRealLocation!, 15.0);
                        AppToast.show(context: context, message: '🔮 Đã đồng bộ tâm bản đồ về vị trí của bạn!', isSuccess: true);
                      } else {
                        _determineUserLocation();
                      }
                    },
                    child: const Icon(Icons.my_location_rounded, size: 20),
                  ),
                ),

                // LỚP 4: BẢNG ĐIỀU KHIỂN TRƯỢT ĐA TẦNG (MULTI-LEVEL SLIDING PANEL CHUẨN DESIGN SYSTEM)
                Positioned.fill(
                  child: NotificationListener<DraggableScrollableNotification>(
                    onNotification: (notification) {
                      return true;
                    },
                    child: DraggableScrollableSheet(
                      controller: _sheetController,
                      initialChildSize: 0.55, // Mặc định mở ở tầng giữa giống ảnh mẫu của bạn
                      minChildSize: 0.18,    // ⚡ TẦNG THẤP NHẤT: Chừa đúng 140px nhô lên, không bị cấn hay khuất bởi Nav Bar đáy 90px!
                      maxChildSize: 0.92,    // ⚡ TẦNG CAO NHẤT: Kéo tràn đỉnh đầu để xem rộng rãi tối đa
                      snap: true,            // Bật tính năng hít lò xo theo tầng động
                      snapSizes: const [0.18, 0.55, 0.92], // Cấu hình 3 khấc lò xo cố định
                      builder: (context, scrollController) {
                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F7F6),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, -5))
                            ],
                          ),
                          child: Column(
                            children: [
                              // THANH TAY CẦM TRỰC QUAN (DRAWER HANDLE BAR) ĐỂ NGƯỜI DÙNG KÉO LÊN/XUỐNG
                              Container(
                                margin: const EdgeInsets.only(top: 10, bottom: 4),
                                width: 40,
                                height: 5,
                                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                              ),
                              
                              // ĐƯA NỘI DUNG CUỘN VÀO TRONG ĐƯỜNG ỐNG SCROLL CONTROLLER NATIVE
                              Expanded(
                                child: ListView(
                                  controller: scrollController,
                                  physics: const ClampingScrollPhysics(), // Giữ cố định lề khi vuốt căng tầng
                                  padding: EdgeInsets.zero,
                                  children: [
                                    _buildHorizontalCategoryChips(),
                                    
                                    // 🟢 KHẮC PHỤC ĐIỂM NGHẼN: Hiển thị mảng dịch vụ thực tế và kết nối nút hành động Đặt lịch
                                    if (_selectedPartner != null) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                'Dịch vụ khả dụng tại ${_selectedPartner!.fullName}',
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black87),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.black45),
                                              onPressed: () {
                                                setState(() {
                                                  _selectedPartner = null;
                                                  _filteredPartners = _selectedCategory == 'Tất cả'
                                                      ? _partners
                                                      : _partners.where((p) => p.tags.any((t) => t.toLowerCase().contains(_selectedCategory.toLowerCase()))).toList();
                                                });
                                              },
                                            )
                                          ],
                                        ),
                                      ),
                                      if (_selectedPartner!.services.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          child: Text('Cơ sở chưa cập nhật danh sách dịch vụ y tế.', style: TextStyle(color: Colors.black38, fontSize: 12, fontStyle: FontStyle.italic)),
                                        )
                                      else
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                          child: Column(
                                            children: _selectedPartner!.services.map<Widget>((service) {
                                              final String name = service['service_name'] ?? service['name'] ?? 'Dịch vụ';
                                              final double price = (service['price'] ?? 0.0).toDouble();
                                              return Container(
                                                margin: const EdgeInsets.only(bottom: 8),
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(color: Colors.black.withOpacity(0.03)),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black87)),
                                                          const SizedBox(height: 2),
                                                          Text('${price.toStringAsFixed(0)} đ', style: const TextStyle(color: Color(0xFF4C8D50), fontWeight: FontWeight.bold, fontSize: 12)),
                                                        ],
                                                      ),
                                                    ),
                                                    ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: const Color(0xFF4C8D50),
                                                        foregroundColor: Colors.white,
                                                        elevation: 0,
                                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                        minimumSize: Size.zero,
                                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                      ),
                                                      onPressed: () {
                                                        AuthGuard.run(context, action: () {
                                                        // Đóng gói dữ liệu Map dịch vụ thành cấu trúc tương thích ngược mà BookingBottomSheet yêu cầu
                                                        final adaptedVideoPayload = {
                                                          'id': service['id'] ?? service['service_id'] ?? '',
                                                          'price': price,
                                                          'title': name,
                                                          'authorId': _selectedPartner!.id,
                                                          'author': {
                                                            'id': _selectedPartner!.id,
                                                            'username': _selectedPartner!.username,
                                                            'full_name': _selectedPartner!.fullName,
                                                          }
                                                        };

                                                        // Khởi tạo luồng hiển thị Bottom Sheet Đặt lịch chuẩn chỉ của hệ thống
                                                        showModalBottomSheet(
                                                          context: context,
                                                          isScrollControlled: true,
                                                          backgroundColor: Colors.transparent,
                                                            builder: (context) => BookingBottomSheet(video: adaptedVideoPayload),
                                                          );
                                                        });
                                                      },
                                                      child: const Text('ĐẶT LỊCH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 16),
                                        child: Divider(height: 24, thickness: 0.5),
                                      ),
                                    ],

                                    _buildSectionTitle("✨ Curations for you", "Nội dung y tế gần bạn"),
                                    _buildHorizontalCurationsList(),
                                    _buildSectionTitle("🩺 Curators for you", "Chuyên gia lân cận"),
                                    _buildVerticalCuratorsGrid(),
                                    
                                    // Khoảng trống an toàn bọc đáy chống cấn Nav Bar lơ lửng của Main Hub Screen
                                    const SizedBox(height: 120),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ==================== CÁC PHÂN HỆ WIDGET CHUẨN DESIGN SYSTEM ====================

  Widget _buildFloatingSearchBar() {
    return Row(
      children: [
        // Thanh tìm kiếm lơ lửng chiếm không gian chính
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Colors.black54, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        decoration: const InputDecoration(
                          hintText: 'Tìm phòng khám, đối tác quanh đây...',
                          hintStyle: TextStyle(color: Colors.black26, fontSize: 13, fontWeight: FontWeight.normal),
                          border: InputBorder.none,
                        ),
                        onChanged: _performSearch,
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                        child: const Icon(Icons.clear_rounded, color: Colors.black38, size: 20),
                      )
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12), // Khoảng cách giữa Search Bar và Nút Thông Báo
        
        // 🚀 NÚT THÔNG BÁO TÍCH HỢP HIỆU ỨNG KÍNH MỜ BẢN ĐỒ
        ListenableBuilder(
          listenable: NotificationNotifier.instance,
          builder: (context, child) {
            final unread = NotificationNotifier.instance.unreadCount;
            return GestureDetector(
              onTap: () => context.push('/notifications'),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.notifications_none_rounded, color: Colors.black54, size: 22),
                        if (unread > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFE2C55), // Badge đỏ cảnh báo nổi bật
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5), // Viền trắng bóc tách 3D
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHorizontalCategoryChips() {
    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _selectedCategory == cat['name'];
          return GestureDetector(
            onTap: () => _filterCategory(cat['name']),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1E3A1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isSelected ? Colors.transparent : Colors.black.withOpacity(0.04)),
              ),
              child: Row(
                children: [
                  Icon(cat['icon'] as IconData, size: 15, color: isSelected ? Colors.amber : Colors.black54),
                  const SizedBox(width: 8),
                  Text(
                    cat['name'] as String,
                    style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 12, fontWeight: FontWeight.w800),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String mainTitle, String subTitle) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 18, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mainTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
          Text(subTitle.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black38, letterSpacing: 0.5)),
        ],
      ),
    );
  }

  Widget _buildHorizontalCurationsList() {
    if (_filteredPartners.isEmpty) {
      return const SizedBox(height: 100, child: Center(child: Text("Không có nội dung phù hợp xung quanh.", style: TextStyle(color: Colors.grey, fontSize: 12))));
    }

    return SizedBox(
      height: 185,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _filteredPartners.length,
        itemBuilder: (context, index) {
          final partner = _filteredPartners[index];
          final isHighlighted = _selectedPartner?.id == partner.id;
          final String primaryTag = partner.tags.isNotEmpty ? partner.tags[0] : "AI Health";

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedPartner = partner;
              });
              _mapController.move(LatLng(partner.latitude, partner.longitude), 14.5);
              
              // 🚀 CẬP NHẬT ĐỒNG BỘ: Chạm nhẹ vào Thẻ nội dung tự động mở Public Profile của Partner
              Future.delayed(const Duration(milliseconds: 150), () {
                if (mounted) {
                  context.push('/public-profile/${partner.username}');
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 140,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isHighlighted ? const Color(0xFF4C8D50) : Colors.transparent, width: 2),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                        image: DecorationImage(
                          image: GlobalCacheProvider.create(
                            partner.avatarUrl.isNotEmpty ? partner.avatarUrl : "https://picsum.photos/200/300",
                            maxWidth: 280, // 🚀 Tối ưu RAM cho Thẻ gợi ý ngang
                            maxHeight: 350,
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            bottom: 8, left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                children: [
                                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 12),
                                  Text('  ${partner.distance.toStringAsFixed(1)} km', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('@${partner.username}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(primaryTag, style: TextStyle(color: const Color(0xFF4C8D50), fontSize: 9, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVerticalCuratorsGrid() {
    if (_filteredPartners.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(), // Chạy chung trục cuộn native mượt mà của DraggableSheet
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 14,
          crossAxisSpacing: 10,
          childAspectRatio: 0.72, // Đảm bảo chứa vừa vặn nút bấm hành động chuẩn chỉ
        ),
        itemCount: _filteredPartners.length,
        itemBuilder: (context, index) {
          final partner = _filteredPartners[index];
          final isHighlighted = _selectedPartner?.id == partner.id;
          // Loại bỏ việc mock số sao giảm dần theo index, tính toán đồng bộ dựa trên tags
          final int mockReputation = partner.tags.isNotEmpty ? (90 + (partner.tags.length % 6)) : 95;

          return Column(
            children: [
              Stack(
                alignment: Alignment.bottomCenter,
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: isHighlighted ? const Color(0xFF4C8D50) : Colors.white, width: isHighlighted ? 3 : 1.5),
                      image: DecorationImage(
                        image: GlobalCacheProvider.create(
                          partner.avatarUrl.isNotEmpty ? partner.avatarUrl : "https://ui-avatars.com/api/?name=${partner.username}&background=4C8D50&color=fff",
                          maxWidth: 160, // 🚀 Tối ưu RAM cho Thẻ chuyên gia dọc
                          maxHeight: 160,
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4)],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 9),
                          Text(' $mockReputation', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.black87)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                partner.fullName.split(' ').last,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              
              // BUTTON ĐIỀU HƯỚNG TRỎ VỀ PARTNER PUBLIC PROFILE KHÉP KÍN KHÔNG LỖI
              SizedBox(
                width: 64,
                height: 20,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF80BF84).withOpacity(0.15),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
                  ),
                  onPressed: () {
                    context.push('/public-profile/${partner.username}');
                  },
                  child: const Text('XEM HỒ SƠ', style: TextStyle(color: Color(0xFF4C8D50), fontSize: 8.5, fontWeight: FontWeight.w900)),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}