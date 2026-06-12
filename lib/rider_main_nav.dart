import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import 'login_screen.dart';
import 'admin_screen.dart';
import 'history_order_screen.dart';
import 'widgets/bunny_icon.dart';

class RiderMainNav extends StatefulWidget {
  const RiderMainNav({super.key});

  @override
  State<RiderMainNav> createState() => _RiderMainNavState();
}

class _RiderMainNavState extends State<RiderMainNav> {
  int index = 0;
  String? riderUid;
  bool? _isVerified;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    riderUid = FirebaseAuth.instance.currentUser?.uid;
    _checkVerification();
    _checkUpdateLink();
  }

  Future<void> _checkVerification() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection("riders")
          .doc(uid)
          .get();
      if (mounted) {
        setState(() {
          _isVerified = doc["rider_verified"] == true;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _checkUpdateLink() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("settings")
          .doc("app_settings")
          .get();
      if (!doc.exists || !mounted) return;
      final link = doc["update_link"] ?? "";
      if (link.toString().trim().isEmpty) return;
      _showUpdatePopup(link.toString().trim());
    } catch (_) {}
  }

  void _showUpdatePopup(String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0D7377).withOpacity(0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 20),
                Text(
                  "Kemas Kini Tersedia",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Sila muat turun versi terbaru aplikasi untuk pengalaman yang lebih baik.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.85),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.download_rounded, color: Color(0xFF0D7377)),
                    label: Text(
                      "Muat Turun Sekarang",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0D7377),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    "Nanti sahaja",
                    style: GoogleFonts.poppins(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
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

  List<Widget> get pages => [
    AdminScreen(isRider: true),
    HistoryOrderScreen(riderUid: riderUid),
  ];

  Widget _buildPendingVerification() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D7377),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.verified_user_outlined,
                size: 52,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              "Menunggu Pengesahan",
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                "Akaun rider anda sedang menunggu pengesahan daripada admin. Sila tunggu sehingga akaun anda disahkan sebelum mula menerima pesanan.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.8),
                  height: 1.5,
                ),
              ),
            ),
            const Spacer(flex: 1),
            Container(
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(bottom: 20),
              child: const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
            Text(
              "Semak semula kemudian",
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D7377),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_isVerified == false) {
      return _buildPendingVerification();
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 110,
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
                      "BunnyFresh Rider",
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
                    _tab("Pesanan", 0),
                    _tab("Sejarah", 1),
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
