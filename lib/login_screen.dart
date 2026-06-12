import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import 'register_screen.dart';
import 'gps_service.dart';
import 'admin_main_nav.dart';
import 'user_main_nav.dart';
import 'rider_main_nav.dart';
import 'force_update_screen.dart';


class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {

  final accountName = TextEditingController();
  final password = TextEditingController();

  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;

  bool isLoading = false;
  String appVersion = "";

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    Future.delayed(Duration.zero, () async {
      bool ok = await GPSService.ensureGPS();

      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Sila aktifkan GPS untuk meneruskan"),
            backgroundColor: Colors.red,
          ),
        );
      }

      try {
        final info = await PackageInfo.fromPlatform();
        if (mounted) setState(() => appVersion = "Version: v${info.version}");
      } catch (_) {}

      if (mounted) _showHalalWelcomeIfNeeded();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Container(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Sedang log masuk...",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showSuccessDialog(String role, String uid) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D9488), Color(0xFF059669)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 20),
                Text(
                  "Berjaya",
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                  Text(
                    role == "admin"
                        ? "Login berjaya sebagai Pentadbir"
                        : role == "rider"
                            ? "Login berjaya sebagai Rider"
                            : "Login berjaya sebagai Pelanggan",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0D9488), Color(0xFF059669)],
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);

                        if (role == "admin") {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminMainNav(),
                            ),
                          );
                        } else if (role == "rider") {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RiderMainNav(),
                            ),
                          );
                        } else {
                          bool showTutorial = false;
                          try {
                            final userDoc = await firestore
                                .collection("users")
                                .doc(uid)
                                .get();
                            showTutorial =
                                !(userDoc["hasSeenTutorial"] ?? false);
                          } catch (_) {}

                          if (!context.mounted) return;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => UserMainNav(
                                uid: uid,
                                showTutorial: showTutorial,
                              ),
                            ),
                          );

                          Future.delayed(
                            const Duration(milliseconds: 800),
                            () {
                              showLatestAnnouncementPopup();
                            },
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        "OK",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
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
  }

  void showFailDialog(String msg) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 20),
                Text(
                  "Gagal",
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0D9488)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      "Tutup",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0D9488),
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

  Future<void> showLatestAnnouncementPopup() async {
    try {
      final snapshot = await firestore
          .collection("announcements")
          .orderBy("created_at", descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return;

      final data = snapshot.docs.first.data();

      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            content: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 40,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.campaign, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Pengumuman Terkini",
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    data["message"] ?? "Tiada pengumuman",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D9488), Color(0xFF059669)],
                        ),
                      ),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          "Tutup",
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
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
      print("RALAT POPUP PENGUMUMAN: $e");
    }
  }

  void _showMaintenanceDialog(String updateLink) {
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cloud_off, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 20),
                Text(
                  "Penyelenggaraan",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Server sedang dalam penyelenggaraan.\nSila cuba sebentar lagi.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                if (updateLink.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        launchUrl(Uri.parse(updateLink), mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                      label: Text(
                        "Muat Turun Versi Terbaru",
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D7377),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    "Tutup",
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF6B7280),
                      fontSize: 14,
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

  void _showUpdateScreen(String url, String currentVersion, String latestVersion) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForceUpdateScreen(
          downloadUrl: url,
          latestVersion: latestVersion,
          currentVersion: currentVersion,
        ),
      ),
    );
  }

  bool _isVersionLower(String current, String latest) {
    final cur = current.split('.').map(int.parse).toList();
    final lat = latest.split('.').map(int.parse).toList();
    for (int i = 0; i < 3; i++) {
      final c = i < cur.length ? cur[i] : 0;
      final l = i < lat.length ? lat[i] : 0;
      if (c < l) return true;
      if (c > l) return false;
    }
    return false;
  }

  Future<void> _showHalalWelcomeIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt("halal_welcome_count") ?? 0;
      if (count >= 3) return;
      await prefs.setInt("halal_welcome_count", count + 1);
    } catch (_) {
      return;
    }

    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0D7377),
                  Color(0xFF14C38E),
                  Color(0xFF0D7377),
                ],
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0D7377).withOpacity(0.4),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
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
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.nights_stay,
                        size: 48,
                        color: Colors.white.withOpacity(0.95),
                      ),
                      Positioned(
                        right: 14,
                        top: 16,
                        child: Icon(
                          Icons.star,
                          size: 18,
                          color: Colors.yellowAccent.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Bismillahirrahmanirrahim",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "\u0628\u0650\u0633\u0652\u0645\u0650 \u0627\u0644\u0644\u0651\u064e\u0647\u0650 \u0627\u0644\u0631\u0651\u064e\u062d\u0652\u0645\u064e\u0646\u0650 \u0627\u0644\u0631\u0651\u064e\u062d\u0650\u064a\u0645\u0650",
                  style: GoogleFonts.notoNaskhArabic(
                    fontSize: 18,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "Selamat Datang ke BunyFresh!",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Kami hanya menerima produk HALAL. "
                        "Semua penghantaran adalah dari kedai-kedai yang "
                        "telah disahkan halal. Terima kasih kerana "
                        "memilih kami sebagai rakan penghantaran anda.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 12.5,
                          color: Colors.white.withOpacity(0.85),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF0D7377),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      "Saya Faham",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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

  void login() async {
    setState(() {
      isLoading = true;
    });

    showLoadingDialog();

    try {
      final query = await firestore
          .collection("users")
          .where(
            "account_name",
            isEqualTo: accountName.text.trim(),
          )
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        Navigator.pop(context);

        setState(() {
          isLoading = false;
        });

        showFailDialog("Akaun tidak dijumpai");
        return;
      }

      final userData = query.docs.first;
      final uid = userData.id;
      final email = userData["email"];
      final role = userData["role"];

      try {
        final settingsDoc = await firestore
            .collection("settings")
            .doc("app_settings")
            .get();

        final isMaintenance = settingsDoc.exists &&
            (settingsDoc["isUnderMaintenance"] == true) &&
            role != "admin";

        // Maintenance check first (applies to all)
        if (isMaintenance) {
          Navigator.pop(context);
          setState(() {
            isLoading = false;
          });
          _showMaintenanceDialog("");
          return;
        }

        // Version check from GitHub (admin bypass)
        if (role != "admin") {
          try {
            final res = await http.get(
              Uri.parse("https://api.github.com/repos/wukongfantastic5-droid/bunnyfresh/releases/latest"),
              headers: {"Accept": "application/vnd.github.v3+json"},
            );
            if (res.statusCode == 200) {
              final json = jsonDecode(res.body);
              final tagName = (json["tag_name"] as String?) ?? "";
              final ghVersion = tagName.replaceFirst(RegExp(r'^v'), '');
              final assets = json["assets"] as List<dynamic>? ?? [];
              String? ghUrl;
              for (final asset in assets) {
                final name = (asset as Map<String, dynamic>)["name"] as String? ?? "";
                if (name.endsWith(".apk")) {
                  ghUrl = asset["browser_download_url"] as String?;
                  break;
                }
              }
              if (ghVersion.isNotEmpty && ghUrl != null) {
                final info = await PackageInfo.fromPlatform();
                if (_isVersionLower(info.version.trim(), ghVersion)) {
                  Navigator.pop(context);
                  setState(() => isLoading = false);
                  _showUpdateScreen(ghUrl, info.version.trim(), ghVersion);
                  return;
                }
              }
            }
          } catch (_) {}
        }
      } catch (e) {
      }

      await auth.signInWithEmailAndPassword(
        email: email,
        password: password.text.trim(),
      );

      Navigator.pop(context);

      setState(() {
        isLoading = false;
      });

      showSuccessDialog(role, uid);

    } catch (e) {
      Navigator.pop(context);

      setState(() {
        isLoading = false;
      });

      showFailDialog("Login gagal");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F766E),
              Color(0xFF115E59),
              Color(0xFF065F46),
              Color(0xFF064E3B),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 800),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),

                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 25,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.shopping_cart_rounded,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      "Selamat Datang",
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),



                    const SizedBox(height: 40),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.20),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 50,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: accountName,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              labelText: "Nama Akaun",
                              labelStyle: GoogleFonts.poppins(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.08),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFF14B8A6),
                                  width: 2,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.person_outline,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          TextField(
                            controller: password,
                            obscureText: true,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              labelText: "Kata Laluan",
                              labelStyle: GoogleFonts.poppins(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 14,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.08),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.15),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFF14B8A6),
                                  width: 2,
                                ),
                              ),
                              prefixIcon: Icon(
                                Icons.lock_outline,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _pulseAnimation.value,
                                child: child,
                              );
                            },
                            child: SizedBox(
                              width: double.infinity,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0D9488).withValues(alpha: 0.4),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(vertical: 17),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    disabledBackgroundColor: Colors.transparent,
                                  ),
                                  child: Text(
                                    "Log Masuk",
                                    style: GoogleFonts.poppins(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RegisterScreen(),
                                ),
                              );
                            },
                            child: Text(
                              "Cipta Akaun Baru",
                              style: GoogleFonts.poppins(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    Text(
                      "© Hak Cipta MuslimGroup",
                      style: GoogleFonts.poppins(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                    ),
                    if (appVersion.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          appVersion,
                          style: GoogleFonts.poppins(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
