import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

class AdminProDashboard extends StatefulWidget {
  const AdminProDashboard({super.key});

  @override
  State<AdminProDashboard> createState() => _AdminProDashboardState();
}

class _AdminProDashboardState extends State<AdminProDashboard> with TickerProviderStateMixin {
  final firestore = FirebaseFirestore.instance;

  Map<int, double> monthlyIncome = {};
  Map<String, RiderStats> riderStats = {};

  double totalRevenue = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
    loadData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    final snapshot = await firestore.collection("orders").get();

    monthlyIncome.clear();
    riderStats.clear();
    totalRevenue = 0;

    for (var doc in snapshot.docs) {
      final data = doc.data();

      double price = double.tryParse((data["fare"] ?? data["total"] ?? "0").toString()) ?? 0;
      double commission = price * 0.2; // 20% admin commission
      double riderShare = price * 0.8; // 80% rider share

      String status = data["status"] ?? "";
      String rider = data["rider"] ?? "unknown";

      if (status == "delivered") {
        totalRevenue += commission;

        if (data["delivered_at"] != null) {
          DateTime d = (data["delivered_at"] as Timestamp).toDate();
          monthlyIncome[d.month] = (monthlyIncome[d.month] ?? 0) + commission;
        }

        riderStats[rider] ??= RiderStats();
        riderStats[rider]!.completedOrders++;
        riderStats[rider]!.totalEarnings += riderShare;

      } else if (status == "cancelled") {
        riderStats[rider] ??= RiderStats();
        riderStats[rider]!.cancelledOrders++;
      }
    }

    setState(() {});
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.25),
            Colors.white.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 6),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        SizedBox(width: 10),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard(Widget child) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withOpacity(0.2),
            Colors.white.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
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
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedMonths = monthlyIncome.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final sortedRiders = riderStats.entries.toList()
      ..sort((a, b) => b.value.calculateScore().compareTo(a.value.calculateScore()));

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D7377),
            Color(0xFF14C38E),
            Color(0xFF1A237E).withOpacity(0.25),
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            "Analytics Dashboard",
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatCard(
                  "Jumlah Pendapatan",
                  "RM ${totalRevenue.toStringAsFixed(2)}",
                  Icons.account_balance_wallet_rounded,
                  Color(0xFF14C38E),
                ),
                SizedBox(height: 20),
                _buildSectionHeader("Pendapatan Bulanan", Icons.bar_chart_rounded),
                SizedBox(height: 12),
                _buildChartCard(
                  monthlyIncome.isEmpty
                      ? Container(
                          height: 250,
                          child: Center(
                            child: Text(
                              "Tiada data pendapatan",
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          height: 250,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: monthlyIncome.values.isEmpty
                                  ? 100
                                  : monthlyIncome.values.reduce((a, b) => a > b ? a : b) * 1.2,
                              barTouchData: BarTouchData(
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                    return BarTooltipItem(
                                      "RM ${rod.toY.toStringAsFixed(2)}",
                                      TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final months = [
                                        "", "Jan", "Feb", "Mac", "Apr", "Mei", "Jun",
                                        "Jul", "Ogos", "Sep", "Okt", "Nov", "Dis"
                                      ];
                                      return Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                          months[value.toInt()],
                                          style: GoogleFonts.poppins(
                                            color: Colors.white.withOpacity(0.7),
                                            fontSize: 10,
                                          ),
                                        ),
                                      );
                                    },
                                    reservedSize: 28,
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        "RM${value.toInt()}",
                                        style: GoogleFonts.poppins(
                                          color: Colors.white.withOpacity(0.5),
                                          fontSize: 9,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: monthlyIncome.values.isEmpty
                                    ? 50
                                    : (monthlyIncome.values.reduce((a, b) => a > b ? a : b) * 1.2) / 4,
                                getDrawingHorizontalLine: (value) {
                                  return FlLine(
                                    color: Colors.white.withOpacity(0.1),
                                    strokeWidth: 1,
                                  );
                                },
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: sortedMonths.map((e) {
                                return BarChartGroupData(
                                  x: e.key,
                                  barRods: [
                                    BarChartRodData(
                                      toY: e.value,
                                      width: 20,
                                      gradient: LinearGradient(
                                        colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                      ),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(6),
                                        topRight: Radius.circular(6),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                ),
                _buildSectionHeader("Trend Pendapatan", Icons.trending_up_rounded),
                SizedBox(height: 12),
                _buildChartCard(
                  monthlyIncome.isEmpty
                      ? Container(
                          height: 250,
                          child: Center(
                            child: Text(
                              "Tiada data trend",
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          height: 250,
                          child: LineChart(
                            LineChartData(
                              minY: 0,
                              maxY: monthlyIncome.values.isEmpty
                                  ? 100
                                  : monthlyIncome.values.reduce((a, b) => a > b ? a : b) * 1.2,
                              lineTouchData: LineTouchData(
                                touchTooltipData: LineTouchTooltipData(
                                  getTooltipItems: (touchedSpots) {
                                    return touchedSpots.map((spot) {
                                      return LineTooltipItem(
                                        "RM ${spot.y.toStringAsFixed(2)}",
                                        TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      );
                                    }).toList();
                                  },
                                ),
                              ),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      final months = [
                                        "", "Jan", "Feb", "Mac", "Apr", "Mei", "Jun",
                                        "Jul", "Ogos", "Sep", "Okt", "Nov", "Dis"
                                      ];
                                      return Padding(
                                        padding: EdgeInsets.only(top: 8),
                                        child: Text(
                                          months[value.toInt()],
                                          style: GoogleFonts.poppins(
                                            color: Colors.white.withOpacity(0.7),
                                            fontSize: 10,
                                          ),
                                        ),
                                      );
                                    },
                                    reservedSize: 28,
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        "RM${value.toInt()}",
                                        style: GoogleFonts.poppins(
                                          color: Colors.white.withOpacity(0.5),
                                          fontSize: 9,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                horizontalInterval: monthlyIncome.values.isEmpty
                                    ? 50
                                    : (monthlyIncome.values.reduce((a, b) => a > b ? a : b) * 1.2) / 4,
                                getDrawingHorizontalLine: (value) {
                                  return FlLine(
                                    color: Colors.white.withOpacity(0.1),
                                    strokeWidth: 1,
                                  );
                                },
                              ),
                              borderData: FlBorderData(show: false),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: sortedMonths.map((e) {
                                    return FlSpot(e.key.toDouble(), e.value);
                                  }).toList(),
                                  isCurved: true,
                                  preventCurveOverShooting: true,
                                  color: Color(0xFF14C38E),
                                  barWidth: 3,
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter: (spot, percent, barData, index) {
                                      return FlDotCirclePainter(
                                        radius: 5,
                                        color: Color(0xFF0D7377),
                                        strokeWidth: 2,
                                        strokeColor: Colors.white,
                                      );
                                    },
                                  ),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF14C38E).withOpacity(0.3),
                                        Color(0xFF14C38E).withOpacity(0.0),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                _buildSectionHeader("Prestasi Rider", Icons.emoji_events_rounded),
                SizedBox(height: 12),
                _buildChartCard(
                  sortedRiders.isEmpty
                      ? Container(
                          padding: EdgeInsets.all(20),
                          child: Center(
                            child: Text(
                              "Tiada data rider",
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          children: sortedRiders.asMap().entries.map((entry) {
                            final index = entry.key;
                            final e = entry.value;
                            final score = e.value.calculateScore();
                            final isTop3 = index < 3;

                            Color medalColor;
                            IconData medalIcon;
                            switch (index) {
                              case 0:
                                medalColor = Color(0xFFFFD700);
                                medalIcon = Icons.emoji_events;
                                break;
                              case 1:
                                medalColor = Color(0xFFC0C0C0);
                                medalIcon = Icons.emoji_events;
                                break;
                              case 2:
                                medalColor = Color(0xFFCD7F32);
                                medalIcon = Icons.emoji_events;
                                break;
                              default:
                                medalColor = Colors.white.withOpacity(0.3);
                                medalIcon = Icons.circle;
                            }

                            return Container(
                              margin: EdgeInsets.only(bottom: 10),
                              padding: EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isTop3
                                    ? Colors.white.withOpacity(0.12)
                                    : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(18),
                                border: isTop3
                                    ? Border.all(
                                        color: medalColor.withOpacity(0.3),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: isTop3
                                          ? medalColor.withOpacity(0.2)
                                          : Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      medalIcon,
                                      color: medalColor,
                                      size: isTop3 ? 22 : 8,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.key,
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          "Siap: ${e.value.completedOrders} | Batal: ${e.value.cancelledOrders}",
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: Colors.white.withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: isTop3
                                            ? [Color(0xFF14C38E), Color(0xFF0D7377)]
                                            : [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      "${score.toStringAsFixed(1)}",
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RiderStats {
  int completedOrders = 0;
  int cancelledOrders = 0;
  double totalEarnings = 0;

  double calculateScore() {
    double efficiency = completedOrders == 0
        ? 0
        : (completedOrders / (completedOrders + cancelledOrders)) * 100;

    double speedBonus = completedOrders * 2;

    return efficiency + speedBonus;
  }
}
