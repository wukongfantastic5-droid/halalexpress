import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'translations.dart';

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

class _TrackingMapScreenState extends State<TrackingMapScreen> {
  StreamSubscription? _riderSub;

  double _riderToShopMin = 0;
  double _shopToDropMin = 0;
  double _totalMin = 0;
  double _totalMinWithBuffer = 0;
  double _riderToShopKm = 0;
  double _shopToDropKm = 0;
  double _totalKm = 0;
  bool _loading = true;
  String? _error;
  int _routeFetchId = 0;
  String _riderName = "";
  String _shopName = "";
  String _dropName = "";
  bool _hasRider = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _riderSub?.cancel();
    super.dispose();
  }

  void _initData() {
    final d = widget.orderData;
    _riderName = (d["rider_name"] ?? "").toString();
    _shopName = (d["shop"] ?? d["shop_name"] ?? AppTranslations.get('Shop')).toString();
    _dropName = (d["drop"] ?? d["drop_name"] ?? "Destinasi").toString();
    _hasRider = _riderName.isNotEmpty;
    _fetchETA();
    if (_hasRider && widget.riderUid != null) {
      _listenRiderLocation();
    }
  }

  void _listenRiderLocation() {
    final uid = widget.riderUid;
    if (uid == null || uid.isEmpty) return;
    _riderSub = FirebaseFirestore.instance
        .collection("riders")
        .doc(uid)
        .snapshots()
        .listen((_) {
      _fetchETA();
    });
  }

  Future<void> _fetchETA() async {
    final d = widget.orderData;
    final sLat = (d["shop_lat"] ?? 0).toDouble();
    final sLng = (d["shop_lng"] ?? 0).toDouble();
    final dropLat = (d["drop_lat"] ?? 0).toDouble();
    final dropLng = (d["drop_lng"] ?? 0).toDouble();

    if (sLat == 0 || sLng == 0 || dropLat == 0 || dropLng == 0) {
      setState(() {
        _error = "Lokasi tidak lengkap";
        _loading = false;
      });
      return;
    }

    _error = null;
    final fetchId = ++_routeFetchId;

    try {
      String coords;
      if (_hasRider) {
        final uid = widget.riderUid;
        double rLat = 0, rLng = 0;
        if (uid != null) {
          try {
            final riderDoc = await FirebaseFirestore.instance
                .collection("riders")
                .doc(uid)
                .get();
            if (riderDoc.exists) {
              final loc = riderDoc["current_location"];
              if (loc is GeoPoint) {
                rLat = loc.latitude;
                rLng = loc.longitude;
              }
            }
          } catch (_) {}
        }
        if (rLat == 0 && rLng == 0) {
          coords = "$sLng,$sLat;$dropLng,$dropLat";
        } else {
          coords = "$rLng,$rLat;$sLng,$sLat;$dropLng,$dropLat";
        }
      } else {
        coords = "$sLng,$sLat;$dropLng,$dropLat";
      }

      final url = Uri.parse(
          "https://router.project-osrm.org/route/v1/driving/$coords?overview=false");
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (fetchId != _routeFetchId) return;

      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        if (body["code"] == "Ok") {
          final route = body["routes"][0];
          final legs = route["legs"] as List;
          _riderToShopMin = 0;
          _shopToDropMin = 0;
          _riderToShopKm = 0;
          _shopToDropKm = 0;

          if (_hasRider && legs.length >= 2) {
            _riderToShopKm = (legs[0]["distance"] as num) / 1000;
            _shopToDropKm = (legs[1]["distance"] as num) / 1000;
            _riderToShopMin = (legs[0]["duration"] as num) / 60;
            _shopToDropMin = (legs[1]["duration"] as num) / 60;
          } else if (legs.isNotEmpty) {
            _shopToDropKm = (legs[0]["distance"] as num) / 1000;
            _shopToDropMin = (legs[0]["duration"] as num) / 60;
          }
          _totalKm = _riderToShopKm + _shopToDropKm;
          _totalMin = _riderToShopMin + _shopToDropMin;
          _totalMinWithBuffer = _totalMin + 15;
        }
      }
    } catch (_) {}

    if (mounted && fetchId == _routeFetchId) {
      setState(() => _loading = false);
    }
  }

  String _formatMin(double min) {
    final m = min.round();
    if (m < 1) return "< 1 min";
    return "$m min";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D7377),
      appBar: AppBar(
        title: Text(
          AppTranslations.get('Estimated Time'),
          style: GoogleFonts.poppins(fontSize: 16),
        ),
        backgroundColor: const Color(0xFF0D7377),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _fetchETA,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
              ? _buildError()
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        _buildHeader(),
                        const SizedBox(height: 24),
                        _buildETACard(
                          Icons.person_pin_circle,
                          AppTranslations.get('Rider to Shop'),
                          _riderToShopMin,
                          _riderToShopKm,
                          _hasRider,
                        ),
                        const SizedBox(height: 12),
                        _buildConnector(),
                        const SizedBox(height: 12),
                        _buildETACard(
                          Icons.store,
                          AppTranslations.get('Shop to Destination'),
                          _shopToDropMin,
                          _shopToDropKm,
                          true,
                        ),
                        const SizedBox(height: 24),
                        _buildTotalCard(),
                      ],
                    ),
                  ),
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
            const Icon(Icons.timer_off_outlined, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchETA,
              icon: const Icon(Icons.refresh),
              label: const Text("Cuba Semula"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.store, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _shopName,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, color: Colors.white54, size: 16),
              ),
              Icon(Icons.location_on, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _dropName,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (_hasRider) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pedal_bike, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  _riderName,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: const Color(0xFF14C38E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildETACard(IconData icon, String label, double minutes, double km, bool show) {
    if (!show || minutes <= 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF0D7377).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF0D7377), size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatMin(minutes),
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0D7377),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.route, size: 16, color: Colors.grey.shade400),
              const SizedBox(height: 2),
              Text(
                "${km.toStringAsFixed(1)} km",
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnector() {
    return Column(
      children: List.generate(3, (i) => Container(
        width: 2,
        height: 6,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(1),
        ),
      )),
    );
  }

  Widget _buildTotalCard() {
    final showBuffer = _totalMinWithBuffer > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D7377).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            AppTranslations.get('Total Estimated Time'),
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          if (showBuffer) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _formatMin(_totalMinWithBuffer),
                  style: GoogleFonts.poppins(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "(+15 min rizab)",
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              AppTranslations.get('Calculating...'),
              style: GoogleFonts.poppins(
                fontSize: 20,
                color: Colors.white,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.route, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                const SizedBox(width: 6),
                Text(
                  "${_totalKm.toStringAsFixed(1)} km",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                if (_hasRider && _riderToShopMin > 0) ...[
                  Container(width: 1, height: 12, margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: Colors.white.withValues(alpha: 0.3)),
                  Icon(Icons.timer_outlined, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  Text(
                    "${_totalMin.round()} min tanpa rizab",
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
