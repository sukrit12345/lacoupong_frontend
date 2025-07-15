// lib/models/coupon_model.dart

import 'dart:io';
import 'package:latlong2/latlong.dart';

class Coupon {
  final String id; // ใช้เก็บ _id จาก MongoDB
  final double lat;
  final double lng;
  final String? placementDate;
  final String name;
  final String? ig;
  final String? face;
  final String mission;
  final String? discount;
  final String? discountBaht;
  final int totalBoxes;
  int remainingBoxes;

  // ส่วนนี้สำหรับ Client-side เท่านั้น ไม่มีใน DB
  File? proofImage;
  String? discountCode;

  Coupon({
    required this.id,
    required this.lat,
    required this.lng,
    this.placementDate,
    required this.name,
    this.ig,
    this.face,
    required this.mission,
    this.discount,
    this.discountBaht,
    required this.totalBoxes,
    required this.remainingBoxes,
    this.proofImage,
    this.discountCode,
  });

  // Getter เพื่อความสะดวกในการใช้กับ flutter_map
  LatLng get position => LatLng(lat, lng);

  // Factory constructor สำหรับแปลง JSON จาก Backend เป็น Object
  factory Coupon.fromJson(Map<String, dynamic> json) {
    return Coupon(
      id: json['_id'], // MongoDB ใช้ _id
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      placementDate: json['placementDate'],
      name: json['name'] ?? 'ไม่มีชื่อ',
      ig: json['ig'],
      face: json['face'],
      mission: json['mission'] ?? '',
      discount: json['discount'],
      discountBaht: json['discountBaht'],
      totalBoxes: json['totalBoxes'] ?? 1,
      remainingBoxes: json['remainingBoxes'] ?? 1,
    );
  }

  // Method สำหรับแปลง Object เป็น JSON เพื่อส่งไป Backend
  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
      'placementDate': DateTime.now().toIso8601String(),
      'name': name,
      'ig': ig,
      'face': face,
      'mission': mission,
      'discount': discount,
      'discountBaht': discountBaht,
      'totalBoxes': totalBoxes,
    };
  }
}