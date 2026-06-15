import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'translations.dart';

class HistoryOrderScreen extends StatefulWidget {
  final String? riderUid;
  const HistoryOrderScreen({super.key, this.riderUid});

  @override
  State<HistoryOrderScreen> createState() => _HistoryOrderScreenState();
}

class _HistoryOrderScreenState extends State<HistoryOrderScreen> with TickerProviderStateMixin {
  final firestore = FirebaseFirestore.instance;

  List<DocumentSnapshot> orders = [];

  bool loading = false;

  DateTime? selectedDate;

  double totalRevenue = 0;
  double todayRevenue = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  StreamSubscription? _ordersSub;

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
    _startListening();
  }

  void _startListening() {
    _ordersSub?.cancel();
    _ordersSub = firestore
        .collection("orders")
        .where("status", isEqualTo: "delivered")
        .orderBy("delivered_at", descending: true)
        .snapshots()
        .listen((snapshot) {
      var docs = snapshot.docs;
      if (widget.riderUid != null) {
        docs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data["rider_uid"] == widget.riderUid;
        }).toList();
      }
      orders = docs;
      calculateRevenue();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  double _riderShare(double fare) {
    if (widget.riderUid == null) return fare;
    return fare * 0.8;
  }

  void calculateRevenue() {
    totalRevenue = 0;
    todayRevenue = 0;

    DateTime now = DateTime.now();

    for (var doc in orders) {
      final data = doc.data() as Map<String, dynamic>;

      double price = double.tryParse((data["fare"] ?? data["total"] ?? "0").toString()) ?? 0;
      price = _riderShare(price);

      totalRevenue += price;

      if (data["delivered_at"] != null) {
        DateTime d = (data["delivered_at"] as Timestamp).toDate();

        if (d.day == now.day && d.month == now.month && d.year == now.year) {
          todayRevenue += price;
        }
      }
    }
  }

  Future<void> deleteOrder(String id) async {
    try {
      await firestore.collection("orders").doc(id).delete();
    } catch (e) {
      print("DELETE ERROR: $e");
    }
  }

  Future<void> pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData(
            colorScheme: ColorScheme.light(
              primary: Color(0xFF0D7377),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF0D7377),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() { selectedDate = picked; });
      _filterByDate();
    }
  }

  void _filterByDate() async {
    setState(() => loading = true);

    final snapshot = await firestore
        .collection("orders")
        .where("status", isEqualTo: "delivered")
        .get();

    orders = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;

      if (data["delivered_at"] == null) return false;

      DateTime d = (data["delivered_at"] as Timestamp).toDate();

      if (selectedDate == null) return true;

      if (widget.riderUid != null && data["rider_uid"] != widget.riderUid) return false;

      return d.year == selectedDate!.year &&
          d.month == selectedDate!.month &&
          d.day == selectedDate!.day;
    }).toList();

    calculateRevenue();
    setState(() => loading = false);
  }

  Future<void> clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('Reset Earnings'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text("Semua sejarah pendapatan akan dipadam. Anda pasti?", style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins())),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppTranslations.get('Reset'), style: GoogleFonts.poppins(color: Colors.red))),
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
            content: Text(AppTranslations.get('Earnings have been reset')),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal reset: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> exportToExcel() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel[AppTranslations.get('Earnings')];

      sheet.appendRow([
        TextCellValue(AppTranslations.get('Shop')),
        TextCellValue(AppTranslations.get('Date Completed')),
        TextCellValue(AppTranslations.get('Distance (km)')),
        TextCellValue(AppTranslations.get('Earnings (RM)')),
        TextCellValue(AppTranslations.get('Rider')),
      ]);

      for (var doc in orders) {
        final data = doc.data() as Map<String, dynamic>;
        String dateText = "";
        if (data["delivered_at"] != null) {
          DateTime d = (data["delivered_at"] as Timestamp).toDate();
          dateText = "${d.day}/${d.month}/${d.year}";
        }
        final fare = _riderShare(double.tryParse((data["fare"] ?? data["total"] ?? "0").toString()) ?? 0);
        sheet.appendRow([
          TextCellValue(data["shop_name"] ?? ""),
          TextCellValue(dateText),
          TextCellValue((data["distance_km"] ?? "0").toString()),
          DoubleCellValue(fare),
          TextCellValue(data["rider_name"] ?? ""),
        ]);
      }

      final dir = await getTemporaryDirectory();
      final path = "${dir.path}/pendapatan.xlsx";
      final bytes = excel.encode();
      if (bytes == null) return;
      await File(path).writeAsBytes(bytes);

      await Share.shareXFiles([XFile(path)], text: AppTranslations.get('Earnings Report'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal export: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatCard(String title, String value, Color gradientStart, Color gradientEnd, IconData icon) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [gradientStart, gradientEnd],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: gradientStart.withOpacity(0.3),
            blurRadius: 15,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 6),
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> data, String dateText, DocumentSnapshot doc) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.2),
            Colors.white.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF14C38E),
              size: 24,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data["shop_name"] ?? "Order",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  "Siap: $dateText",
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                if ((data["rider_name"] ?? "").isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      "Rider: ${data["rider_name"]}",
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Color(0xFFFCD34D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                SizedBox(height: 4),
                Text(
                  "Jarak: ${data["distance_km"] ?? "0"} km",
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0D7377).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "RM ${_riderShare(double.tryParse((data["fare"] ?? data["total"] ?? "0").toString()) ?? 0).toStringAsFixed(2)}",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  AppTranslations.get('Earnings'),
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    color: Colors.white.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            "History Dashboard",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          actions: [
            if (widget.riderUid == null) ...[
              Container(
                margin: EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  icon: Icon(Icons.delete_sweep_rounded, color: Colors.white, size: 20),
                  tooltip: AppTranslations.get('Reset Earnings'),
                  onPressed: clearHistory,
                ),
              ),
              Container(
                margin: EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IconButton(
                  icon: Icon(Icons.file_download_rounded, color: Colors.white, size: 20),
                  tooltip: AppTranslations.get('Export Excel'),
                  onPressed: exportToExcel,
                ),
              ),
            ],
            Container(
              margin: EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                icon: Icon(Icons.calendar_month_rounded, color: Colors.white),
                onPressed: pickDate,
              ),
            ),
          ],
        ),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (selectedDate != null)
                      Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Color(0xFF14C38E).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today, size: 14, color: Color(0xFF14C38E)),
                              SizedBox(width: 8),
                              Text(
                                "${AppTranslations.get('Filtered:')} ${_formatDate(selectedDate!)}",
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  setState(() { selectedDate = null; });
                                  _startListening();
                                },
                                child: Icon(Icons.close, size: 16, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatCard(
                            AppTranslations.get('Total Earnings'),
                            "RM ${totalRevenue.toStringAsFixed(2)}",
                            Color(0xFF0D7377),
                            Color(0xFF14C38E),
                            Icons.account_balance_wallet_rounded,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _buildStatCard(
                            AppTranslations.get("Today's Earnings"),
                            "RM ${todayRevenue.toStringAsFixed(2)}",
                            Color(0xFF14C38E),
                            Color(0xFF0D7377),
                            Icons.today_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: orders.isEmpty && !loading
                    ? Center(
                        child: Container(
                          padding: EdgeInsets.all(32),
                          margin: EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.1),
                                Colors.white.withOpacity(0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.15),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.history_toggle_off,
                                size: 56,
                                color: Colors.white.withOpacity(0.4),
                              ),
                              SizedBox(height: 16),
                              Text(
                                selectedDate != null
                                    ? AppTranslations.get('No orders on this date')
                                    : AppTranslations.get('No order history'),
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final doc = orders[index];
                          final data = doc.data() as Map<String, dynamic>;

                          String dateText = "";
                          if (data["delivered_at"] != null) {
                            DateTime d = (data["delivered_at"] as Timestamp).toDate();
                            dateText = _formatDate(d);
                          }

                          return widget.riderUid == null
                              ? Dismissible(
                                  key: Key(doc.id),
                                  direction: DismissDirection.endToStart,
                                  onDismissed: (_) {
                                    deleteOrder(doc.id);
                                  },
                                  background: Container(
                                    margin: EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.red.shade500, Colors.red.shade300],
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    alignment: Alignment.centerRight,
                                    padding: EdgeInsets.only(right: 20),
                                    child: Icon(Icons.delete_rounded, color: Colors.white, size: 28),
                                  ),
                                  child: _buildOrderCard(data, dateText, doc),
                                )
                              : _buildOrderCard(data, dateText, doc);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return "${d.day.toString().padLeft(2, '0')}/"
        "${d.month.toString().padLeft(2, '0')}/"
        "${d.year}";
  }
}
