import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'login_screen.dart';
import 'order_screen.dart';
import 'announcement_user_screen.dart';
import 'feedback_screen.dart';
import 'customer_history_screen.dart';
import 'profile_screen.dart';
import 'tutorial_overlay.dart';
import 'widgets/bunny_icon.dart';
import 'force_update_screen.dart';

class UserMainNav extends StatefulWidget {
  final String uid;
  final bool showTutorial;

  const UserMainNav({
    super.key,
    required this.uid,
    this.showTutorial = false,
  });

  @override
  State<UserMainNav> createState() => _UserMainNavState();
}

class _UserMainNavState extends State<UserMainNav> with TickerProviderStateMixin {

  int index = 0;
  bool _showTutorial = false;

  final _formCardKey = GlobalKey();
  final _locationRowKey = GlobalKey();
  final _submitBtnKey = GlobalKey();
  final _pesananTabKey = GlobalKey();
  final _maklumatTabKey = GlobalKey();
  final _historyTabKey = GlobalKey();

  late final List<TutorialStep> _tutorialSteps;

  late AnimationController _slideController;

  final firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideController.forward();

    _tutorialSteps = [
      TutorialStep(
        targetKey: _formCardKey,
        title: "Buat Pesanan",
        description: "Isi borang pesanan dengan butiran barang yang ingin dibeli. Nyatakan barangan, nama kedai, dan butiran tambahan seperti alamat atau not khas.",
      ),
      TutorialStep(
        targetKey: _locationRowKey,
        title: "Pilih Lokasi",
        description: "Masukkan alamat penghantaran anda atau tekan butang GPS untuk mengesan lokasi semasa secara automatik.",
      ),
      TutorialStep(
        targetKey: _submitBtnKey,
        title: "Hantar Pesanan",
        description: "Selepas lengkap mengisi borang, tekan butang ini untuk menghantar pesanan kepada rider. Anda akan menerima notifikasi selepas pesanan diterima.",
      ),
      TutorialStep(
        targetKey: _pesananTabKey,
        title: "Pantau Pesanan",
        description: "Tab ini membolehkan anda melihat status terkini pesanan anda, termasuk bila rider sedang dalam perjalanan untuk menghantar ke rumah anda.",
      ),
      TutorialStep(
        targetKey: _maklumatTabKey,
        title: "Maklumat Terkini",
        description: "Semak halaman ini untuk sebarang pengumuman atau pemberitahuan terkini daripada pihak admin tentang perkhidmatan kami.",
        onStepEnter: () {
          if (index != 1) {
            setState(() => index = 1);
          }
        },
      ),
    ];

    if (widget.showTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _showTutorial = true);
      });
    }

    _checkUpdateFromGitHub();
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

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _markTutorialSeen() async {
    try {
      await firestore.collection("users").doc(widget.uid).set(
        {"hasSeenTutorial": true},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  List<Widget> get pages => [
    OrderScreen(
      formCardKey: _formCardKey,
      locationRowKey: _locationRowKey,
      submitBtnKey: _submitBtnKey,
    ),
    AnnouncementUserScreen(),
    const FeedbackScreen(),
    const CustomerHistoryScreen(),
    ProfileScreen(uid: widget.uid),
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            backgroundColor: const Color(0xFF0D7377),
            automaticallyImplyLeading: false,
            title: Row(
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
          body: AnimatedSwitcher(
            duration: Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
            child: KeyedSubtree(
              key: ValueKey(index),
              child: pages[index],
            ),
          ),
          bottomNavigationBar: Container(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.95),
                  Colors.white.withOpacity(0.9),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF0D7377).withOpacity(0.15),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BottomNavigationBar(
                currentIndex: index,
                onTap: (i) {
                  setState(() => index = i);
                  _slideController.reset();
                  _slideController.forward();
                },
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedFontSize: 12,
                unselectedFontSize: 11,
                selectedLabelStyle: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: GoogleFonts.poppins(),
                selectedItemColor: Color(0xFF0D7377),
                unselectedItemColor: Colors.grey.shade500,
                type: BottomNavigationBarType.fixed,
                items: [
                  BottomNavigationBarItem(
                    icon: Container(
                      key: _pesananTabKey,
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: index == 0
                            ? Color(0xFF0D7377).withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.shopping_cart_rounded,
                        size: 26,
                        color: index == 0 ? Color(0xFF0D7377) : Colors.grey.shade500,
                      ),
                    ),
                    activeIcon: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0D7377).withOpacity(0.15), Color(0xFF14C38E).withOpacity(0.1)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.shopping_cart_rounded,
                        size: 26,
                        color: Color(0xFF0D7377),
                      ),
                    ),
                    label: "Pesanan",
                  ),
                  BottomNavigationBarItem(
                    icon: Container(
                      key: _maklumatTabKey,
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: index == 1
                            ? Color(0xFF0D7377).withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.campaign_rounded,
                        size: 26,
                        color: index == 1 ? Color(0xFF0D7377) : Colors.grey.shade500,
                      ),
                    ),
                    activeIcon: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0D7377).withOpacity(0.15), Color(0xFF14C38E).withOpacity(0.1)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.campaign_rounded,
                        size: 26,
                        color: Color(0xFF0D7377),
                      ),
                    ),
                    label: "Maklumat Terkini",
                  ),
                  BottomNavigationBarItem(
                    icon: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: index == 2
                            ? Color(0xFF0D7377).withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.feedback_outlined,
                        size: 26,
                        color: index == 2 ? Color(0xFF0D7377) : Colors.grey.shade500,
                      ),
                    ),
                    activeIcon: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0D7377).withOpacity(0.15), Color(0xFF14C38E).withOpacity(0.1)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.feedback_rounded,
                        size: 26,
                        color: Color(0xFF0D7377),
                      ),
                    ),
                    label: "Maklum Balas",
                  ),
                  BottomNavigationBarItem(
                    icon: Container(
                      key: _historyTabKey,
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: index == 3
                            ? Color(0xFF0D7377).withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.history_rounded,
                        size: 26,
                        color: index == 3 ? Color(0xFF0D7377) : Colors.grey.shade500,
                      ),
                    ),
                    activeIcon: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0D7377).withOpacity(0.15), Color(0xFF14C38E).withOpacity(0.1)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.history_rounded,
                        size: 26,
                        color: Color(0xFF0D7377),
                      ),
                    ),
                    label: "Sejarah",
                  ),
                  BottomNavigationBarItem(
                    icon: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: index == 4
                            ? Color(0xFF0D7377).withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.person_outline_rounded,
                        size: 26,
                        color: index == 4 ? Color(0xFF0D7377) : Colors.grey.shade500,
                      ),
                    ),
                    activeIcon: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0D7377).withOpacity(0.15), Color(0xFF14C38E).withOpacity(0.1)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.person_rounded,
                        size: 26,
                        color: Color(0xFF0D7377),
                      ),
                    ),
                    label: "Profil",
                  ),
                ],
              ),
            ),
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
}
