import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class TrackingMapScreen extends StatefulWidget {
  final String orderId;
  final Map<String, dynamic> orderData;
  final String? riderUid;

  const TrackingMapScreen({
    super.key,
    required this.orderId,
    required this.orderData,
    this.riderUid,
  });

  @override
  State<TrackingMapScreen> createState() => _TrackingMapScreenState();
}

class _TrackingMapScreenState extends State<TrackingMapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  StreamSubscription? _riderSub;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  LatLng? _riderPos;
  LatLng? _shopPos;
  LatLng? _dropPos;
  List<LatLng> _routePoints = [];
  double _riderToShopKm = 0;
  double _shopToDropKm = 0;
  double _totalKm = 0;
  bool _loading = true;
  String? _error;
  bool _initialFitDone = false;
  int _routeFetchId = 0;
  String _riderName = "";

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _initPositions();
  }

  @override
  void dispose() {
    _riderSub?.cancel();
    _pulseCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initPositions() async {
    final d = widget.orderData;
    final sLat = (d["shop_lat"] ?? 0).toDouble();
    final sLng = (d["shop_lng"] ?? 0).toDouble();
    final dLat = (d["drop_lat"] ?? 0).toDouble();
    final dLng = (d["drop_lng"] ?? 0).toDouble();

    if (sLat == 0 || sLng == 0 || dLat == 0 || dLng == 0) {
      setState(() {
        _error = "Lokasi kedai atau penghantaran tidak lengkap";
        _loading = false;
      });
      return;
    }

    _shopPos = LatLng(sLat, sLng);
    _dropPos = LatLng(dLat, dLng);
    _riderName = (d["rider_name"] ?? "").toString();

    await _fetchRiderLocation();
    if (_riderPos != null) {
      _listenRiderLocation();
    }
    await _fetchRoute();
  }

  Future<void> _fetchRiderLocation() async {
    final uid = widget.riderUid;
    if (uid == null || uid.isEmpty) return;
    try {
      final riderDoc =
          await FirebaseFirestore.instance.collection("riders").doc(uid).get();
      if (!riderDoc.exists) return;
      final loc = riderDoc["current_location"];
      if (loc is GeoPoint) {
        _riderPos = LatLng(loc.latitude, loc.longitude);
      }
    } catch (_) {}
  }

  void _listenRiderLocation() {
    final uid = widget.riderUid;
    if (uid == null || uid.isEmpty) return;
    _riderSub = FirebaseFirestore.instance
        .collection("riders")
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) return;
      final loc = snap["current_location"];
      if (loc is GeoPoint) {
        final newPos = LatLng(loc.latitude, loc.longitude);
        final moved = _riderPos == null ||
            _distanceBetween(_riderPos!, newPos) > 0.05;
        _riderPos = newPos;
        if (mounted) setState(() {});
        if (moved) _fetchRoute();
      }
    });
  }

  double _distanceBetween(LatLng a, LatLng b) {
    final c = a.latitudeInRad;
    final d = b.latitudeInRad;
    final e = (a.longitudeInRad - b.longitudeInRad).abs();
    return 12742 * asin(sqrt(0.5 - cos(d - c) / 2 + cos(c) * cos(d) * (1 - cos(e)) / 2));
  }

  Future<void> _fetchRoute() async {
    if (_shopPos == null || _dropPos == null) return;
    _error = null;
    final fetchId = ++_routeFetchId;

    try {
      final hasRider = _riderPos != null;
      final coords = hasRider
          ? "${_riderPos!.longitude},${_riderPos!.latitude};${_shopPos!.longitude},${_shopPos!.latitude};${_dropPos!.longitude},${_dropPos!.latitude}"
          : "${_shopPos!.longitude},${_shopPos!.latitude};${_dropPos!.longitude},${_dropPos!.latitude}";

      final url = Uri.parse(
          "https://router.project-osrm.org/route/v1/driving/$coords?overview=simplified&geometries=geojson");

      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (fetchId != _routeFetchId) return;

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body["code"] == "Ok") {
          final route = body["routes"][0];
          final rawCoords = route["geometry"]["coordinates"] as List;
          _routePoints =
              rawCoords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
          final legs = route["legs"] as List;
          _riderToShopKm = 0;
          _shopToDropKm = 0;
          if (hasRider && legs.length >= 2) {
            _riderToShopKm = (legs[0]["distance"] as num) / 1000;
            _shopToDropKm = (legs[1]["distance"] as num) / 1000;
          } else if (!hasRider && legs.isNotEmpty) {
            _shopToDropKm = (legs[0]["distance"] as num) / 1000;
          }
          _totalKm = _riderToShopKm + _shopToDropKm;
        }
      }
    } catch (e) {
      debugPrint("OSRM error: $e");
    }

    if (mounted && fetchId == _routeFetchId) {
      setState(() => _loading = false);
      if (!_initialFitDone) {
        _initialFitDone = true;
        _fitBounds();
      }
    }
  }

  void _fitBounds() {
    final pts = <LatLng>[];
    if (_riderPos != null) pts.add(_riderPos!);
    if (_shopPos != null) pts.add(_shopPos!);
    if (_dropPos != null) pts.add(_dropPos!);
    for (final p in _routePoints) {
      pts.add(p);
    }
    if (pts.length < 2) return;
    double minLat = pts[0].latitude, maxLat = pts[0].latitude;
    double minLng = pts[0].longitude, maxLng = pts[0].longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng)),
        padding: const EdgeInsets.all(60),
      ));
    });
  }

  LatLng _midpoint(LatLng a, LatLng b) =>
      LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D7377),
      appBar: AppBar(
        title: Text(
          _riderName.isNotEmpty ? "Laluan $_riderName" : "Laluan",
          style: GoogleFonts.poppins(fontSize: 16),
        ),
        backgroundColor: const Color(0xFF0D7377),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchRoute,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    Expanded(child: _buildMap()),
                    _buildBottomPanel(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchRoute,
              icon: const Icon(Icons.refresh),
              label: const Text("Cuba Semula"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    if (_routePoints.isEmpty && _shopPos == null) {
      return const SizedBox.shrink();
    }

    final markers = <Marker>[];

    // Rider marker — motorcycle icon with pulse ring
    if (_riderPos != null) {
      markers.add(Marker(
        point: _riderPos!,
        width: 80,
        height: 80,
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: 1.0 + (1.0 - _pulseAnim.value) * 0.6,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0D7377).withOpacity(0.15 * _pulseAnim.value),
                    ),
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0D7377),
                    boxShadow: [
                      BoxShadow(color: Colors.black26, blurRadius: 6),
                    ],
                  ),
                  child: const Icon(
                    Icons.two_wheeler,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            );
          },
        ),
      ));
    }

    // Shop marker
    if (_shopPos != null) {
      markers.add(_buildPinMarker(
        _shopPos!, "Kedai", const Color(0xFF0D7377), Icons.store, false,
      ));
    }

    // Drop marker
    if (_dropPos != null) {
      markers.add(_buildPinMarker(
        _dropPos!, "Hantar", Colors.red, Icons.location_on, true,
      ));
    }

    // Distance labels
    if (_riderPos != null && _shopPos != null && _riderToShopKm > 0) {
      markers.add(_distanceLabel(_midpoint(_riderPos!, _shopPos!), _riderToShopKm));
    }
    if (_shopPos != null && _dropPos != null && _shopToDropKm > 0) {
      markers.add(_distanceLabel(_midpoint(_shopPos!, _dropPos!), _shopToDropKm));
    }

    // Route line with glow
    final polylines = <Polyline>[];
    if (_routePoints.isNotEmpty) {
      polylines.add(Polyline(
        points: _routePoints,
        color: const Color(0xFF14C38E).withOpacity(0.2),
        strokeWidth: 9,
      ));
      polylines.add(Polyline(
        points: _routePoints,
        color: const Color(0xFF14C38E),
        strokeWidth: 4,
      ));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _shopPos ?? const LatLng(3.139, 101.6869),
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.example.kampungrider',
        ),
        PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Marker _buildPinMarker(LatLng point, String label, Color color, IconData icon, bool isDrop) {
    return Marker(
      point: point,
      width: 90,
      height: 90,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6)],
            ),
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          if (isDrop)
            // Drop pin like Google Maps
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(36, 36),
                    painter: _PinPainter(color),
                  ),
                  Icon(icon, color: Colors.white, size: 16),
                ],
              ),
            )
          else
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.4), blurRadius: 8),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
        ],
      ),
    );
  }

  Marker _distanceLabel(LatLng point, double km) {
    return Marker(
      point: point,
      width: 70,
      height: 26,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF0D7377),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 6),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_car, size: 11, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              "${km.toStringAsFixed(1)} km",
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    if (_loading) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF0D7377),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_riderPos != null)
              _statItem(Icons.person_pin_circle, "Rider \u2192 Kedai", _riderToShopKm),
            if (_riderPos != null) const SizedBox(width: 10),
            _statItem(Icons.store, "Kedai \u2192 Hantar", _shopToDropKm),
            if (_riderPos != null) ...[
              const SizedBox(width: 10),
              _statItem(Icons.route, "Jumlah", _totalKm),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statItem(IconData icon, String label, double km) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(height: 2),
            Text(
              "${km.toStringAsFixed(1)} km",
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 7,
                color: Colors.white.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  final Color color;
  _PinPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(size.width * 0.1, size.height * 0.35)
      ..quadraticBezierTo(size.width / 2, -size.height * 0.1, size.width * 0.9, size.height * 0.35)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
