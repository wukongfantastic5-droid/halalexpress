import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'admin_main_nav.dart';
import 'translations.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final accountCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final keyCtrl = TextEditingController();
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  bool _loading = false;
  bool _authenticated = false;
  bool _requestingKey = false;
  bool _verifyingKey = false;
  String? _uid;
  String? _adminWhatsApp;
  String? _error;
  int _countdown = 0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    accountCtrl.dispose();
    passwordCtrl.dispose();
    keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (accountCtrl.text.trim().isEmpty || passwordCtrl.text.isEmpty) {
      setState(() => _error = AppTranslations.get('Please fill in account name and password'));
      return;
    }
    setState(() { _loading = true; _error = null; });

    try {
      final query = await firestore
          .collection("users")
          .where("account_name", isEqualTo: accountCtrl.text.trim())
          .where("role", isEqualTo: "admin")
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() { _loading = false; _error = AppTranslations.get('Admin account not found'); });
        return;
      }

      final userData = query.docs.first;
      final uid = userData.id;
      final email = userData["email"] as String? ?? "";
      final whatsapp = userData["whatsapp"] as String? ?? "";

      if (email.isEmpty) {
        setState(() { _loading = false; _error = AppTranslations.get('Admin email not found'); });
        return;
      }
      if (whatsapp.isEmpty) {
        setState(() { _loading = false; _error = AppTranslations.get('Admin WhatsApp not found'); });
        return;
      }

      final userCred = await auth.signInWithEmailAndPassword(
        email: email,
        password: passwordCtrl.text,
      );
      final authUid = userCred.user!.uid;

      setState(() {
        _loading = false;
        _authenticated = true;
        _uid = authUid;
        _adminWhatsApp = whatsapp;
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = e.code == "wrong-password" || e.code == "invalid-credential"
            ? AppTranslations.get('Wrong password')
            : "${AppTranslations.get('Login failed')}: ${e.message}";
      });
    } catch (e) {
      setState(() { _loading = false; _error = "${AppTranslations.get('Error')}: $e"; });
    }
  }

  Future<void> _requestKey() async {
    setState(() { _requestingKey = true; _error = null; keyCtrl.clear(); });

    try {
      final key = _generateKey();
      final now = DateTime.now();

      await firestore.collection("admin_login_keys").add({
        "admin_uid": _uid,
        "key": key,
        "created_at": Timestamp.fromDate(now),
        "expires_at": Timestamp.fromDate(now.add(const Duration(minutes: 5))),
        "used": false,
      });

      // Invalidate any previous unused keys for this admin
      final oldKeys = await firestore
          .collection("admin_login_keys")
          .where("admin_uid", isEqualTo: _uid)
          .where("used", isEqualTo: false)
          .get();
      for (final doc in oldKeys.docs) {
        if (doc.data()["key"] != key) {
          await doc.reference.update({"used": true});
        }
      }

      final msg = key;
      String cleanPhone = _adminWhatsApp!.replaceAll(RegExp(r'[^0-9]'), '');
      if (!cleanPhone.startsWith("60")) {
        cleanPhone = "60${cleanPhone.replaceFirst(RegExp(r'^0+'), '')}";
      }
      final waUrl = "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(msg)}";

      if (await canLaunchUrl(Uri.parse(waUrl))) {
        await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
      } else {
        setState(() {
          _error = "${AppTranslations.get('Cannot open WhatsApp')}. ${AppTranslations.get('Key')}: $key";
        });
      }

      setState(() {
        _requestingKey = false;
        _countdown = 300;
      });
      _startCountdown();
    } catch (e) {
      setState(() { _requestingKey = false; _error = "${AppTranslations.get('Failed to send key')}: $e"; });
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 0) { t.cancel(); return; }
      setState(() => _countdown--);
    });
  }

  Future<void> _verifyKey() async {
    final inputKey = keyCtrl.text.trim();
    if (inputKey.length != 32) {
      setState(() => _error = AppTranslations.get('Key must be 32 characters'));
      return;
    }
    setState(() { _verifyingKey = true; _error = null; });

    try {
      final keys = await firestore
          .collection("admin_login_keys")
          .where("admin_uid", isEqualTo: _uid)
          .where("key", isEqualTo: inputKey)
          .where("used", isEqualTo: false)
          .limit(1)
          .get();

      if (keys.docs.isEmpty) {
        setState(() { _verifyingKey = false; _error = AppTranslations.get('Invalid key or already used. Request a new key.'); });
        return;
      }

      final doc = keys.docs.first;
      final expiresAt = (doc.data()["expires_at"] as Timestamp).toDate();
      if (DateTime.now().isAfter(expiresAt)) {
        await doc.reference.update({"used": true});
        setState(() { _verifyingKey = false; _error = AppTranslations.get('Key has expired. Request a new key.'); });
        return;
      }

      await doc.reference.update({"used": true});

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminMainNav()),
      );
    } catch (e) {
      setState(() { _verifyingKey = false; _error = "${AppTranslations.get('Verification error')}: $e"; });
    }
  }

  String _generateKey() {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    final rand = Random.secure();
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
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
            colors: [Color(0xFF0F766E), Color(0xFF115E59), Color(0xFF065F46), Color(0xFF064E3B)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF14B8A6), Color(0xFF0D9488)]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 6))],
                    ),
                    child: const Icon(Icons.admin_panel_settings, size: 44, color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  Text(AppTranslations.get('Admin Login'), style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text(_authenticated ? AppTranslations.get('Step 2: Verify Key') : AppTranslations.get('Step 1: Account Name & Password'),
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 32),

                  if (!_authenticated) ...[
                    _buildField(accountCtrl, AppTranslations.get('Account Name'), Icons.person, false),
                    const SizedBox(height: 16),
                    _buildField(passwordCtrl, AppTranslations.get('Password'), Icons.lock, true),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: GoogleFonts.poppins(fontSize: 13, color: Colors.orange.shade300)),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF0D7377),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D7377)))
                            : Text(AppTranslations.get('Login'), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppTranslations.get('Back'), style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                    ),
                  ],

                  if (_authenticated) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.security, size: 48, color: Colors.white.withValues(alpha: 0.8)),
                          const SizedBox(height: 12),
                          Text(AppTranslations.get('Two-Factor Authentication'), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                          const SizedBox(height: 8),
                          Text(
                            AppTranslations.get('A login key will be sent to admin WhatsApp. Please enter the key received.'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                          ),
                          const SizedBox(height: 24),

                          if (!_requestingKey && _countdown == 0) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: _requestKey,
                                icon: const Icon(Icons.send_rounded, size: 18),
                                label: Text(AppTranslations.get('Request Login Key'), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],

                          if (_requestingKey) ...[
                            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                            const SizedBox(height: 12),
                            Text(AppTranslations.get('Sending key...'), style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
                          ],

                          if (_countdown > 0) ...[
                            _buildField(keyCtrl, AppTranslations.get('Enter 32-Character Key'), Icons.vpn_key, false),
                            const SizedBox(height: 8),
                            Text("${AppTranslations.get('Key expires in')} ${_countdown ~/ 60}:${(_countdown % 60).toString().padLeft(2, '0')}",
                                style: GoogleFonts.poppins(fontSize: 12, color: _countdown < 60 ? Colors.orange.shade300 : Colors.white70)),
                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(_error!, style: GoogleFonts.poppins(fontSize: 13, color: Colors.orange.shade300)),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _verifyingKey ? null : _verifyKey,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF14C38E),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                child: _verifyingKey
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : Text(AppTranslations.get('Verify Key'), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _requestKey,
                              child: Text(AppTranslations.get('Resend Key'), style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
                            ),
                          ],

                          if (_countdown == 0 && !_requestingKey && _error != null && _authenticated) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _requestKey,
                              child: Text(AppTranslations.get('Request new key'), style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, bool obscure) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white60, size: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF14C38E))),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
