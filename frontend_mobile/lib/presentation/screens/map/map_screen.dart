import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../data/models/partner_map_model.dart';
import '../../../data/services/map_api_service.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  List<PartnerMapModel> _partners = [];
  PartnerMapModel? _selectedPartner;
  bool _isLoading = true;
  
  // Tọa độ mặc định (Hà Nội) nếu người dùng từ chối cấp quyền
  LatLng _currentCenter = const LatLng(21.028511, 105.804817);
  LatLng? _userRealLocation; 
  double _currentZoom = 14.0;

  @override
  void initState() {
    super.initState();
    _initMapDataAndLocation();
  }

  // LUỒNG TẢI SONG SONG (Tối ưu Tốc độ Load)
  Future<void> _initMapDataAndLocation() async {
    // Chạy song song cả API và Xin quyền GPS để triệt tiêu thời gian chờ
    final results = await Future.wait([
      MapApiService.fetchMapPartners(),
      _determinePosition().catchError((_) => null), // Nếu từ chối GPS, không crash app
    ]);

    List<PartnerMapModel> partners = results[0] as List<PartnerMapModel>;
    Position? userPos = results[1] as Position?;

    if (userPos != null) {
      _userRealLocation = LatLng(userPos.latitude, userPos.longitude);
      _currentCenter = _userRealLocation!; // Dời tâm bản đồ về người dùng
      _currentZoom = 15.0;

      // Tính toán khoảng cách thực tế từ User đến các cơ sở
      for (var p in partners) {
        double distanceMeters = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude, p.latitude, p.longitude,
        );
        // Đổi ra km và làm tròn 1 chữ số thập phân
        p.distance = double.parse((distanceMeters / 1000).toStringAsFixed(1));
      }
      // Sắp xếp ưu tiên hiển thị cơ sở gần nhất
      partners.sort((a, b) => a.distance.compareTo(b.distance));
    }

    if (mounted) {
      setState(() {
        _partners = partners;
        _isLoading = false;
      });
      // Di chuyển bản đồ mượt mà đến vị trí khởi tạo
      _mapController.move(_currentCenter, _currentZoom);
    }
  }

  // LUỒNG XIN QUYỀN VÀ LẤY VỊ TRÍ
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return Future.error('Location services are disabled.');

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    } 

    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  // Nút bấm: Về vị trí của tôi
  void _locateMe() async {
    try {
      Position pos = await _determinePosition();
      setState(() {
        _userRealLocation = LatLng(pos.latitude, pos.longitude);
      });
      _mapController.move(_userRealLocation!, 16.0);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng bật định vị GPS trong cài đặt.')));
    }
  }

  void _onMarkerTapped(PartnerMapModel partner) {
    setState(() => _selectedPartner = partner);
    _mapController.move(LatLng(partner.latitude, partner.longitude), 16.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      body: Stack(
        children: [
          // 1. LỚP BẢN ĐỒ NỀN (Kéo dài trọn màn hình)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentCenter,
              initialZoom: _currentZoom,
              onTap: (_, __) => setState(() => _selectedPartner = null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.aihealth.share',
                
                // 1. Thuật toán cốt lõi: Tự động HỦY tải các ảnh PNG đã trôi ra khỏi màn hình
                tileProvider: CancellableNetworkTileProvider(), 
                
                // 2. Mở rộng bộ đệm RAM: Giữ lại ảnh rộng hơn xung quanh viền màn hình
                keepBuffer: 6, 
                
                // 3. Đoán trước hướng vuốt: Tải trước 2 lớp ảnh ở hướng tay người dùng đang kéo tới
                panBuffer: 2, 
                
                // 4. Khóa giới hạn Zoom mạng: Không tải ảnh phân giải quá cao gây nặng máy
                maxNativeZoom: 18, 
                
                // 5. Zoom nội suy: Cho phép phóng to cận cảnh bằng cách scale mờ ảnh cũ thay vì bắt tải lại
                maxZoom: 22, 
              ),
              MarkerLayer(
                markers: [
                  // Vẽ các đối tác
                  ..._partners.map((p) => Marker(
                    point: LatLng(p.latitude, p.longitude),
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onTap: () => _onMarkerTapped(p),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Color(0xFF80BF84),
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1)],
                            ),
                            child: CircleAvatar(radius: 16, backgroundImage: NetworkImage(p.avatarUrl)),
                          ),
                          const Icon(Icons.arrow_drop_down, color: Color(0xFF80BF84), size: 14),
                        ],
                      ),
                    ),
                  )),
                  
                  // Vẽ Vị trí người dùng (Chấm xanh)
                  if (_userRealLocation != null)
                    Marker(
                      point: _userRealLocation!,
                      width: 24,
                      height: 24,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 10, spreadRadius: 5)],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 2. LỚP PHỦ TÌM KIẾM
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: Colors.grey),
                  SizedBox(width: 12),
                  Text('Tìm cơ sở, địa chỉ...', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  Spacer(),
                  Icon(Icons.filter_list, color: Color(0xFF80BF84)),
                ],
              ),
            ),
          ),

          // 3. NÚT ĐỊNH VỊ (LOCATE ME) TÍCH HỢP TRÊN BẢN ĐỒ
          Positioned(
            right: 16,
            bottom: _selectedPartner != null ? 350 : 120, // Nảy lên nếu có thẻ thông tin mở
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: FloatingActionButton(
                heroTag: 'locate_me_btn',
                backgroundColor: Colors.white.withOpacity(0.9),
                onPressed: _locateMe,
                child: const Icon(Icons.my_location, color: Colors.blueAccent),
              ),
            ),
          ),

          // 4. THẺ THÔNG TIN ĐỐI TÁC TRƯỢT LÊN Ở ĐÁY
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutQuart,
            bottom: _selectedPartner != null ? 100 : -350,
            left: 16,
            right: 16,
            child: _selectedPartner == null ? const SizedBox() : _buildPartnerCard(_selectedPartner!),
          ),

          // Màn chắn Loading khi mới vào
          if (_isLoading)
            Container(
              color: const Color(0xFF09090b).withOpacity(0.5),
              child: const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84))),
            ),
        ],
      ),
    );
  }

  Widget _buildPartnerCard(PartnerMapModel partner) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 30, backgroundImage: NetworkImage(partner.avatarUrl)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFF80BF84).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: const Row(
                              children: [
                                Icon(Icons.verified_user, color: Color(0xFF80BF84), size: 10),
                                SizedBox(width: 4),
                                Text('Đã xác thực', style: TextStyle(color: Color(0xFF80BF84), fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (partner.tags.isNotEmpty)
                            Text(partner.tags[0], style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(partner.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('${partner.distance} km • So với vị trí của bạn', style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.grey), onPressed: () => setState(() => _selectedPartner = null)),
              ],
            ),
          ),
          
          if (partner.services.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: partner.services.length,
                itemBuilder: (context, index) {
                  final s = partner.services[index];
                  return Container(
                    width: 150,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(s['service_name'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('${s['price']}đ', style: const TextStyle(color: Color(0xFF80BF84), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.black),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang điều hướng đến Hồ sơ đối tác...')));
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('XEM HỒ SƠ & ĐẶT LỊCH', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(width: 8),
                    Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}