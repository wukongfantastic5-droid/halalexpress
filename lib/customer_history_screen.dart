import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

String _formatItems(dynamic items) {
  if (items is List && items.isNotEmpty) {
    final parts = items.map((item) {
      final name = (item["name"] ?? "").toString().trim();
      final qty = (item["qty"] ?? 1) as int;
      if (name.isEmpty) return "";
      return qty > 1 ? "$name \u00d7$qty" : name;
    }).where((s) => s.isNotEmpty);
    return parts.join(", ");
  }
  return items?.toString() ?? "-";
}

String _formatDate(DateTime d) {
  return "${d.day.toString().padLeft(2, '0')}/"
      "${d.month.toString().padLeft(2, '0')}/"
      "${d.year}";
}

List<String> _timelineSteps = [
  "Menunggu",
  "Dijemput",
  "Dalam Perjalanan",
  "Selesai",
];

int _statusToIndex(String status) {
  switch (status) {
    case "pending":
    case "menunggu":
      return 0;
    case "accepted":
    case "dijemput":
      return 1;
    case "on the way":
    case "dalam perjalanan":
      return 2;
    case "delivered":
    case "selesai":
      return 3;
    default:
      return 0;
  }
}

class CustomerHistoryScreen extends StatefulWidget {
  const CustomerHistoryScreen({super.key});

  @override
  State<CustomerHistoryScreen> createState() => _CustomerHistoryScreenState();
}

class _CustomerHistoryScreenState extends State<CustomerHistoryScreen>
    with TickerProviderStateMixin {
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;

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
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Widget _buildTimeline(int activeIndex) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: List.generate(_timelineSteps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIdx = i ~/ 2;
            final isCompleted = stepIdx < activeIndex;
            final isActive = stepIdx == activeIndex;
            return Expanded(
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? Color(0xFFFCD34D)
                      : isActive
                          ? Color(0xFF0D7377)
                          : Color(0xFFBDBDBD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }
          final stepIdx = i ~/ 2;
          final isCompleted = stepIdx < activeIndex;
          final isActive = stepIdx == activeIndex;
          return Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? Color(0xFFFCD34D)
                  : isActive
                      ? Color(0xFF0D7377)
                      : Color(0xFFBDBDBD),
              border: isActive
                  ? Border.all(color: Color(0xFF0D7377).withOpacity(0.5), width: 2)
                  : null,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Color(0xFF0D7377).withOpacity(0.4),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: isCompleted
                  ? Icon(Icons.check, size: 12, color: Colors.white)
                  : isActive
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        )
                      : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTimelineLabels(int activeIndex) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        children: List.generate(_timelineSteps.length, (i) {
          final isCompleted = i < activeIndex;
          final isActive = i == activeIndex;
          return Expanded(
            child: Text(
              _timelineSteps[i],
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 8,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isCompleted
                    ? Color(0xFFFCD34D)
                    : isActive
                        ? Color(0xFF0D7377)
                        : Color(0xFFBDBDBD),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> data, String docId) {
    final items = _formatItems(data["items"] ?? data["grocery"]);
    final fare = double.tryParse(
            (data["fare"] ?? data["total"] ?? "0").toString()) ??
        0;
    final distance = (data["distance_km"] ?? "0").toString();
    final riderName = data["rider_name"] ?? "";
    final paymentStatus = data["payment_status"]?.toString();
    final rating = data["rider_rating"];
    final statusIndex = _statusToIndex(data["status"] ?? "delivered");

    String dateText = "";
    if (data["delivered_at"] != null) {
      DateTime d = (data["delivered_at"] as Timestamp).toDate();
      dateText = _formatDate(d);
    } else if (data["created_at"] != null) {
      DateTime d = (data["created_at"] as Timestamp).toDate();
      dateText = _formatDate(d);
    }

    return Container(
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.25),
            Colors.white.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF14C38E),
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data["shop_name"] ?? "Kedai",
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      items,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFF0D7377).withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "RM ${fare.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "Tambang",
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
          SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: 13, color: Colors.white.withOpacity(0.5)),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  data["drop"] ?? "-",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Icon(Icons.straighten,
                  size: 13, color: Colors.white.withOpacity(0.5)),
              SizedBox(width: 3),
              Text(
                "$distance km",
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.calendar_today,
                  size: 13, color: Colors.white.withOpacity(0.5)),
              SizedBox(width: 4),
              Text(
                dateText,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
              if (riderName.isNotEmpty) ...[
                SizedBox(width: 16),
                Icon(Icons.motorcycle_outlined,
                    size: 13, color: Color(0xFFFCD34D)),
                SizedBox(width: 4),
                Text(
                  riderName,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Color(0xFFFCD34D),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          if (paymentStatus != null) ...[
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: paymentStatus.toLowerCase() == "paid"
                    ? Color(0xFF14C38E).withOpacity(0.2)
                    : Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: paymentStatus.toLowerCase() == "paid"
                      ? Color(0xFF14C38E).withOpacity(0.4)
                      : Colors.orange.withOpacity(0.4),
                ),
              ),
              child: Text(
                paymentStatus.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: paymentStatus.toLowerCase() == "paid"
                      ? Color(0xFF14C38E)
                      : Colors.orange,
                ),
              ),
            ),
          ],
          if (rating != null) ...[
            SizedBox(height: 8),
            Row(
              children: [
                ...List.generate(5, (i) {
                  final star = (rating is int)
                      ? rating
                      : double.tryParse(rating.toString()) ?? 0;
                  return Icon(
                    i < star ? Icons.star : Icons.star_border,
                    size: 16,
                    color: Color(0xFFFCD34D),
                  );
                }),
              ],
            ),
          ],
          SizedBox(height: 10),
          Divider(color: Colors.white.withOpacity(0.1), height: 1),
          SizedBox(height: 10),
          _buildTimelineLabels(statusIndex),
          _buildTimeline(statusIndex),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) {
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
              "Sejarah Pesanan",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
          ),
          body: Center(
            child: Text(
              "Sila log masuk",
              style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.7),
                fontSize: 15,
              ),
            ),
          ),
        ),
      );
    }

    final stream = firestore
        .collection("orders")
        .where("user_uid", isEqualTo: user.uid)
        .where("status", isEqualTo: "delivered")
        .orderBy("created_at", descending: true)
        .snapshots();

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
            "Sejarah Pesanan",
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
          child: StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      "Ralat: ${snapshot.error}",
                      style: GoogleFonts.poppins(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return Center(
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
                          Icons.history_rounded,
                          size: 64,
                          color: Colors.white.withOpacity(0.35),
                        ),
                        SizedBox(height: 16),
                        Text(
                          "Tiada sejarah pesanan",
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          "Pesanan yang telah selesai akan muncul di sini.",
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  return _buildOrderCard(data, doc.id);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
