// lib/main.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
// ***** จุดแก้ไข 1: เพิ่ม as fm เพื่อป้องกันชื่อซ้ำซ้อน *****
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import 'models/coupon_model.dart';

// --- สร้าง Service สำหรับจัดการ API ---
class ApiService {
  final String baseUrl = "https://goldticket.up.railway.app/api";

  Future<List<Coupon>> fetchCoupons() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/treasures'));
      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));
        return body.map((dynamic item) => Coupon.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load coupons: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Network Error: $e');
    }
  }

  Future<Coupon> placeCoupon(Coupon coupon) async {
    final response = await http.post(
      Uri.parse('$baseUrl/treasures'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(coupon.toJson()),
    );
    if (response.statusCode == 201) {
      return Coupon.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      throw Exception('Failed to place coupon');
    }
  }

  Future<void> claimCoupon(String id) async {
    final response = await http.patch(Uri.parse('$baseUrl/treasures/$id'));
    if (response.statusCode != 200) {
      throw Exception('Failed to claim coupon');
    }
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'แผนที่แสดงคูปอง',
      theme: ThemeData(
          colorScheme: const ColorScheme.light().copyWith(
            primary: Colors.brown,
            secondary: Colors.brown.shade300,
          ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
          scaffoldBackgroundColor: const Color(0xFFF5F5F5),
          dialogTheme: DialogThemeData(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.grey.shade100,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.brown,
              foregroundColor: Colors.white,
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: Colors.brown,
            ),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.brown,
            foregroundColor: Colors.white,
          )),
      home: const CouponMapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

enum UserRole { placer, hunter }

class CouponMapScreen extends StatefulWidget {
  const CouponMapScreen({super.key});

  @override
  State<CouponMapScreen> createState() => _CouponMapScreenState();
}

class _CouponMapScreenState extends State<CouponMapScreen> {
  final ApiService apiService = ApiService();
  UserRole _currentRole = UserRole.hunter;
  // ***** จุดแก้ไข 2: เพิ่ม fm. *****
  final fm.MapController _mapController = fm.MapController();
  LatLng? _currentLocation;
  bool _isLoading = true;
  List<Coupon> _coupons = [];

  // --- ตัวแปรสำหรับ Draggable Switch ---
  double _sliderPosition = 0;
  Duration _animationDuration = const Duration(milliseconds: 250);
  static const double switchWidth = 220.0;
  static const double switchHeight = 40.0;

  // --- ตัวแปรควบคุม Animation Overlay ---
  UserRole? _roleToShowInAnimation;
  Timer? _animationTimer;

  final _shopNameController = TextEditingController();
  final _igController = TextEditingController();
  final _facebookController = TextEditingController();
  final _missionController = TextEditingController();
  final _discountPercentController = TextEditingController();
  final _discountBahtController = TextEditingController();
  final _totalBoxesController = TextEditingController(text: '1');

  final _screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    _sliderPosition = _currentRole == UserRole.placer ? 0 : switchWidth / 2;
    _initialize();
  }

  @override
  void dispose() {
    _animationTimer?.cancel();
    _shopNameController.dispose();
    _igController.dispose();
    _facebookController.dispose();
    _missionController.dispose();
    _discountPercentController.dispose();
    _discountBahtController.dispose();
    _totalBoxesController.dispose();
    super.dispose();
  }

  void _handleRoleChange(UserRole newRole) {
    if (_currentRole != newRole) {
      setState(() {
        _roleToShowInAnimation = newRole;
      });

      _animationTimer?.cancel();
      _animationTimer = Timer(const Duration(milliseconds: 2000), () {
        if (mounted) {
          setState(() {
            _roleToShowInAnimation = null;
          });
        }
      });
    }

    setState(() {
      _currentRole = newRole;
      _sliderPosition = newRole == UserRole.placer ? 0 : switchWidth / 2;
      _animationDuration = const Duration(milliseconds: 250);
    });
  }

  Future<void> _initialize() async {
    await _determinePosition();
    await _loadCoupons();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCoupons() async {
    try {
      final coupons = await apiService.fetchCoupons();
      if (mounted) {
        setState(() => _coupons = coupons);
      }
    } catch (e) {
      _showErrorDialog("ไม่สามารถโหลดข้อมูลคูปองได้: ${e.toString()}");
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!serviceEnabled) {
      setState(() => _isLoading = false);
      _showErrorDialog('กรุณาเปิด GPS เพื่อใช้งาน');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _isLoading = false);
        _showErrorDialog('แอปต้องการสิทธิ์เข้าถึงตำแหน่ง');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _isLoading = false);
      _showErrorDialog('คุณได้ปิดกั้นสิทธิ์เข้าถึงตำแหน่งถาวร');
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _mapController.move(_currentLocation!, 18);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      _showErrorDialog('ไม่สามารถดึงตำแหน่งปัจจุบันได้: $e');
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เกิดข้อผิดพลาด'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  void _clearForm() {
    _shopNameController.clear();
    _igController.clear();
    _facebookController.clear();
    _missionController.clear();
    _discountPercentController.clear();
    _discountBahtController.clear();
    _totalBoxesController.text = '1';
  }

  void _showPlaceCouponDialog(LatLng position) {
    _clearForm();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          final isPercentFilled = _discountPercentController.text.isNotEmpty;
          final isBahtFilled = _discountBahtController.text.isNotEmpty;

          return AlertDialog(
            title: const Text('วางคูปองใหม่'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                      controller: _shopNameController,
                      decoration: const InputDecoration(labelText: 'ชื่อร้าน *')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _igController,
                      decoration:
                          const InputDecoration(labelText: 'ไอจี (ถ้ามี)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _facebookController,
                      decoration:
                          const InputDecoration(labelText: 'เฟสบุ๊ก (ถ้ามี)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _missionController,
                      decoration:
                          const InputDecoration(labelText: 'ภารกิจที่ต้องทำ *'),
                      maxLines: 3),
                  const SizedBox(height: 16),
                  Text('ส่วนลด (เลือกกรอกเพียง 1 ช่อง)',
                      style: TextStyle(
                          color: Colors.brown.shade800,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discountPercentController,
                          decoration: InputDecoration(
                              labelText: '(%)', enabled: !isBahtFilled),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => setDialogState(() {}),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text("หรือ",
                            style: TextStyle(color: Colors.grey.shade600)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _discountBahtController,
                          decoration: InputDecoration(
                              labelText: '(บาท)', enabled: !isPercentFilled),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => setDialogState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _totalBoxesController,
                      decoration: const InputDecoration(
                          labelText: 'จำนวนคูปองทั้งหมด *'),
                      keyboardType: TextInputType.number),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('ยกเลิก')),
              ElevatedButton(
                onPressed: () async {
                  if (_shopNameController.text.isEmpty ||
                      _missionController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content:
                            Text('กรุณากรอกข้อมูลที่มีเครื่องหมาย * ให้ครบถ้วน')));
                    return;
                  }
                  if (_discountPercentController.text.isEmpty &&
                      _discountBahtController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'กรุณากรอกส่วนลด (%) หรือ (บาท) อย่างใดอย่างหนึ่ง')));
                    return;
                  }

                  final couponToSend = Coupon(
                    id: '',
                    lat: position.latitude,
                    lng: position.longitude,
                    name: _shopNameController.text,
                    ig: _igController.text,
                    face: _facebookController.text,
                    mission: _missionController.text,
                    discount: _discountPercentController.text,
                    discountBaht: _discountBahtController.text,
                    totalBoxes: int.tryParse(_totalBoxesController.text) ?? 1,
                    remainingBoxes: 0,
                  );

                  try {
                    if (mounted) setState(() => _isLoading = true);
                    await apiService.placeCoupon(couponToSend);
                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('วางคูปองสำเร็จ!')));
                    }
                    await _loadCoupons();
                  } catch (e) {
                    _showErrorDialog(
                        "เกิดข้อผิดพลาดในการวางคูปอง: ${e.toString()}");
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
                child: const Text('บันทึก'),
              ),
            ],
          );
        });
      },
    );
  }

  void _showViewCouponDialog(Coupon coupon) {
    String discountText = 'ไม่มีข้อมูลส่วนลด';
    if (coupon.discount != null && coupon.discount!.isNotEmpty) {
      discountText = 'ส่วนลด ${coupon.discount}%';
    } else if (coupon.discountBaht != null && coupon.discountBaht!.isNotEmpty) {
      discountText = 'ส่วนลด ${coupon.discountBaht} บาท';
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('พบคูปอง!'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('ชื่อร้าน: ${coupon.name}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18)),
                if (coupon.ig != null && coupon.ig!.isNotEmpty)
                  Text('IG: ${coupon.ig}'),
                if (coupon.face != null && coupon.face!.isNotEmpty)
                  Text('Facebook: ${coupon.face}'),
                const Divider(height: 20),
                const Text('ภารกิจ:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(coupon.mission),
                const SizedBox(height: 10),
                const Text('รางวัล:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(discountText,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 16)),
                const Divider(height: 20),
                Text(
                    'จำนวนคงเหลือ: ${coupon.remainingBoxes} / ${coupon.totalBoxes}'),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ปิด')),
            ElevatedButton(
              onPressed: coupon.remainingBoxes > 0
                  ? () {
                      Navigator.of(context).pop();
                      _showSubmitProofDialog(coupon);
                    }
                  : null,
              child: const Text('ทำภารกิจ'),
            ),
          ],
        );
      },
    );
  }

  void _showSubmitProofDialog(Coupon coupon) {
    XFile? imageFile;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('ส่งหลักฐานภารกิจ'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('ภาพหลักฐานการทำภารกิจของคุณ:'),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final XFile? selectedImage = await ImagePicker()
                            .pickImage(source: ImageSource.gallery);
                        if (selectedImage != null) {
                          setDialogState(() => imageFile = selectedImage);
                        }
                      },
                      child: Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(8)),
                        child: imageFile == null
                            ? const Center(
                                child: Icon(Icons.add_a_photo_outlined,
                                    size: 50, color: Colors.grey))
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(File(imageFile!.path),
                                    fit: BoxFit.contain),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('กลับ'),
                ),
                ElevatedButton(
                  onPressed: imageFile == null
                      ? null
                      : () async {
                          coupon.proofImage = File(imageFile!.path);
                          coupon.discountCode =
                              'COUPON${Random().nextInt(9000) + 1000}';
                          try {
                            if (mounted) setState(() => _isLoading = true);
                            await apiService.claimCoupon(coupon.id);
                            if (mounted) {
                              setState(() {
                                coupon.remainingBoxes--;
                                if (coupon.remainingBoxes <= 0) {
                                  _coupons
                                      .removeWhere((c) => c.id == coupon.id);
                                }
                              });
                              Navigator.of(context).pop();
                              _showDiscountCodeDialog(coupon);
                            }
                          } catch (e) {
                            _showErrorDialog(
                                "เกิดข้อผิดพลาดในการเก็บคูปอง: ${e.toString()}");
                          } finally {
                            if (mounted) setState(() => _isLoading = false);
                          }
                        },
                  child: const Text('รับคูปอง'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDiscountCodeDialog(Coupon coupon) {
    String discountText = '';
    if (coupon.discount != null && coupon.discount!.isNotEmpty) {
      discountText = 'ส่วนลด ${coupon.discount}%';
    } else if (coupon.discountBaht != null && coupon.discountBaht!.isNotEmpty) {
      discountText = 'ส่วนลด ${coupon.discountBaht} บาท';
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('แคปภาพนี้แล้วส่งให้ทางร้าน',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: Screenshot(
            controller: _screenshotController,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                            color: Colors.brown.shade50,
                            border: Border.all(color: Colors.brown, width: 2),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(coupon.discountCode ?? 'N/A',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.brown,
                                letterSpacing: 1.5)),
                      ),
                    ),
                    const Divider(height: 32),
                    Text('ร้าน: ${coupon.name}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('ภารกิจที่ทำสำเร็จ: ${coupon.mission}'),
                    const SizedBox(height: 8),
                    Text('ได้รับ: $discountText',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    const Text('หลักฐานภารกิจ:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (coupon.proofImage != null)
                      Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey)),
                          child: Image.file(coupon.proofImage!,
                              fit: BoxFit.contain))
                    else
                      const Text('ไม่มีหลักฐาน'),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final Uint8List? image =
                    await _screenshotController.capture();
                if (image == null) return;

                final directory = await getApplicationDocumentsDirectory();
                final imagePath =
                    await File('${directory.path}/screenshot.png').create();
                await imagePath.writeAsBytes(image);

                await Share.shareXFiles([XFile(imagePath.path)],
                    text: 'นี่คือคูปองของฉันจากร้าน ${coupon.name}!');
              },
              child: const Text('แชร์'),
            ),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ปิด')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white.withOpacity(0.95),
        elevation: 8,
        shape: const CircularNotchedRectangle(),
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: "โหลดข้อมูลใหม่",
                icon: Icon(Icons.refresh, color: Colors.brown.shade400),
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() => _isLoading = true);
                        await _loadCoupons();
                        setState(() => _isLoading = false);
                      },
              ),
              GestureDetector(
                onHorizontalDragStart: (details) {
                  setState(() {
                    _animationDuration = Duration.zero;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _sliderPosition = (_sliderPosition + details.delta.dx)
                        .clamp(0.0, switchWidth / 2);
                  });
                },
                onHorizontalDragEnd: (details) {
                  final targetRole = (_sliderPosition < switchWidth / 4)
                      ? UserRole.placer
                      : UserRole.hunter;
                  _handleRoleChange(targetRole);
                },
                child: Container(
                  width: switchWidth,
                  height: switchHeight,
                  decoration: BoxDecoration(
                    color: Colors.brown.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _handleRoleChange(UserRole.placer),
                              behavior: HitTestBehavior.opaque,
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _handleRoleChange(UserRole.hunter),
                              behavior: HitTestBehavior.opaque,
                            ),
                          ),
                        ],
                      ),
                      AnimatedPositioned(
                        duration: _animationDuration,
                        curve: Curves.easeInOut,
                        left: _sliderPosition,
                        child: Container(
                          width: switchWidth / 2,
                          height: switchHeight,
                          decoration: BoxDecoration(
                            color: Colors.brown,
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: Center(
                            child: Text(
                              _currentRole == UserRole.placer
                                  ? 'วางคูปอง'
                                  : 'ล่าคูปอง',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'กลับไปที่ตำแหน่งปัจจุบัน',
                icon: Icon(Icons.my_location, color: Colors.brown.shade400),
                onPressed: () {
                  if (_currentLocation != null) {
                    _mapController.move(_currentLocation!, 18.0);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // เนื้อหาหลักของแอป (แผนที่)
          // ***** จุดแก้ไข 3: เพิ่ม fm. นำหน้าคลาสทั้งหมดจาก flutter_map *****
          fm.FlutterMap(
            mapController: _mapController,
            options: fm.MapOptions(
              initialCenter: const LatLng(13.7563, 100.5018),
              initialZoom: 6.0,
              onTap: (_, latlng) {
                if (_currentRole == UserRole.placer) {
                  _showPlaceCouponDialog(latlng);
                }
              },
            ),
            children: [
              fm.TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.coupon_map_v2',
              ),
              fm.MarkerLayer(
                markers: [
                  if (_currentLocation != null)
                    fm.Marker(
                      point: _currentLocation!,
                      width: 80,
                      height: 80,
                      child: Icon(Icons.person_pin_circle,
                          color: Colors.brown.shade700, size: 22.0),
                    ),
                  ..._coupons.map((coupon) => fm.Marker(
                        point: coupon.position,
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () {
                            if (_currentRole == UserRole.hunter) {
                              _showViewCouponDialog(coupon);
                            }
                          },
                          child: Tooltip(
                            message: coupon.name,
                            child: Icon(
                              Icons.monetization_on,
                              color: Colors.amber.shade700,
                              size: 18.0,
                              shadows: [
                                Shadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 4.0,
                                    offset: const Offset(0, 2))
                              ],
                            ),
                          ),
                        ),
                      )),
                ],
              ),
            ],
          ),

          // Loading Indicator
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('กำลังโหลด...',
                        style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),
          
          // Animation Overlay
          if (_roleToShowInAnimation != null)
             RoleAnimationOverlay(role: _roleToShowInAnimation!),

        ],
      ),
    );
  }
}

class RoleAnimationOverlay extends StatelessWidget {
  final UserRole role;

  const RoleAnimationOverlay({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final isHunter = role == UserRole.hunter;
    final animationPath = isHunter
        ? 'assets/animations/hunter_animation.json'
        : 'assets/animations/placer_animation.json';
    final text = isHunter ? 'นักล่าคูปอง' : 'วางคูปอง';
    final color = isHunter ? Colors.lightBlue.shade700 : Colors.orange.shade800;

    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        color: Colors.black.withOpacity(0.6),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset(
                animationPath,
                width: 250,
                height: 250,
              ),
              const SizedBox(height: 20),
              Text(
                text,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: color.withOpacity(0.8),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}