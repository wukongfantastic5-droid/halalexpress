import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'notification_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final firestore = FirebaseFirestore.instance;
  final AudioPlayer player = AudioPlayer();

  double totalRevenue = 0;
  int totalOrders = 0;
  int completedOrders = 0;
  List<QueryDocumentSnapshot> orders = [];

  Map<String, double> monthlyRevenue = {};
  Map<String, int> riderPerformance = {};

  String _fmtItem(String fallback, dynamic items) {
    if (items is List && items.isNotEmpty) {
      return items.map((item) {
        final name = (item["name"] ?? "").toString().trim();
        final qty = (item["qty"] ?? 1) as int;
        if (name.isEmpty) return "";
        return qty > 1 ? "$name ×$qty" : name;
      }).where((s) => s.isNotEmpty).join(", ");
    }
    return fallback;
  }

  String latestOrderId = "";

  @override
  void initState() {
    super.initState();

    loadAnalytics();
    saveFCMToken();
    listenRealtimeOrders();
    listenNotificationTap();

    NotificationService.init();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  Future<void> saveFCMToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid != null && token != null) {
        await firestore.collection("users").doc(uid).update({
          "fcm_token": token,
        });
      }
    } catch (e) {
      debugPrint("Ralat FCM Token: $e");
    }
  }

  void listenRealtimeOrders() {
    firestore
        .collection("orders")
        .orderBy("created_at", descending: true)
        .snapshots()
        .listen((snapshot) {
      loadAnalytics();

      if (snapshot.docs.isEmpty) return;

      final newest = snapshot.docs.first;

      if (latestOrderId == "") {
        latestOrderId = newest.id;
        return;
      }

      if (newest.id != latestOrderId) {
        latestOrderId = newest.id;

        final data = newest.data();

        player.play(AssetSource('audio/order_received.mp3'));

        showNewOrderPopup(data);

        NotificationService.showOrderNotification(
          title: "🚨 Pesanan Baru Diterima",
          body: "${_fmtItem(data["grocery"] ?? "", data["items"])} → ${data["drop"]}",
          orderId: newest.id,
        );
      }
    });
  }

  void listenNotificationTap() {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Membuka pesanan terkini...")),
      );
    });
  }

  void showNewOrderPopup(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  Color(0xFFF1F8E9),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B6B).withOpacity(0.3),
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: Colors.white,
                    size: 45,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "PESANAN BARU DITERIMA",
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0D7377),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shopping_cart, size: 18, color: Color(0xFF0D7377)),
                          const SizedBox(width: 8),
                          Text(
                            "🛒 ${_fmtItem(data["grocery"] ?? "", data["items"])}",
                            style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 18, color: Color(0xFF0D7377)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              "📍 ${data["drop"] ?? ""}",
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D7377),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "LIHAT PESANAN",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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
  }

  Future<void> loadAnalytics() async {
    final snapshot = await firestore.collection("orders").get();
    orders = snapshot.docs;

    totalRevenue = 0;
    totalOrders = snapshot.docs.length;
    completedOrders = 0;

    monthlyRevenue = {};
    riderPerformance = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();

      double price =
          double.tryParse((data["fare"] ?? data["total"] ?? "0").toString()) ?? 0;
      double commission = price * 0.2; // 20% admin commission

      String status = data["status"] ?? "";
      String rider = data["rider"] ?? "tidak diketahui";

      if (status == "delivered") {
        totalRevenue += commission;
        completedOrders++;

        if (data["delivered_at"] != null) {
          DateTime d =
              (data["delivered_at"] as Timestamp).toDate();

          String monthKey =
              "${d.year}-${d.month.toString().padLeft(2, '0')}";

          monthlyRevenue[monthKey] =
              (monthlyRevenue[monthKey] ?? 0) + commission;
        }

        riderPerformance[rider] =
            (riderPerformance[rider] ?? 0) + 1;
      }
    }

    setState(() {});
  }

  Future<void> clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Reset Pendapatan", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text("Semua sejarah pendapatan akan dipadam. Anda pasti?", style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Batal", style: GoogleFonts.poppins())),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Reset", style: GoogleFonts.poppins(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      for (var doc in orders) {
        await firestore.collection("orders").doc(doc.id).delete();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Pendapatan telah direset"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal reset: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> exportToExcel() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Pendapatan'];

      sheet.appendRow([
        TextCellValue("Kedai"),
        TextCellValue("Tarikh Siap"),
        TextCellValue("Jarak (km)"),
        TextCellValue("Pendapatan (RM)"),
        TextCellValue("Rider"),
      ]);

      for (var doc in orders) {
        final data = doc.data() as Map<String, dynamic>;
        String dateText = "";
        if (data["delivered_at"] != null) {
          DateTime d = (data["delivered_at"] as Timestamp).toDate();
          dateText = "${d.day}/${d.month}/${d.year}";
        }
        final commission = (double.tryParse((data["fare"] ?? data["total"] ?? "0").toString()) ?? 0) * 0.2;
        sheet.appendRow([
          TextCellValue(data["shop_name"] ?? ""),
          TextCellValue(dateText),
          TextCellValue((data["distance_km"] ?? "0").toString()),
          DoubleCellValue(commission),
          TextCellValue(data["rider_name"] ?? ""),
        ]);
      }

      final dir = await getTemporaryDirectory();
      final path = "${dir.path}/pendapatan.xlsx";
      final bytes = excel.encode();
      if (bytes == null) return;
      await File(path).writeAsBytes(bytes);

      await Share.shareXFiles([XFile(path)], text: "Laporan Pendapatan");
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal export: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _actionButton(
                icon: Icons.delete_sweep_rounded,
                label: "Reset",
                color: Colors.redAccent,
                onTap: clearHistory,
              ),
              const SizedBox(width: 12),
              _actionButton(
                icon: Icons.file_download_rounded,
                label: "Export Excel",
                color: const Color(0xFF0D7377),
                onTap: exportToExcel,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildCard(
                "Jumlah Pendapatan",
                "RM ${totalRevenue.toStringAsFixed(2)}",
                Icons.monetization_on,
                const Color(0xFF0D7377),
                const Color(0xFF14C38E),
              ),
              const SizedBox(width: 12),
              _buildCard(
                "Pesanan",
                "$totalOrders",
                Icons.receipt_long,
                const Color(0xFF6366F1),
                const Color(0xFF818CF8),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCard(
                "Selesai",
                "$completedOrders",
                Icons.check_circle,
                const Color(0xFFF59E0B),
                const Color(0xFFFBBF24),
              ),
              const SizedBox(width: 12),
              _buildCard(
                "Kadar Kejayaan",
                totalOrders == 0
                    ? "0%"
                    : "${((completedOrders / totalOrders) * 100).toStringAsFixed(1)}%",
                Icons.trending_up,
                const Color(0xFF8B5CF6),
                const Color(0xFFA78BFA),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.9),
                  Colors.white.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.bar_chart,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Pendapatan Bulanan",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0D7377),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (monthlyRevenue.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        "Tiada data pendapatan",
                        style: GoogleFonts.poppins(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  ...monthlyRevenue.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF14C38E),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                e.key,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            "RM ${e.value.toStringAsFixed(2)}",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0D7377),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.9),
                  Colors.white.withOpacity(0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.emoji_transportation,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Prestasi Rider",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0D7377),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (riderPerformance.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        "Tiada data rider",
                        style: GoogleFonts.poppins(
                          color: Colors.grey.shade400,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  ...riderPerformance.entries.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.delivery_dining,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              e.key,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF14C38E).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "${e.value} pesanan",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF0D7377),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.12), color.withOpacity(0.06)],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    String title,
    String value,
    IconData icon,
    Color color1,
    Color color2,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.95),
              Colors.white.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color1, color2],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color1.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
