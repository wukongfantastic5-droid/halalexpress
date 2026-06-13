import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'notification_service.dart';
import 'tracking_map_screen.dart';
import 'widgets/order_timeline.dart';

String formatItems(dynamic items) {
  if (items is List && items.isNotEmpty) {
    final parts = items.map((item) {
      final name = (item["name"] ?? "").toString().trim();
      final qty = (item["qty"] ?? 1) as int;
      if (name.isEmpty) return "";
      return qty > 1 ? "$name ×$qty" : name;
    }).where((s) => s.isNotEmpty);
    return parts.join(", ");
  }
  return items?.toString() ?? "-";
}

String _statusLabel(String? status) {
  switch (status) {
    case "pending":
      return "Menunggu";
    case "accepted":
      return "Dijemput";
    case "on the way":
      return "Dalam Perjalanan";
    case "delivered":
      return "Selesai";
    default:
      return status ?? "";
  }
}

class OrderScreen extends StatefulWidget {
  final GlobalKey? formCardKey;
  final GlobalKey? locationRowKey;
  final GlobalKey? submitBtnKey;

  const OrderScreen({
    super.key,
    this.formCardKey,
    this.locationRowKey,
    this.submitBtnKey,
  });

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> with TickerProviderStateMixin {

  final List<Map<String, dynamic>> _items = [{"name": "", "qty": 1}];
  final List<TextEditingController> _itemControllers = [];
  final shopName = TextEditingController();
  final details = TextEditingController();
  final drop = TextEditingController();

  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  final AudioPlayer player = AudioPlayer();

  double? shopLat;
  double? shopLng;
  double? dropLat;
  double? dropLng;

  double? calculatedDistance;
  double? calculatedFare;

  bool loading = false;
  bool locating = false;
  bool calculating = false;
  String? fareError;
  bool agreedToFare = false;
  Timer? _shopDebounce;
  Timer? _dropDebounce;
  final Set<String> _acceptedPlayed = {};
  final Set<String> _deliveredPlayed = {};

  List<bool> _debugPresets = [false, false, false];
  static const _presets = [
    {
      "shop": "Petronas Taman Amaniah",
      "items": [{"name": "Nasi", "qty": 1}],
      "details": "Letak di guard",
      "drop": "Jalan 1/4 Taman Amaniah",
    },
    {
      "shop": "Masjid Taman Amaniah",
      "items": [{"name": "Roti", "qty": 2}],
      "details": "Blok A31",
      "drop": "Jalan 1/2 Taman Amaniah",
    },
    {
      "shop": "7-Eleven Taman Amaniah",
      "items": [{"name": "Air minum", "qty": 3}],
      "details": "Depan pagar",
      "drop": "Jalan 1/6 Taman Amaniah",
    },
  ];



  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
    _syncControllers();
    shopName.addListener(() => _onShopNameChanged(shopName.text));
    drop.addListener(_onDropTextChanged);
  }

  void _syncControllers() {
    while (_itemControllers.length < _items.length) {
      _itemControllers.add(TextEditingController());
    }
    while (_itemControllers.length > _items.length) {
      _itemControllers.removeLast().dispose();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    for (var c in _itemControllers) {
      c.dispose();
    }
    shopName.dispose();
    details.dispose();
    drop.dispose();
    player.dispose();
    _shopDebounce?.cancel();
    _dropDebounce?.cancel();
    super.dispose();
  }

  void showLocationLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  "Mencari lokasi anda...",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D7377),
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Sila tunggu sementara kami mengesan lokasi GPS anda.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> pinLocation() async {
    setState(() { locating = true; });
    showLocationLoading();

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        setState(() { locating = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sila hidupkan GPS"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      dropLat = pos.latitude;
      dropLng = pos.longitude;
      drop.text = "${pos.latitude},${pos.longitude}";

      print("📍 Lokasi Penghantaran Dikenalpasti");
      print("Latitude: ${pos.latitude}");
      print("Longitude: ${pos.longitude}");

      if (Navigator.canPop(context)) Navigator.pop(context);

      setState(() { locating = false; });
      _calculateFare();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Lokasi penghantaran dikenalpasti\nLat: ${pos.latitude}\nLng: ${pos.longitude}",
          ),
          backgroundColor: Colors.green,
        ),
      );

    } catch (e) {
      print("Gagal mendapatkan lokasi");
      print(e);

      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() { locating = false; });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Gagal mendapatkan lokasi"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onShopNameChanged(String value) {
    _shopDebounce?.cancel();
    if (value.trim().length < 3) {
      setState(() { shopLat = null; shopLng = null; });
      _calculateFare();
      return;
    }
    _shopDebounce = Timer(const Duration(milliseconds: 800), () => _searchShopLocation(value.trim()));
  }

  Future<void> _searchShopLocation(String query) async {
    setState(() => calculating = true);
    try {
      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1&countrycodes=my",
      );
      final res = await http.get(url, headers: {"User-Agent": "BunnyFresh/1.0"}).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception("Nominatim ${res.statusCode}");
      final data = jsonDecode(res.body) as List;
      if (data.isEmpty) {
        setState(() { shopLat = null; shopLng = null; calculating = false; fareError = "Kedai tidak dijumpai, cuba nama lain"; });
        return;
      }
      shopLat = double.tryParse(data[0]["lat"] ?? "");
      shopLng = double.tryParse(data[0]["lon"] ?? "");
      if (shopLat == null || shopLng == null) {
        setState(() { calculating = false; fareError = "Gagal dapat koordinat kedai"; });
        return;
      }
      setState(() { fareError = null; calculating = false; });
      // Only calculate fare if delivery location is already set
      if (dropLat != null && dropLng != null) _calculateFare();
    } catch (e) {
      debugPrint("NOMINATIM ERROR: $e");
      setState(() { shopLat = null; shopLng = null; calculating = false; fareError = "Ralat carian: ${e.toString().substring(0, 80)}"; });
    }
  }

  void _onDropTextChanged() {
    _dropDebounce?.cancel();
    final value = drop.text.trim();
    if (value.length < 3) {
      setState(() { dropLat = null; dropLng = null; });
      _calculateFare();
      return;
    }
    if (RegExp(r'^-?\d+\.\d+,-?\d+\.\d+$').hasMatch(value)) {
      return;
    }
    _dropDebounce = Timer(const Duration(milliseconds: 800), () => _searchDropLocation(value));
  }

  Future<void> _searchDropLocation(String query) async {
    setState(() => calculating = true);
    try {
      final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1&countrycodes=my",
      );
      final res = await http.get(url, headers: {"User-Agent": "BunnyFresh/1.0"}).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception("Nominatim ${res.statusCode}");
      final data = jsonDecode(res.body) as List;
      if (data.isEmpty) {
        setState(() { dropLat = null; dropLng = null; calculating = false; fareError = "Lokasi tidak dijumpai, cuba nama lain"; });
        return;
      }
      dropLat = double.tryParse(data[0]["lat"] ?? "");
      dropLng = double.tryParse(data[0]["lon"] ?? "");
      if (dropLat == null || dropLng == null) {
        setState(() { calculating = false; fareError = "Gagal dapat koordinat lokasi"; });
        return;
      }
      setState(() { fareError = null; calculating = false; });
      if (shopLat != null && shopLng != null) _calculateFare();
    } catch (e) {
      debugPrint("DROP NOMINATIM ERROR: $e");
      setState(() { dropLat = null; dropLng = null; calculating = false; fareError = "Ralat carian: ${e.toString().substring(0, 80)}"; });
    }
  }

  Future<void> _calculateFare() async {
    if (shopLat == null || shopLng == null ||
        dropLat == null || dropLng == null) {
      setState(() { calculatedDistance = null; calculatedFare = null; agreedToFare = false; fareError = null; calculating = false; });
      return;
    }

    setState(() => calculating = true);

    try {
      final url = Uri.parse(
        "https://router.project-osrm.org/route/v1/driving/"
        "$shopLng,$shopLat;$dropLng,$dropLat?overview=false",
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception("OSRM returned ${res.statusCode}");

      final json = jsonDecode(res.body);
      final km = (json["routes"][0]["distance"] as num) / 1000;

      // Fare formula: base RM4 + RM1.50/km, minimum RM7
      final fare = (4.0 + km * 1.5).clamp(7.0, double.infinity);

      setState(() {
        calculatedDistance = (km * 1000).roundToDouble();
        calculatedFare = double.parse(fare.toStringAsFixed(2));
        calculating = false;
      });
    } catch (e) {
      debugPrint("OSRM ERROR: $e");
      setState(() {
        calculatedDistance = null;
        calculatedFare = null;
        calculating = false;
        fareError = "Gagal kira tambang: ${e.toString().substring(0, 80)}";
      });
    }
  }

  Future<void> _submitDebugOrders() async {
    final checked = <int>[];
    for (int i = 0; i < _presets.length; i++) {
      if (_debugPresets[i]) checked.add(i);
    }
    if (checked.isEmpty) return;

    setState(() => loading = true);
    final user = auth.currentUser;
    if (user == null) { setState(() => loading = false); return; }

    final userDoc = await firestore.collection("users").doc(user.uid).get();
    final whatsapp = userDoc["whatsapp"] ?? "";

    for (final i in checked) {
      final preset = _presets[i];
      double? sLat, sLng, dLat, dLng;
      double? fare;

      try {
        final shopUrl = Uri.parse("https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(preset["shop"].toString())}&format=json&limit=1&countrycodes=my");
        final shopRes = await http.get(shopUrl, headers: {"User-Agent": "BunnyFresh/1.0"}).timeout(const Duration(seconds: 10));
        if (shopRes.statusCode == 200) {
          final sd = jsonDecode(shopRes.body) as List;
          if (sd.isNotEmpty) { sLat = double.tryParse(sd[0]["lat"] ?? ""); sLng = double.tryParse(sd[0]["lon"] ?? ""); }
        }
      } catch (_) {}

      try {
        final dropUrl = Uri.parse("https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(preset["drop"].toString())}&format=json&limit=1&countrycodes=my");
        final dropRes = await http.get(dropUrl, headers: {"User-Agent": "BunnyFresh/1.0"}).timeout(const Duration(seconds: 10));
        if (dropRes.statusCode == 200) {
          final dd = jsonDecode(dropRes.body) as List;
          if (dd.isNotEmpty) { dLat = double.tryParse(dd[0]["lat"] ?? ""); dLng = double.tryParse(dd[0]["lon"] ?? ""); }
        }
      } catch (_) {}

      if (sLat != null && sLng != null && dLat != null && dLng != null) {
        try {
          final osrmUrl = Uri.parse("https://router.project-osrm.org/route/v1/driving/$sLng,$sLat;$dLng,$dLat?overview=false");
          final osrmRes = await http.get(osrmUrl).timeout(const Duration(seconds: 10));
          if (osrmRes.statusCode == 200) {
            final oj = jsonDecode(osrmRes.body);
            final km = (oj["routes"][0]["distance"] as num) / 1000;
            fare = (4.0 + km * 1.5).clamp(7.0, double.infinity);
          }
        } catch (_) {}
      }

      await firestore.collection("orders").add({
        "user_uid": user.uid,
        "user_email": user.email,
        "whatsapp": whatsapp,
        "items": preset["items"],
        "grocery": formatItems(preset["items"] as List),
        "shop_name": preset["shop"],
        "details": preset["details"],
        "shop_lat": sLat,
        "shop_lng": sLng,
        "drop": preset["drop"],
        "drop_lat": dLat,
        "drop_lng": dLng,
        "fare": fare ?? 0,
        "distance_km": "0",
        "status": "pending",
        "rider": "",
        "created_at": Timestamp.now(),
      });
    }

    setState(() { loading = false; _debugPresets = [false, false, false]; });

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: const Color(0xFF0D7377),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(Icons.check_circle, color: Colors.amber, size: 28),
            SizedBox(width: 10),
            Text("Selesai", style: GoogleFonts.poppins(color: Colors.white)),
          ]),
          content: Text("${checked.length} pesanan debug telah dihantar.",
            style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.8)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text("OK", style: GoogleFonts.poppins(color: Colors.amber))),
          ],
        ),
      );
    }
  }

  void submitOrder() async {
    if (drop.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Sila isi alamat penghataran"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final user = auth.currentUser;
      final userDoc = await firestore
          .collection("users")
          .doc(user!.uid)
          .get();

      String whatsapp = userDoc["whatsapp"] ?? "";

      final validItems = _items
          .map((item) => {
                "name": (item["name"] as String).trim(),
                "qty": item["qty"] as int,
              })
          .where((item) => (item["name"] as String).isNotEmpty)
          .toList();

      if (validItems.isEmpty) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sila tambah sekurang-kurangnya satu barang"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await firestore.collection("orders").add({
        "user_uid": user.uid,
        "user_email": user.email,
        "whatsapp": whatsapp,
        "items": validItems,
        "grocery": formatItems(validItems),
        "shop_name": shopName.text.trim(),
        "details": details.text.trim(),
        "shop_lat": shopLat,
        "shop_lng": shopLng,
        "drop": drop.text,
        "drop_lat": dropLat,
        "drop_lng": dropLng,
        "fare": calculatedFare ?? 0,
        "distance_km": calculatedDistance != null ? (calculatedDistance! / 1000).toStringAsFixed(2) : "0",
        "status": "pending",
        "rider": "",
        "created_at": Timestamp.now(),
      });

      await player.play(
        AssetSource('audio/order_received.mp3'),
      );

      _items.clear();
      _items.add({"name": "", "qty": 1});
      shopName.clear();
      details.clear();
      drop.clear();
      setState(() {
        loading = false;
        shopLat = null;
        shopLng = null;
        dropLat = null;
        dropLng = null;
        calculatedDistance = null;
        calculatedFare = null;
      });

      showDialog(
        context: context,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 30,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: Colors.white,
                      size: 55,
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    "Order Submitted",
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0D7377),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    "Barangan anda telah dihantar",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xFF0D7377).withOpacity(0.3),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Center(
                              child: Text(
                                "Done",
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

    } catch (e) {
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Gagal untuk membuat tempahan"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      margin: EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0D7377).withOpacity(0.08),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon != null ? Icon(icon, color: Color(0xFF0D7377)) : null,
          labelStyle: GoogleFonts.poppins(color: Color(0xFF0D7377).withOpacity(0.7)),
          hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Color(0xFF14C38E), width: 2),
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.85),
          contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editOrder(BuildContext context, String docId, Map<String, dynamic> data) async {
    final itemsData = (data["items"] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final editItems = itemsData.isNotEmpty
        ? itemsData.map((e) => Map<String, dynamic>.from(e)).toList()
        : [{"name": data["grocery"] ?? "", "qty": 1}];
    final shopCtrl = TextEditingController(text: data["shop_name"] ?? "");
    final detailsCtrl = TextEditingController(text: data["details"] ?? "");

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Edit Pesanan", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(editItems.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: TextEditingController(text: editItems[i]["name"] ?? ""),
                            decoration: InputDecoration(
                              labelText: "Barang #${i + 1}",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                            ),
                            onChanged: (v) => editItems[i]["name"] = v,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            controller: TextEditingController(text: "${editItems[i]["qty"] ?? 1}"),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: "Qty",
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              isDense: true,
                            ),
                            onChanged: (v) => editItems[i]["qty"] = int.tryParse(v) ?? 1,
                          ),
                        ),
                        if (editItems.length > 1)
                          IconButton(
                            icon: Icon(Icons.remove_circle, color: Colors.red.shade400, size: 20),
                            onPressed: () {
                              editItems.removeAt(i);
                              setDialogState(() {});
                            },
                          ),
                      ],
                    ),
                  );
                }),
                TextButton.icon(
                  onPressed: () {
                    editItems.add({"name": "", "qty": 1});
                    setDialogState(() {});
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text("Tambah Barang"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: shopCtrl,
                  decoration: InputDecoration(
                    labelText: "Nama Kedai",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detailsCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: "Butiran",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text("Batal", style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text("Simpan", style: GoogleFonts.poppins(color: const Color(0xFF0D7377))),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      final validItems = editItems
          .map((item) => {
                "name": (item["name"] as String).trim(),
                "qty": item["qty"] as int,
              })
          .where((item) => (item["name"] as String).isNotEmpty)
          .toList();

      await firestore.collection("orders").doc(docId).update({
        "items": validItems,
        "grocery": formatItems(validItems),
        "shop_name": shopCtrl.text.trim(),
        "details": detailsCtrl.text.trim(),
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Pesanan dikemas kini"),
          backgroundColor: const Color(0xFF14C38E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      debugPrint("EDIT ORDER ERROR: $e");
    }
  }

  Future<void> _cancelOrder(BuildContext context, String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Batal Pesanan", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text("Adakah anda pasti mahu membatalkan pesanan ini?", style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Tidak", style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text("Ya, Batalkan", style: GoogleFonts.poppins(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await firestore.collection("orders").doc(docId).delete();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Pesanan dibatalkan"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      debugPrint("CANCEL ORDER ERROR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D7377),
            Color(0xFF14C38E),
            Color(0xFF1A237E).withOpacity(0.2),
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            "Pesanan Pelanggan",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(height: 10),
                Container(
                  key: widget.formCardKey,
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.25),
                        Colors.white.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 30,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 20),
                          ),
                          SizedBox(width: 10),
                          Text(
                            "Butiran Pesanan",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      ..._items.asMap().entries.map((entry) {
                        final i = entry.key;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D7377).withOpacity(0.3),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    "${i + 1}",
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _itemControllers[i],
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: const Color(0xFF0D7377),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: "Nama barang",
                                    hintStyle: GoogleFonts.poppins(
                                      color: const Color(0xFF0D7377).withOpacity(0.35),
                                      fontSize: 13,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.85),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  onChanged: (v) => _items[i]["name"] = v,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  controller: TextEditingController(text: "${_items[i]["qty"]}"),
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: const Color(0xFF0D7377),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: "Qty",
                                    hintStyle: GoogleFonts.poppins(
                                      color: const Color(0xFF0D7377).withOpacity(0.35),
                                      fontSize: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 12,
                                    ),
                                  ),
                                  onChanged: (v) {
                                    _items[i]["qty"] = int.tryParse(v) ?? 1;
                                  },
                                ),
                              ),
                              if (_items.length > 1)
                                IconButton(
                                  icon: Icon(Icons.close, color: Colors.red.shade300, size: 18),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: () {
                                    setState(() {
                                      _items.removeAt(i);
                                      _itemControllers.removeAt(i).dispose();
                                    });
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: const Color(0xFF0D7377).withOpacity(0.4)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              setState(() {
                                _items.add({"name": "", "qty": 1});
                                _itemControllers.add(TextEditingController());
                              });
                            },
                            icon: Icon(Icons.add, color: const Color(0xFF0D7377), size: 20),
                            label: Text(
                              "Tambah Barang",
                              style: GoogleFonts.poppins(
                                color: const Color(0xFF0D7377),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _buildField(
                        controller: shopName,
                        label: "Nama Kedai",
                        hint: "Contoh: NSK Selayang / 7-Eleven",
                        icon: Icons.store_outlined,
                      ),
                      _buildField(
                        controller: details,
                        label: "Butiran tambahan",
                        hint: "Contoh: Tinggalkan di pondok pengawal",
                        icon: Icons.notes_rounded,
                        maxLines: 4,
                      ),
                      SizedBox(height: 14),
                      Text(
                        "Lokasi Penghantaran",
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        key: widget.locationRowKey,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0xFF0D7377).withOpacity(0.08),
                                    blurRadius: 12,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: drop,
                                decoration: InputDecoration(
                                  hintText: "Cari lokasi penghantaran",
                                  hintStyle: GoogleFonts.poppins(
                                    color: Colors.grey.shade400,
                                    fontSize: 13,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: const Color(0xFF0D7377),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: locating
                                      ? [Colors.grey, Colors.grey.shade400]
                                      : [Color(0xFF14C38E), Color(0xFF0D7377)],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0xFF0D7377).withOpacity(0.3),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: locating ? null : pinLocation,
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    width: 56,
                                    height: 56,
                                    child: Center(
                                      child: locating
                                          ? SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2.5,
                                              ),
                                            )
                                          : Icon(
                                              Icons.pin_drop,
                                              color: Colors.white,
                                              size: 28,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      ..._presets.asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        return CheckboxListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          checkColor: const Color(0xFF0D7377),
                          activeColor: Colors.amber,
                          value: _debugPresets[i],
                          onChanged: (v) {
                            setState(() => _debugPresets[i] = v ?? false);
                            if (v == true) {
                              _items.clear();
                              for (var item in (p["items"] as List)) {
                                _items.add({"name": item["name"], "qty": item["qty"] as int});
                              }
                              _syncControllers();
                              _itemControllers.asMap().forEach((idx, c) {
                                if (idx < _items.length) c.text = _items[idx]["name"] as String;
                              });
                              shopName.text = p["shop"].toString();
                              details.text = p["details"].toString();
                              drop.text = p["drop"].toString();
                            }
                          },
                          title: Text(
                            "${p["shop"]} — ${(p["items"] as List).map((e) => e["name"]).join(", ")}",
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                          ),
                          subtitle: Text(
                            "Ke: ${p["drop"]}",
                            style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withOpacity(0.5)),
                          ),
                        );
                      }),
                      if (calculating)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text("Mengira tambang...",
                                style: GoogleFonts.poppins(
                                  fontSize: 12, color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (fareError != null)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.red.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, size: 18, color: Colors.red.shade300),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(fareError!,
                                  style: GoogleFonts.poppins(
                                    fontSize: 12, color: Colors.red.shade200,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (calculatedFare != null && !calculating)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCD34D).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFCD34D).withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.receipt_long, size: 18, color: const Color(0xFFFCD34D)),
                              SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  "Anggaran Tambang: ",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ),
                              Text(
                                "RM ${calculatedFare!.toStringAsFixed(2)}",
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFFCD34D),
                                ),
                              ),
                              if (calculatedDistance != null) ...[
                                Spacer(),
                                Text(
                                  "${(calculatedDistance! / 1000).toStringAsFixed(1)} km",
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ),
                    ],
                  ),
                ),
                if (calculatedFare != null && !calculating)
                  GestureDetector(
                    onTap: () => setState(() => agreedToFare = !agreedToFare),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            agreedToFare ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 22,
                            color: agreedToFare ? Colors.red : Colors.white.withOpacity(0.7),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Saya bersetuju dengan tambang RM ${calculatedFare!.toStringAsFixed(2)}",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: agreedToFare ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SizedBox(height: 16),
                AnimatedContainer(
                  key: widget.submitBtnKey,
                  duration: Duration(milliseconds: 200),
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: (loading || calculatedFare == null || !agreedToFare)
                          ? [Colors.grey, Colors.grey.shade400]
                          : [Color(0xFF14C38E), Color(0xFF0D7377)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF0D7377).withOpacity(0.4),
                        blurRadius: 15,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _debugPresets.any((v) => v)
                          ? _submitDebugOrders
                          : (loading || calculatedFare == null || !agreedToFare) ? null : submitOrder,
                      borderRadius: BorderRadius.circular(18),
                      child: Center(
                        child: loading
                            ? CircularProgressIndicator(color: Colors.white)
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    "Hantar Pesanan",
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.inbox_rounded, color: Colors.white, size: 18),
                    ),
                    SizedBox(width: 10),
                    Text(
                      "Pesanan Aktif",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: firestore
                      .collection("orders")
                      .where("user_uid", isEqualTo: user!.uid)
                      .orderBy("created_at", descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: Text(
                            "Firestore Error",
                            style: GoogleFonts.poppins(color: Colors.red.shade300),
                          ),
                        ),
                      );
                    }

                    if (!snapshot.hasData) {
                      return Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    }

                    final allOrders = snapshot.data!.docs;

                    for (final doc in allOrders) {
                      final d = doc.data() as Map<String, dynamic>;
                      if (d["status"] == "accepted" &&
                          _acceptedPlayed.add(doc.id)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          player.play(AssetSource('audio/job_accept.mp3'));
                        });
                        NotificationService.showOrderNotification(
                          title: "Pesanan Diterima",
                          body: "Rider akan mengambil barang anda",
                          orderId: doc.id,
                        );
                      }
                      if (d["status"] == "delivered" &&
                          _deliveredPlayed.add(doc.id)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          player.play(AssetSource('audio/delivered.mp3'));
                        });
                        NotificationService.showOrderNotification(
                          title: "Pesanan Selesai",
                          body: "Barang telah sampai. Jangan lupa nilai rider!",
                          orderId: doc.id,
                        );
                      }
                    }

                    final orders = allOrders.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return data["status"] != "delivered";
                    }).toList();

                    if (orders.isEmpty) {
                      return Container(
                        padding: EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.15),
                              Colors.white.withOpacity(0.05),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 48,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            SizedBox(height: 12),
                            Text(
                              "No active orders",
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: orders.length,
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemBuilder: (context, index) {
                        final doc = orders[index];
                        final data = doc.data() as Map<String, dynamic>;

                        Color statusColor;
                        IconData statusIcon;
                        switch (data["status"]) {
                          case "pending":
                            statusColor = Colors.amber.shade700;
                            statusIcon = Icons.hourglass_empty;
                            break;
                          case "accepted":
                            statusColor = Colors.orange;
                            statusIcon = Icons.assignment_turned_in;
                            break;
                          case "on the way":
                            statusColor = const Color(0xFF14C38E);
                            statusIcon = Icons.delivery_dining;
                            break;
                          default:
                            statusColor = Colors.amber.shade700;
                            statusIcon = Icons.schedule;
                        }

                        return AnimatedContainer(
                          duration: Duration(milliseconds: 400),
                          margin: EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.25),
                                Colors.white.withOpacity(0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.25),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 15,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        Icons.shopping_bag_outlined,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        formatItems(data["items"] ?? data["grocery"] ?? ""),
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: statusColor.withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(statusIcon, size: 14, color: statusColor),
                                          SizedBox(width: 4),
                                          Text(
                                            _statusLabel(data["status"]),
                                            style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600,
                                              color: statusColor,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                Divider(color: Colors.white.withOpacity(0.15), height: 1),
                                SizedBox(height: 10),
                                Row(
                                  children: [
                                    Icon(Icons.store_outlined, size: 14, color: Colors.white.withOpacity(0.7)),
                                    SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        "Kedai: ${data["shop_name"] ?? ""}",
                                        style: GoogleFonts.poppins(
                                          color: Colors.white.withOpacity(0.85),
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 6),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.location_on_outlined, size: 14, color: Colors.white.withOpacity(0.7)),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        "Lokasi: ${data["drop"] ?? ""}",
                                        style: GoogleFonts.poppins(
                                          color: Colors.white.withOpacity(0.85),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if ((data["details"] ?? "").isNotEmpty) ...[
                                  SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.notes_rounded, size: 14, color: Colors.white.withOpacity(0.7)),
                                      SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          "Butiran: ${data["details"]}",
                                          style: GoogleFonts.poppins(
                                            color: Colors.white.withOpacity(0.85),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF0D7377).withOpacity(0.25),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.monetization_on, color: Colors.white, size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              "Tambang",
                                              style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                color: Colors.white.withOpacity(0.8),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            Text(
                                              "RM ${double.tryParse((data["fare"] ?? data["total"] ?? "0").toString())?.toStringAsFixed(2) ?? "0.00"}",
                                              style: GoogleFonts.poppins(
                                                fontSize: 20,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if ((data["distance_km"] ?? "").toString() != "0" &&
                                          (data["distance_km"] ?? "").toString().isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.straighten, size: 12, color: Colors.white.withOpacity(0.8)),
                                              const SizedBox(width: 3),
                                              Text(
                                                "${data["distance_km"]} km",
                                                style: GoogleFonts.poppins(
                                                  fontSize: 12,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (data["status"] == "on the way" ||
                                    data["status"] == "delivered") ...[
                                  SizedBox(height: 12),
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.12),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Pembayaran",
                                          style: GoogleFonts.poppins(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withOpacity(0.85),
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        if (data["payment_screenshot"] != null &&
                                            data["payment_screenshot"].toString().isNotEmpty) ...[
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              data["payment_screenshot"],
                                              height: 80,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                height: 80,
                                                color: Colors.white.withOpacity(0.1),
                                                child: Icon(Icons.broken_image,
                                                    color: Colors.white.withOpacity(0.5)),
                                              ),
                                            ),
                                          ),
                                          SizedBox(height: 6),
                                        ],
                                        if (data["payment_status"] == "paid")
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(
                                                color: Colors.green.withOpacity(0.4),
                                              ),
                                            ),
                                            child: Text(
                                              "LUNAS",
                                              style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.greenAccent,
                                              ),
                                            ),
                                          )
                                        else ...[
                                          Text(
                                            "Sila upload bukti bayaran (QR receipt)",
                                            style: GoogleFonts.poppins(
                                              fontSize: 11,
                                              color: Colors.white.withOpacity(0.7),
                                            ),
                                          ),
                                          SizedBox(height: 6),
                                          _actionButton(
                                            icon: Icons.upload_file,
                                            label: "Upload",
                                            color: const Color(0xFF14C38E),
                                            onTap: () =>
                                                _uploadPaymentProof(context, doc.id),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                                if ((data["rider_name"] ?? "").isNotEmpty &&
                                    data["status"] != "pending") ...[
                                  SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.motorcycle, size: 14, color: Colors.white.withOpacity(0.7)),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          "Rider: ${data["rider_name"]}",
                                          style: GoogleFonts.poppins(
                                            color: const Color(0xFFFCD34D),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                if ((data["rider_name"] ?? "").isNotEmpty &&
                                    data["status"] != "pending" &&
                                    data["status"] != "delivered") ...[
                                  SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _actionButton(
                                          icon: Icons.map,
                                          label: "Lihat Laluan",
                                          color: const Color(0xFF0D7377),
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TrackingMapScreen(
                                                orderId: doc.id,
                                                orderData: data,
                                                riderUid: data["rider_uid"],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                SizedBox(height: 12),
                                OrderTimeline(currentStatus: data["status"] ?? "pending"),
                                if (data["status"] == "delivered") ...[
                                  SizedBox(height: 12),
                                  _buildRatingSection(context, doc.id, data),
                                ],
                                if (data["status"] == "pending") ...[
                                  SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _actionButton(
                                          icon: Icons.edit_outlined,
                                          label: "Edit",
                                          color: const Color(0xFF6366F1),
                                          onTap: () => _editOrder(context, doc.id, data),
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: _actionButton(
                                          icon: Icons.cancel_outlined,
                                          label: "Batal",
                                          color: const Color(0xFFEF4444),
                                          onTap: () => _cancelOrder(context, doc.id),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );

                      },
                    );
                  },
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _uploadPaymentProof(BuildContext context, String orderId) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child("payments/${orderId}_${DateTime.now().millisecondsSinceEpoch}.jpg");
      final uploadTask = await storageRef.putFile(File(image.path));
      final url = await uploadTask.ref.getDownloadURL();

      await firestore.collection("orders").doc(orderId).update({
        "payment_screenshot": url,
        "payment_status": "paid",
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Bukti bayaran berjaya dimuat naik"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ralat: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildRatingSection(BuildContext context, String orderId, Map<String, dynamic> data) {
    final existingRating = data["rider_rating"];
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Nilai Rider",
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.85),
            ),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (index) {
              final starValue = index + 1;
              final isFilled = existingRating != null && starValue <= existingRating;
              return GestureDetector(
                onTap: existingRating != null
                    ? null
                    : () {
                        firestore
                            .collection("orders")
                            .doc(orderId)
                            .update({"rider_rating": starValue});
                      },
                child: Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    isFilled ? Icons.star : Icons.star_border,
                    color: isFilled ? const Color(0xFFFCD34D) : Colors.white.withOpacity(0.4),
                    size: 28,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
