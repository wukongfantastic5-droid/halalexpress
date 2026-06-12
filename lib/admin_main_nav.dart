import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_screen.dart';
import 'announcement_screen.dart';
import 'admin_feedback_screen.dart';
import 'admin_rider_verify_screen.dart';
import 'widgets/bunny_icon.dart';

class AdminMainNav extends StatefulWidget {
  const AdminMainNav({super.key});

  @override
  State<AdminMainNav> createState() => _AdminMainNavState();
}

class _AdminMainNavState extends State<AdminMainNav> {
  int index = 0;

  final pages = [
    AdminDashboardScreen(),
    AdminScreen(),
    AnnouncementScreen(),
    const AdminFeedbackScreen(),
    AdminRiderVerifyScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkExportReminder();
  }

  Future<void> _checkExportReminder() async {
    final prefs = await SharedPreferences.getInstance();
    final lastDismissed = prefs.getInt("lastExportReminder") ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    const weekMs = 7 * 24 * 60 * 60 * 1000;

    if (now - lastDismissed < weekMs) return;
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: const Color(0xFF0D7377)),
            const SizedBox(width: 8),
            Text("Export Data", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ],
        ),
        content: Text(
          "Sudah 7 hari! Jalan export_delete.js untuk backup data sebelum dipadam dari server.",
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await prefs.setInt("lastExportReminder", now);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text("Saya Dah Export", style: GoogleFonts.poppins(color: const Color(0xFF14C38E))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 120,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0D7377),
                Color(0xFF14919B),
                Color(0xFF14C38E),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 16, right: 16),
                child: Row(
                  children: [
                    BunnyIcon(
                      size: 36,
                      color: Colors.white,
                      accentColor: const Color(0xFF14C38E),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "BunnyFresh",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 22),
                      tooltip: "Log keluar",
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => LoginScreen()),
                          (route) => false,
                        );
                      },
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.only(left: 16, right: 16, bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _tab("Dashboard", 0),
                    _tab("Pesanan", 1),
                    _tab("Pengumuman", 2),
                    _tab("Maklum Balas", 3),
                    _tab("Rider", 4),
                  ],
                ),
              ),
            ],
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8F5E9),
              Color(0xFFF1F8E9),
              Color(0xFFFFFDE7),
            ],
          ),
        ),
        child: pages[index],
      ),
    );
  }

  Widget _tab(String title, int i) {
    final bool isSelected = index == i;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            index = i;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: EdgeInsets.all(isSelected ? 4 : 4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withOpacity(0.25) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
