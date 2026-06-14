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

  final _pesananIconKey = GlobalKey();
  final _maklumatIconKey = GlobalKey();
  final _feedbackIconKey = GlobalKey();
  final _sejarahIconKey = GlobalKey();
  final _profilIconKey = GlobalKey();
  final _logoutKey = GlobalKey();

  late final List<TutorialStep> _tutorialSteps;

  late AnimationController _slideController;

  final firestore = FirebaseFirestore.instance;

  late final Widget _pesananIcon;
  late final Widget _maklumatIcon;
  late final Widget _feedbackIcon;
  late final Widget _sejarahIcon;
  late final Widget _profilIcon;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideController.forward();

    _pesananIcon = Container(
      key: _pesananIconKey,
      padding: EdgeInsets.all(8),
      child: Icon(Icons.shopping_cart_rounded, size: 26),
    );
    _maklumatIcon = Container(
      key: _maklumatIconKey,
      padding: EdgeInsets.all(8),
      child: Icon(Icons.campaign_rounded, size: 26),
    );
    _feedbackIcon = Container(
      key: _feedbackIconKey,
      padding: EdgeInsets.all(8),
      child: Icon(Icons.feedback_outlined, size: 26),
    );
    _sejarahIcon = Container(
      key: _sejarahIconKey,
      padding: EdgeInsets.all(8),
      child: Icon(Icons.history_rounded, size: 26),
    );
    _profilIcon = Container(
      key: _profilIconKey,
      padding: EdgeInsets.all(8),
      child: Icon(Icons.person_outline_rounded, size: 26),
    );

    _tutorialSteps = [
      TutorialStep(
        targetKey: _maklumatIconKey,
        title: "Selamat Datang!",
        description: "Anda telah log masuk sebagai Pelanggan. Ikuti tutorial ringkas ini untuk mengenali fungsi-fungsi utama aplikasi BunnyFresh.",
        noSpotlight: true,
      ),
      TutorialStep(
        targetKey: _maklumatIconKey,
        title: "Maklumat Terkini",
        description: "Semak halaman ini untuk sebarang pengumuman atau pemberitahuan terkini daripada pihak admin tentang perkhidmatan kami.",
        onStepEnter: () {
          if (index != 1) {
            setState(() => index = 1);
          }
        },
      ),
      TutorialStep(
        targetKey: _feedbackIconKey,
        title: "Maklum Balas",
        description: "Hantar maklum balas atau cadangan anda kepada pihak admin. Pandangan anda membantu kami memperbaiki perkhidmatan.",
        onStepEnter: () {
          if (index != 2) {
            setState(() => index = 2);
          }
        },
      ),
      TutorialStep(
        targetKey: _sejarahIconKey,
        title: "Sejarah Pesanan",
        description: "Lihat sejarah pesanan anda yang telah selesai. Anda boleh semak butiran pesanan lepas di sini.",
        onStepEnter: () {
          if (index != 3) {
            setState(() => index = 3);
          }
        },
      ),
      TutorialStep(
        targetKey: _profilIconKey,
        title: "Profil Anda",
        description: "Uruskan profil peribadi anda, termasuk nama, alamat, nombor telefon, dan tetapan gelap (dark mode).",
        onStepEnter: () {
          if (index != 4) {
            setState(() => index = 4);
          }
        },
      ),
      TutorialStep(
        targetKey: _logoutKey,
        title: "Log Keluar",
        description: "Tekan ikon ini untuk log keluar dari akaun anda bila-bila masa.",
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
                const SizedBox(width: 8),
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
                    icon: _pesananIcon,
                    activeIcon: _pesananIcon,
                    label: "Pesanan",
                  ),
                  BottomNavigationBarItem(
                    icon: _maklumatIcon,
                    activeIcon: _maklumatIcon,
                    label: "Maklumat Terkini",
                  ),
                  BottomNavigationBarItem(
                    icon: _feedbackIcon,
                    activeIcon: _feedbackIcon,
                    label: "Maklum Balas",
                  ),
                  BottomNavigationBarItem(
                    icon: _sejarahIcon,
                    activeIcon: _sejarahIcon,
                    label: "Sejarah",
                  ),
                  BottomNavigationBarItem(
                    icon: _profilIcon,
                    activeIcon: _profilIcon,
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
