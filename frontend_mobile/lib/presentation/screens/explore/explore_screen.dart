import 'dart:ui';
import 'dart:async'; // Bổ sung thư viện quản lý luồng Timer tự động chuyển slide banner
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart'; // Đấu nối định tuyến nhanh Router 
import '../../../data/models/partner_map_model.dart'; // Nạp mô hình đối tác sạch 
import '../../../data/services/explore_api_service.dart'; // Nạp lớp dịch vụ 
import '../../widgets/mini_video_player.dart'; // Nạp trình phát video thực tế hệ thống
import '../../widgets/booking_bottom_sheet.dart'; // Nạp bảng cấu hình đặt lịch chuẩn 404-resolved
import '../../widgets/app_toast.dart'; // Bổ sung import AppToast để xử lý lỗi biên dịch
import '../../widgets/app_toast.dart'; // Bổ sung import AppToast để xử lý lỗi biên dịch

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<PartnerMapModel> _partners = []; // Chuẩn hóa kiểu dữ liệu mảng đối tượng 
  List<PartnerMapModel> _filteredPartners = []; // Bộ đệm lưu trữ dữ liệu sau khi lọc tìm kiếm
  
  // Các mảng trạng thái lưu trữ danh sách gói dịch vụ lẻ đồng bộ từ Web
  List<dynamic> _services = [];
  List<dynamic> _filteredServices = [];
  
  // Quản lý trạng thái Pop-up xem trước video lơ lửng công nghệ cao
  String? _activePreviewVideoUrl;
  dynamic _activeSelectedService; // Lưu trữ object dịch vụ cụ thể phục vụ luồng Booking liên thông
  
  bool _isLoading = true; // 

  // Khai báo bộ điều khiển nhập liệu cho thanh tìm kiếm
  final TextEditingController _searchController = TextEditingController();

  // Trạng thái lưu trữ bộ lọc nâng cao đồng bộ theo logic hệ thống
  String _selectedTypeFilter = 'ALL'; // Các giá trị: 'ALL' | 'RELAXATION' | 'TREATMENT'

  // Trạng thái lưu trữ Bộ lọc nhanh dịch vụ chính: 'NONE' | 'ONLINE' | 'CLINIC'
  String _selectedQuickService = 'NONE';

  // Trạng thái lưu trữ bộ lọc danh mục y tế khác: 'ALL' hoặc tên danh mục cụ thể
  String _selectedCategoryFilter = 'ALL';

  // Khai báo bộ điều khiển cuộn trang để xử lý Userflow của Banner
  final ScrollController _scrollController = ScrollController();

  // --- CẤU HÌNH BANNER CAROUSEL TỰ ĐỘNG DỊCH CHUYỂN MƯỢT MÀ ---
  late final PageController _bannerPageController = PageController(viewportFraction: 0.92);
  Timer? _bannerAutoSliderTimer;
  int _currentBannerIndex = 0;

  // Khởi tạo bộ dữ liệu 5 lời chúc/slogan cao cấp xoay vòng phối màu Gradient đa tầng
  final List<Map<String, dynamic>> _bannerQuotes = [
    {
      "title": "VÒNG XANH\nSỨC KHỎE",
      "slogan": "Trải nghiệm y tế chuẩn 5 sao",
      "wish": "✨ Chúc bạn một ngày mới ngập tràn năng lượng và thân tâm an lạc!",
      "colors": [Color(0xFF80BF84), Color(0xFF5B9E5F)]
    },
    {
      "title": "AN NHIÊN\nMỖI NGÀY",
      "slogan": "Chăm sóc chủ động, an tâm vững bước",
      "wish": "🌿 Sức khỏe là vàng, chúc bạn luôn giữ vững tinh thần lạc quan và rạng rỡ!",
      "colors": [Color(0xFF3B82F6), Color(0xFF1D4ED8)]
    },
    {
      "title": "SỐNG KHỎE\nSỐNG ĐẸP",
      "slogan": "Cân bằng thân - tâm - trí toàn diện",
      "wish": "🌸 Chúc bạn luôn rạng ngời, biết yêu thương bản thân và tràn đầy hạnh phúc!",
      "colors": [Color(0xFFEC4899), Color(0xFFBE185D)]
    },
    {
      "title": "TĨNH TÂM\nPHỤC HỒI",
      "slogan": "Liệu pháp chuyên sâu từ chuyên gia",
      "wish": "☀️ Mong mọi điều bình an và nhẹ nhàng nhất sẽ đến với hành trình của bạn ngày hôm nay!",
      "colors": [Color(0xFFF59E0B), Color(0xFFD97706)]
    },
    {
      "title": "NĂNG LƯỢNG\nBẤT TẬN",
      "slogan": "Lắng nghe cơ thể bạn lên tiếng mỗi giây",
      "wish": "💪 Khỏe mạnh từ bên trong! Chúc bạn vượt qua mọi mục tiêu với nguồn năng lượng đỉnh cao!",
      "colors": [Color(0xFF14B8A6), Color(0xFF0F766E)]
    },
  ];

  final _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ'); // 

  @override
  void initState() {
    super.initState();
    _fetchExploreData();
    // Đợi khung hình Flutter render xong (PostFrameCallback) rồi mới kích hoạt luồng tự động trượt
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bannerAutoSliderTimer = Timer.periodic(const Duration(milliseconds: 3500), (timer) {
        if (_bannerPageController.hasClients && _bannerPageController.position.hasContentDimensions) {
          // Tính toán vị trí trang kế tiếp, xoay vòng vô hạn
          int nextPage = _bannerPageController.page!.round() + 1;
          if (nextPage >= _bannerQuotes.length) {
            nextPage = 0; // Trở về thẻ đầu tiên nếu chạm đỉnh danh sách
          }
          
          _bannerPageController.animateToPage(
            nextPage,
            duration: const Duration(milliseconds: 800), // Tăng nhẹ thời gian chuyển trang giúp hiệu ứng Morph lộ rõ và mịn hơn
            curve: Curves.easeInOutCubic,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _bannerAutoSliderTimer?.cancel();
    _bannerPageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- ĐỒNG BỘ ĐƯỜNG ỐNG NẠP DỮ LIỆU SẠCH ---
  Future<void> _fetchExploreData() async {
    try {
      // Nạp song song cả danh sách đối tác bản đồ và mảng gói dịch vụ lẻ chuẩn Web
      final partnerData = await ExploreApiService.fetchExplorePartners(); // 
      final serviceData = await ExploreApiService.fetchAllServices();
      
      if (mounted) {
        setState(() {
          _partners = partnerData; // 
          _filteredPartners = partnerData; // Khởi tạo dữ liệu bộ đệm ban đầu trùng với dữ liệu gốc
          
          _services = serviceData;
          _filteredServices = serviceData;
          
          _isLoading = false; // 
        });
        _applyFilters(); // Kích hoạt bộ lọc tổng hợp đồng bộ cả 2 kho dữ liệu
      }
    } catch (e) {
      debugPrint("Lỗi nạp dữ liệu Explore UI: $e"); // 
      if (mounted) setState(() => _isLoading = false); // 
    }
  }

  // --- LOGIC ÁP DỤNG BỘ LỌC TỔNG HỢP (TỪ KHÓA & LOẠI HÌNH) ---
  void _applyFilters() {
    final String query = _searchController.text.toLowerCase();
    
    setState(() {
      _filteredPartners = _partners.where((partner) {
        // 1. Kiểm tra điều kiện từ khóa tìm kiếm
        bool matchesSearch = true;
        if (query.isNotEmpty) {
          final String partnerName = partner.fullName?.toLowerCase() ?? '';
          final String partnerUsername = partner.username?.toLowerCase() ?? '';
          final bool matchesName = partnerName.contains(query) || partnerUsername.contains(query);
          final bool matchesTags = partner.tags?.any((tag) => tag.toLowerCase().contains(query)) ?? false;
          matchesSearch = matchesName || matchesTags;
        }

        // 2. Kiểm tra điều kiện loại hình dịch vụ nâng cao (RELAXATION / TREATMENT)
        bool matchesType = true;
        if (_selectedTypeFilter != 'ALL') {
          matchesType = partner.services?.any((s) => 
            (s['service_type'] ?? s['service_type_enum'] ?? '').toString().toUpperCase() == _selectedTypeFilter
          ) ?? false;
        }

        // 3. Kiểm tra điều kiện Bộ lọc nhanh (Khám Online / Đặt lịch cơ sở)
        bool matchesQuickService = true;
        if (_selectedQuickService == 'ONLINE') {
          matchesQuickService = partner.services?.any((s) {
            final String serviceName = (s['service_name'] ?? '').toString().toLowerCase();
            return serviceName.contains('online') || serviceName.contains('video') || serviceName.contains('từ xa');
          }) ?? false;
        } else if (_selectedQuickService == 'CLINIC') {
          matchesQuickService = partner.services?.any((s) {
            final String serviceName = (s['service_name'] ?? '').toString().toLowerCase();
            return !serviceName.contains('online') && !serviceName.contains('video');
          }) ?? false;
        }

        // 4. Kiểm tra điều kiện Bộ lọc theo danh mục y tế khác
        bool matchesCategory = true;
        if (_selectedCategoryFilter != 'ALL') {
          final String targetCat = _selectedCategoryFilter.toLowerCase();
          final bool hasMatchingTag = partner.tags?.any((tag) => tag.toLowerCase().contains(targetCat)) ?? false;
          final bool hasMatchingServiceName = partner.services?.any((s) => 
            (s['service_name'] ?? '').toString().toLowerCase().contains(targetCat)
          ) ?? false;
          matchesCategory = hasMatchingTag || hasMatchingServiceName;
        }

        return matchesSearch && matchesType && matchesQuickService && matchesCategory;
      }).toList();

      // ĐỒNG BỘ LOGIC LỌC MẢNG DỊCH VỤ LẺ THEO CHUẨN WEBSITE (page.tsx)
      _filteredServices = _services.where((service) {
        final String sName = (service['service_name'] ?? '').toString().toLowerCase();
        final String sDesc = (service['description'] ?? '').toString().toLowerCase();
        final String sType = (service['service_type_enum'] ?? service['service_type'] ?? '').toString().toUpperCase();

        // 1. Đối chiếu từ khóa tìm kiếm
        bool matchesSearch = true;
        if (query.isNotEmpty) {
          matchesSearch = sName.contains(query) || sDesc.contains(query);
        }

        // 2. Đối chiếu bộ lọc nâng cao (ALL | RELAXATION | TREATMENT)
        bool matchesType = true;
        if (_selectedTypeFilter != 'ALL') {
          matchesType = (sType == _selectedTypeFilter);
        }

        // 3. Đối chiếu bộ lọc danh mục y tế khác
        bool matchesCategory = true;
        if (_selectedCategoryFilter != 'ALL') {
          final String targetCat = _selectedCategoryFilter.toLowerCase();
          matchesCategory = sName.contains(targetCat) || sDesc.contains(targetCat);
        }

        return matchesSearch && matchesType && matchesCategory;
      }).toList();
    });
  }

  void _onSearchChanged(String query) {
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA), // Nền xám nhạt làm bật các khối Card trắng 
      body: Stack(
        children: [
          CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()), // 
        slivers: [
          // 1. THANH TÌM KIẾM LƠ LỬNG (Floating Search Bar) 
          SliverAppBar(
            floating: true,
            snap: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent, // 
            title: _buildFloatingSearchBar(),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(10),
              child: SizedBox(), // 
            ),
          ),

          // 2. BANNER QUẢNG CÁO / SỰ KIỆN CO-BRANDING 
          SliverToBoxAdapter(
            child: _buildBannerCarousel(), // 
          ),

          // 3. KHỐI DỊCH VỤ CHÍNH (Tương đương Đặt xe / Đặt đồ ăn) 
          SliverToBoxAdapter(
            child: _buildPrimaryServices(), // 
          ),

          // 4. DANH SÁCH GỢI Ý ĐỐI TÁC (Tích hợp dữ liệu thật từ R2 & DB) 
          SliverToBoxAdapter(
            child: _buildHorizontalList(title: "✨ Gần bạn có dịch vụ tốt, thử luôn không?"), // 
          ),

          // 5. LƯỚI DANH MỤC CHUYÊN KHOA 
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 24, bottom: 12), // 
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
              "Dịch vụ y tế khác",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black87), // 
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedCategoryFilter = 'ALL';
                });
                _applyFilters();
              }, // 
              child: Text(
                "Xem tất cả", 
                style: TextStyle(
                  color: _selectedCategoryFilter == 'ALL' ? const Color(0xFF80BF84) : Colors.grey, 
                  fontWeight: FontWeight.bold
                )
              ), // 
            ),
                ],
              ),
            ),
          ),
          _buildCategoryGrid(), // 

          // --- BỔ SUNG KHU VỰC LƯỚI GÓI DỊCH VỤ Y TẾ LẺ ĐỒNG BỘ LOGIC WEB ---
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 32, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "🔥 Gói dịch vụ y tế thịnh hành", 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Hiển thị ${_filteredServices.length} gói khám xác thực", 
                    style: const TextStyle(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
            ),
          ),
          
          _buildServiceGrid(), // Khởi chạy lưới ô dịch vụ co giãn

          // Spacer an toàn chống lẹm tiêu chuẩn vào thanh Nav Bar lơ lửng 
          const SliverToBoxAdapter(
            child: SizedBox(height: 140), // 
          ),
        ],
      ),
      
      // --- POP-UP XEM TRƯỚC VIDEO (PREVIEW OVERLAY DIALOG LƠ LỬNG TRÊN STACK) ---
      if (_activePreviewVideoUrl != null) _buildVideoPreviewPopup(),
    ],
   ),
  );
}

  // --- WIDGET DIALOG POP-UP XEM TRƯỚC VIDEO AN TOÀN ---
  Widget _buildVideoPreviewPopup() {
    final String serviceName = (_activeSelectedService?['service_name'] ?? 'Gói dịch vụ y tế').toString();
    final double price = (_activeSelectedService?['price'] ?? 0).toDouble();

    return Positioned.fill(
      child: Stack(
        children: [
          // Lớp nền mờ tối bảo mật góc nhìn
          GestureDetector(
            onTap: () => setState(() {
              _activePreviewVideoUrl = null;
              _activeSelectedService = null;
            }),
            child: Container(
              color: Colors.black.withOpacity(0.75),
            ),
          ),
          // Khối hộp khung hình Mini-Player thông minh
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.88,
              height: MediaQuery.of(context).size.width * 1.35,
              decoration: BoxDecoration(
                color: const Color(0xFF131316), 
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5)
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // 1. EMBED TRÌNH PHÁT VIDEO THỰC TẾ (Zero-latency video streaming)
                  Positioned.fill(
                    bottom: 95, // Nhường không gian phía đáy cho khay thông tin thanh toán đặt lịch
                    child: MiniVideoPlayer(videoUrl: _activePreviewVideoUrl!),
                  ),

                  // 2. NÚT ĐÓNG POP-UP NHANH GÓC TRÊN KHUNG HÌNH
                  Positioned(
                    top: 16,
                    right: 16,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _activePreviewVideoUrl = null;
                        _activeSelectedService = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ),

                  // 3. KHAY THÔNG TIN DỊCH VỤ VÀ SHORTCUT ĐẶT LỊCH KÍNH MỜ CAO CẤP
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 95,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131316).withOpacity(0.92),
                        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
                      ),
                      child: Row(
                        children: [
                          // Khối chữ tiêu đề và giá gói khám lẻ
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  serviceName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currencyFormat.format(price),
                                  style: const TextStyle(color: Color(0xFF80BF84), fontSize: 16, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // NÚT BẤM "ĐẶT LỊCH NGAY" ĐỒNG BỘ LOGIC HỆ THỐNG WEB - MOBILE
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF80BF84),
                              foregroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              elevation: 0,
                            ),
                            onPressed: () {
                              final dynamic currentService = _activeSelectedService;
                              
                              // SỬA LỖI NGHIÊM TRỌNG LUỒNG ĐẶT LỊCH: Gán adapter Map payload để tương thích hoàn toàn với getters của BookingBottomSheet
                              if (currentService != null) {
                                currentService['id'] = currentService['id'] ?? '';
                                currentService['price'] = currentService['price'] ?? 0;
                                currentService['authorId'] = currentService['partner_id']; // Đồng bộ mã hóa trường partner_id sang authorId
                              }

                              // Tắt Pop-up xem video trước khi mở BottomSheet đặt lịch để tránh xung đột overlay
                              setState(() {
                                _activePreviewVideoUrl = null;
                                _activeSelectedService = null;
                              });
                              
                              // Kích hoạt vuốt mở bảng đơn đặt lịch chuẩn hệ thống, không còn bị vấp lỗi Null/AuthorID nữa
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.transparent,
                                builder: (context) => BookingBottomSheet(video: currentService),
                              );
                            },
                            child: const Row(
                              children: [
                                Icon(Icons.calendar_month_rounded, size: 16),
                                SizedBox(width: 6),
                                Text('ĐẶT LỊCH', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET LƯỚI DỊCH VỤ LẺ ĐỒNG BỘ THEO MẪU GIAO DIỆN WEB ---
  // --- WIDGET LƯỚI DỊCH VỤ LẺ ĐỒNG BỘ THEO MẪU GIAO DIỆN WEB ---
  Widget _buildServiceGrid() {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator(color: Color(0xFF80BF84)))),
      );
    }
    
    if (_filteredServices.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(child: Padding(padding: EdgeInsets.all(40.0), child: Text("Không tìm thấy gói dịch vụ phù hợp.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)))),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 32),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16, // Tăng khoảng trống thở dọc chuẩn UX
          crossAxisSpacing: 16, // Tăng khoảng trống thở ngang chuẩn UX
          childAspectRatio: 0.65, // Tối ưu chiều cao hộp thẻ để không gian text rộng rãi, chống tràn
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final service = _filteredServices[index];
            final String serviceName = (service['service_name'] ?? 'Gói dịch vụ y tế').toString();
            final double price = (service['price'] ?? 0).toDouble();
            final String? imageUrl = service['image_url'];
            final String? videoUrl = service['video_url'];
            
            final Map<String, dynamic> userData = service['users'] ?? {};
            final String partnerName = (userData['full_name'] ?? 'Cơ sở chuyên khoa').toString();

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20), // Tinh chỉnh bo góc mềm mại, cao cấp
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04), 
                    blurRadius: 12, 
                    offset: const Offset(0, 4)
                  )
                ],
                border: Border.all(color: Colors.black.withOpacity(0.03), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Khung Media tỉ lệ vàng di động 4:3 thay vì tỉ lệ vuông bóp nghẹt diện tích
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: GestureDetector(
                        onTap: () {
                          if (videoUrl != null && videoUrl.isNotEmpty) {
                            setState(() {
                              _activePreviewVideoUrl = videoUrl;
                              _activeSelectedService = service;
                            });
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          color: Colors.grey.shade50,
                          child: videoUrl != null && videoUrl.isNotEmpty
                              ? MiniVideoPlayer(videoUrl: videoUrl)
                              : (imageUrl != null && imageUrl.isNotEmpty
                                  ? Image.network(imageUrl, fit: BoxFit.cover)
                                  : Center(child: Icon(Icons.medical_services_outlined, color: Colors.grey.shade400, size: 28))),
                        ),
                      ),
                    ),
                  ),
                  
                  // 2. Khu vực thông tin phân bổ khoa học, thông thoáng bằng Expanded Layout
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween, // Đã sửa lỗi: Sử dụng spaceBetween chuẩn Flutter
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                partnerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF5B9E5F)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                serviceName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87, height: 1.3),
                              ),
                            ],
                          ),
                          
                          // Khối thông tin tài chính và nút shortcut đặt lịch công thái học dạng hàng ngang
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _currencyFormat.format(price),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF3B82F6), letterSpacing: -0.3),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) => BookingBottomSheet(video: service),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF80BF84).withOpacity(0.12), 
                                    shape: BoxShape.circle
                                  ),
                                  child: const Icon(Icons.calendar_month_rounded, size: 14, color: Color(0xFF5B9E5F)),
                                ),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            );
          },
          childCount: _filteredServices.length,
        ),
      ),
    );
  }

  Widget _buildFloatingSearchBar() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Colors.black54, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(
                hintText: 'Bạn muốn tìm chuyên khoa nào?',
                hintStyle: TextStyle(color: Colors.black38, fontSize: 15, fontWeight: FontWeight.w500),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.clear_rounded, color: Colors.black38, size: 20),
              ),
            ),
          GestureDetector(
            onTap: () => _showFilterBottomSheet(context),
            child: Icon(
              Icons.tune_rounded, 
              color: _selectedTypeFilter != 'ALL' ? const Color(0xFF80BF84) : Colors.black54, 
              size: 22
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext bc) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Bộ lọc nâng cao',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.close_rounded, color: Colors.black45),
                        )
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Loại hình dịch vụ',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      children: [
                        _buildFilterChip(context, setModalState, 'Tất cả dịch vụ', 'ALL'),
                        _buildFilterChip(context, setModalState, 'Thư giãn & Phục hồi', 'RELAXATION'),
                        _buildFilterChip(context, setModalState, 'Trị liệu chuyên sâu', 'TREATMENT'),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(BuildContext context, StateSetter setModalState, String label, String value) {
    final bool isSelected = _selectedTypeFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
      selectedColor: const Color(0xFF80BF84),
      backgroundColor: Colors.grey.shade100,
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(100),
        side: BorderSide.none,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      onSelected: (bool selected) {
        if (selected) {
          setModalState(() {
            _selectedTypeFilter = value;
          });
          setState(() {
            _selectedTypeFilter = value;
          });
          _applyFilters();
        }
      },
    );
  }

  Widget _buildBannerCarousel() {
    return SizedBox(
      height: 176,
      child: PageView.builder(
        controller: _bannerPageController,
        itemCount: _bannerQuotes.length,
        onPageChanged: (index) {
          // Cập nhật trạng thái chỉ mục thực tế để hệ thống Dots Indicator sáng đúng vị trí
          _currentBannerIndex = index;
          setState(() {});
        },
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final banner = _bannerQuotes[index];
          final List<Color> colors = banner['colors'] as List<Color>;
          
          // Tính toán hiệu ứng Morph co giãn nhẹ khoảng cách lề (Viewport Animation)
          return AnimatedBuilder(
            animation: _bannerPageController,
            builder: (context, child) {
              double value = 1.0;
              if (_bannerPageController.position.hasContentDimensions) {
                value = _bannerPageController.page! - index;
                value = (1 - (value.abs() * 0.04)).clamp(0.0, 1.0);
              }
              return Center(
                child: SizedBox(
                  height: Curves.easeInOut.transform(value) * 160,
                  width: double.infinity,
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onTap: () {
                // Điều chỉnh cú pháp gọi AppToast chuẩn chỉ, đồng bộ theo thiết kế hệ thống
                AppToast.show(
                  context: context,
                  message: banner['wish'].toString(),
                  isSuccess: true,
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colors[0].withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 24,
                      top: 28,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            banner['title'].toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            banner['slogan'].toString(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Hệ thống thanh chỉ báo trang (Dots Indicator) nằm gọn gàng bên trong thẻ Card
                    Positioned(
                      bottom: 14,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_bannerQuotes.length, (dotIndex) {
                          final bool isActive = _currentBannerIndex == dotIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: isActive ? 16 : 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.white : Colors.white.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    )
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPrimaryServices() {
    final bool isOnlineSelected = _selectedQuickService == 'ONLINE';
    final bool isClinicSelected = _selectedQuickService == 'CLINIC';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedQuickService = isOnlineSelected ? 'NONE' : 'ONLINE';
                });
                _applyFilters();
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 90),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isOnlineSelected ? const Color(0xFFE3F2FD) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isOnlineSelected ? Border.all(color: Colors.blue.withOpacity(0.5), width: 1.5) : null,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_camera_front_rounded, color: isOnlineSelected ? Colors.blue.shade700 : Colors.blue, size: 26),
                    const SizedBox(height: 6),
                    Text(
                      "Khám Online", 
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 13, 
                        color: isOnlineSelected ? Colors.blue.shade900 : Colors.black87
                      )
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedQuickService = isClinicSelected ? 'NONE' : 'CLINIC';
                });
                _applyFilters();
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 90),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isClinicSelected ? const Color(0xFFE8F5E9) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isClinicSelected ? Border.all(color: const Color(0xFF80BF84).withOpacity(0.5), width: 1.5) : null,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.storefront_rounded, color: isClinicSelected ? const Color(0xFF4CAF50) : const Color(0xFF80BF84), size: 26),
                    const SizedBox(height: 6),
                    Text(
                      "Đặt lịch cơ sở", 
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        fontSize: 13, 
                        color: isClinicSelected ? const Color(0xFF2E7D32) : Colors.black87
                      )
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalList({required String title}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12, top: 8),
          child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
        ),
        SizedBox(
          height: 230,
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)))
            : _filteredPartners.isEmpty
              ? const Center(child: Text("Không tìm thấy kết quả phù hợp.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _filteredPartners.length,
                  itemBuilder: (context, index) {
                    final partner = _filteredPartners[index];
                    final List<String> tags = partner.tags;
                    final String primaryTag = tags.isNotEmpty ? tags[0] : "Chăm sóc sức khỏe";
                    
                    final List<dynamic> services = partner.services;
                    double minPrice = 0;
                    if (services.isNotEmpty) {
                      minPrice = (services[0]['price'] ?? 0).toDouble();
                      for (var s in services) {
                         if ((s['price'] ?? 0) < minPrice) minPrice = (s['price'] ?? 0).toDouble();
                      }
                    }

                    return GestureDetector(
                      onTap: () {
                        context.push('/public-profile/${partner.username}');
                      },
                      child: Container(
                        width: 160,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 110,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                image: DecorationImage(
                                  image: NetworkImage(
                                    partner.avatarUrl.isNotEmpty 
                                        ? partner.avatarUrl 
                                        : "https://ui-avatars.com/api/?name=${partner.username}&background=80BF84&color=fff"
                                  ), 
                                  fit: BoxFit.cover
                                )
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 8, left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: const Color(0xFF80BF84), borderRadius: BorderRadius.circular(8)),
                                      child: Text(primaryTag, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                    ),
                                  )
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    partner.fullName.isNotEmpty ? partner.fullName : partner.username,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black87),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                                      const Text(" 4.9 ", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                      Text("• ${partner.distance.toStringAsFixed(1)} km", style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (minPrice > 0)
                                    Text("Từ ${_currencyFormat.format(minPrice)}", style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.w800)),
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
    );
  }

  Widget _buildCategoryGrid() {
    final categories = [
      {"icon": Icons.spa_rounded, "name": "Spa & Clinic", "color": Colors.pink},
      {"icon": Icons.medical_services_rounded, "name": "Khám tổng quát", "color": Colors.blue},
      {"icon": Icons.science_rounded, "name": "Xét nghiệm", "color": Colors.purple},
      {"icon": Icons.wheelchair_pickup_rounded, "name": "Trị liệu", "color": Colors.orange},
      {"icon": Icons.health_and_safety_rounded, "name": "Nha khoa", "color": Colors.teal},
      {"icon": Icons.psychology_rounded, "name": "Tâm lý", "color": Colors.indigo},
      {"icon": Icons.monitor_weight_rounded, "name": "Dinh dưỡng", "color": Colors.green},
      {"icon": Icons.vaccines_rounded, "name": "Nhà thuốc", "color": Colors.redAccent},
    ];

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final cat = categories[index];
            final String catName = cat['name'] as String;
            final bool isSelected = _selectedCategoryFilter == catName;

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategoryFilter = isSelected ? 'ALL' : catName;
                });
                _applyFilters();
              },
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: isSelected ? (cat['color'] as Color) : (cat['color'] as Color).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                      boxShadow: isSelected ? [BoxShadow(color: (cat['color'] as Color).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : null,
                    ),
                    child: Icon(
                      cat['icon'] as IconData, 
                      color: isSelected ? Colors.white : cat['color'] as Color, 
                      size: 26
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    catName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600, 
                      color: isSelected ? (cat['color'] as Color) : Colors.black87
                    ),
                    maxLines: 2,
                  )
                ],
              ),
            );
          },
          childCount: categories.length,
        ),
      ),
    );
  }
}