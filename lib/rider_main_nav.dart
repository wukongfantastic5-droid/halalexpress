import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'login_screen.dart';
import 'admin_screen.dart';
import 'history_order_screen.dart';
import 'rider_wallet_screen.dart';
import 'rider_profile_screen.dart';
import 'widgets/bunny_icon.dart';
import 'force_update_screen.dart';
import 'tutorial_overlay.dart';

class RiderMainNav extends StatefulWidget {
  final bool showTutorial;

  const RiderMainNav({super.key, this.showTutorial = false});

  @override
  State<RiderMainNav> createState() => _RiderMainNavState();
}

class _RiderMainNavState extends State<RiderMainNav> {
  int index = 0;
  String? riderUid;
  bool? _isVerified;
  bool _checking = true;
  bool _showTutorial = false;

  final _tab1Key = GlobalKey();
  final _tab2Key = GlobalKey();
  final _tab3Key = GlobalKey();
  final _tab4Key = GlobalKey();
  final _logoutKey = GlobalKey();
  late final List<TutorialStep> _tutorialSteps;

  @override
  void initState() {
    super.initState();
    riderUid = FirebaseAuth.instance.currentUser?.uid;
    _checkVerification();
    _checkUpdateFromGitHub();
    _tutorialSteps = [
      TutorialStep(
        targetKey: _tab1Key,
        title: "Selamat Datang!",
        description: "Anda telah log masuk sebagai Rider. Ikuti tutorial ringkas ini untuk mengenali fungsi-fungsi utama aplikasi BunnyFresh.",
        noSpotlight: true,
      ),
      TutorialStep(
        targetKey: _tab1Key,
        title: "Pesanan Aktif",
        description: "Lihat dan urus pesanan yang tersedia. Ambil tugas baru dan kemas kini status penghantaran dari sini.",
      ),
      TutorialStep(
        targetKey: _tab2Key,
        title: "Sejarah",
        description: "Semak sejarah pendapatan dan pesanan yang telah selesai. Anda juga boleh muat turun laporan pendapatan.",
      ),
      TutorialStep(
        targetKey: _tab3Key,
        title: "Dompet",
        description: "Lihat baki dompet dan buat permohonan pengeluaran pendapatan.",
      ),
      TutorialStep(
        targetKey: _tab4Key,
        title: "Profil",
        description: "Uruskan profil rider anda: nama, email, dokumen motor, kata laluan, dan maklumat bank.",
      ),
      TutorialStep(
        targetKey: _logoutKey,
        title: "Log Keluar",
        description: "Tekan ikon ini untuk log keluar dari akaun rider anda bila-bila masa.",
      ),
    ];
    if (widget.showTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _showTutorial = true);
      });
    }
  }

  Future<void> _markTutorialSeen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection("riders").doc(uid).set({
      "hasSeenTutorial": true,
    }, SetOptions(merge: true));
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

  Future<void> _checkUpdateFromGitHub() async {
    try {
      final res = await http.get(
        Uri.parse("https://api.github.com/repos/wukongfantastic5-droid/bunnyfresh/releases/latest"),
        headers: {"Accept": "application/vnd.github.v3+json"},
      );
      if (res.statusCode != 200 || !mounted) return;
      final json = jsonDecode(res.body);
      final tagName = (json["tag_name"] as String?) ?? "";
      final ghVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      String? ghUrl;
      final assets = json["assets"] as List<dynamic>? ?? [];
      for (final asset in assets) {
        final name = (asset as Map<String, dynamic>)["name"] as String? ?? "";
        if (name.endsWith(".apk")) {
          ghUrl = asset["browser_download_url"] as String?;
          break;
        }
      }
      if (ghVersion.isEmpty || ghUrl == null) return;
      final info = await PackageInfo.fromPlatform();
      if (!_isVersionLower(info.version.trim(), ghVersion)) return;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ForceUpdateScreen(
            downloadUrl: ghUrl!,
            latestVersion: ghVersion,
            currentVersion: info.version.trim(),
          ),
        ),
      );
    } catch (_) {}
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

  List<Widget> get pages => [
    AdminScreen(isRider: true),
    HistoryOrderScreen(riderUid: riderUid),
    const RiderWalletScreen(),
    const RiderProfileScreen(),
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

    return Stack(
      children: [
        Scaffold(
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
                          key: _logoutKey,
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
                        _tab("Dompet", 2),
                        _tab("Profil", 3),
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
        ),
        if (_showTutorial)
          TutorialOverlay(
            steps: _tutorialSteps,
            onFinished: () {
              _markTutorialSeen();
              setState(() => _showTutorial = false);
            },
            onSkipped: () {
              _markTutorialSeen();
              setState(() => _showTutorial = false);
            },
          ),
      ],
    );
  }

  Widget _tab(String title, int i) {
    final bool isSelected = index == i;
    final key = i == 0 ? _tab1Key : i == 1 ? _tab2Key : i == 2 ? _tab3Key : _tab4Key;

    return Expanded(
      key: key,
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
