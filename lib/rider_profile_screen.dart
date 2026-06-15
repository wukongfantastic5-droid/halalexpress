import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:typed_data';
import 'translations.dart';

class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;
  final storage = FirebaseStorage.instance;
  final picker = ImagePicker();

  Map<String, dynamic>? _riderData;
  Map<String, dynamic>? _userData;
  bool _loading = true;
  double _avgRating = 0;
  int _ratingCount = 0;

  @override
  void initState() {
    super.initState();
    AppTranslations.languageNotifier.addListener(_onLangChange);
    _loadData();
  }

  @override
  void dispose() {
    AppTranslations.languageNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final riderDoc = await firestore.collection("riders").doc(uid).get();
      final userDoc = await firestore.collection("users").doc(uid).get();
      final ratingSnap = await firestore
          .collection("ratings")
          .where("rider_uid", isEqualTo: uid)
          .get();
      double total = 0;
      for (final doc in ratingSnap.docs) {
        total += (doc.data()["rating"] ?? 0).toDouble();
      }
      if (mounted) {
        setState(() {
          _riderData = riderDoc.data();
          _userData = userDoc.data();
          _avgRating = ratingSnap.docs.isNotEmpty ? total / ratingSnap.docs.length : 0;
          _ratingCount = ratingSnap.docs.length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── 1. NAMA (instant) ──────────────────────────────────────────
  Future<void> _editName() async {
    final ctrl = TextEditingController(text: _riderData?["full_name"] ?? "");
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('Change Name'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          style: GoogleFonts.poppins(fontSize: 14),
          decoration: InputDecoration(
            labelText: AppTranslations.get('Full Name'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppTranslations.get('Save'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (result != true || ctrl.text.trim().isEmpty) return;
    final name = ctrl.text.trim();
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await firestore.collection("users").doc(uid).update({"full_name": name});
      await firestore.collection("riders").doc(uid).update({"full_name": name});
      if (mounted) {
        setState(() {
          _riderData?["full_name"] = name;
          _userData?["full_name"] = name;
        });
        _showSnack(AppTranslations.get('Name updated'));
      }
    } catch (e) {
      _showSnack("Ralat: $e");
    }
  }

  // ─── 2. EMAIL (verify current email first) ──────────────────────
  Future<void> _editEmail() async {
    final currentEmail = _userData?["email"] ?? "";
    final ctrl = TextEditingController(text: currentEmail);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('Change Email'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${AppTranslations.get('Current email')}: $currentEmail", style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.poppins(fontSize: 14),
              decoration: InputDecoration(
                labelText: "Email Baru",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "Pengesahan akan dihantar ke email semasa anda.",
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange.shade700),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppTranslations.get('Send Verification'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (result != true || ctrl.text.trim().isEmpty) return;
  final user = auth.currentUser;
    if (user == null) return;

    try {
      await user.sendEmailVerification();
      if (mounted) {
        _showSnack("Email pengesahan telah dihantar ke $currentEmail. Sila sahkan sebelum menukar email.");
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("Pengesahan Email", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: Text(
              "Email pengesahan telah dihantar ke $currentEmail.\n\nSila sahkan email anda, kemudian log masuk semula untuk menggunakan email baru.",
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppTranslations.get('OK'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600))),
            ],
          ),
        );
      }
    } catch (e) {
      _showSnack("Ralat: $e");
    }
  }

  // ─── 3. MOTORSIKAL (upload new photos) ──────────────────────────
  Future<void> _editMotor() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _MotorEditDialog(
        currentData: _riderData,
        onSaved: (updated) {
          if (mounted) {
            setState(() {
              if (updated["rider_photo"] != null) _riderData?["rider_photo"] = updated["rider_photo"];
              if (updated["motorcycle_photo"] != null) _riderData?["motorcycle_photo"] = updated["motorcycle_photo"];
              if (updated["insurance"] != null) _riderData?["insurance"] = updated["insurance"];
              if (updated["road_tax"] != null) _riderData?["road_tax"] = updated["road_tax"];
              if (updated["license_front"] != null) _riderData?["license_front"] = updated["license_front"];
              if (updated["license_back"] != null) _riderData?["license_back"] = updated["license_back"];
            });
          }
        },
      ),
    );
  }

  // ─── 4. KATA LALUAN (reset email) ───────────────────────────────
  Future<void> _editPassword() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Tukar Kata Laluan", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          "Email pengesahan untuk menukar kata laluan akan dihantar ke ${_userData?["email"] ?? "email anda"}.\n\nSila ikut arahan dalam email tersebut.",
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppTranslations.get('Send'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await auth.sendPasswordResetEmail(email: _userData?["email"] ?? "");
      if (mounted) {
        _showSnack("Email set semula kata laluan telah dihantar");
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text("Email Dihantar", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: Text(
              "Sila periksa inbox ${_userData?["email"]} dan ikut arahan dalam email untuk menetapkan semula kata laluan.",
              style: GoogleFonts.poppins(fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppTranslations.get('OK'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600))),
            ],
          ),
        );
      }
    } catch (e) {
      _showSnack("Ralat: $e");
    }
  }

  // ─── 5. BANK (admin verification 1-3 days) ──────────────────────
  Future<void> _editBank() async {
    final bankTypes = [
      "CIMB Bank", "Maybank", "Bank Islam", "Bank Rakyat",
      "Public Bank", "RHB Bank", "Hong Leong Bank", "AmBank",
      "BSN", "Affin Bank", "OCBC Bank", "Standard Chartered",
    ];
    String selectedBank = _riderData?["bank_type"] ?? bankTypes[0];
    final ctrl = TextEditingController(text: _riderData?["bank_account"] ?? "");

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Tukar Maklumat Bank", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Semasa: ${_riderData?["bank_type"] ?? "-"} - ${_riderData?["bank_account"] ?? "-"}",
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedBank,
                items: bankTypes.map((b) => DropdownMenuItem(value: b, child: Text(b, style: GoogleFonts.poppins(fontSize: 13)))).toList(),
                onChanged: (v) => setDialogState(() => selectedBank = v ?? selectedBank),
                decoration: InputDecoration(
                  labelText: AppTranslations.get('Select Bank'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                dropdownColor: Colors.white,
                style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF2E3A46)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: AppTranslations.get('Bank Account Number'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                style: GoogleFonts.poppins(fontSize: 14),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              Text(
                "Permohonan tukar bank akan disahkan dalam 1-3 hari bekerja.",
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.orange.shade700),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppTranslations.get('Send Request'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600))),
          ],
        ),
      ),
    );

    if (result != true || ctrl.text.trim().isEmpty) return;
    final uid = auth.currentUser?.uid;
    final riderName = _riderData?["full_name"] ?? "Rider";
    if (uid == null) return;

    try {
      await firestore.collection("rider_bank_requests").add({
        "rider_id": uid,
        "rider_name": riderName,
        "current_bank_type": _riderData?["bank_type"] ?? "",
        "current_bank_account": _riderData?["bank_account"] ?? "",
        "new_bank_type": selectedBank,
        "new_bank_account": ctrl.text.trim(),
        "status": "pending",
        "created_at": FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _showSnack("Permohonan tukar bank dihantar. Sila tunggu 1-3 hari.");
      }
    } catch (e) {
      _showSnack("Ralat: $e");
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.poppins()), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF0D7377)));
    }

    final name = _riderData?["full_name"] ?? "Rider";
    final email = _userData?["email"] ?? "-";
    final bankType = _riderData?["bank_type"] ?? "-";
    final bankAccount = _riderData?["bank_account"] ?? "-";

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppTranslations.get('Rider Profile'), style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377))),
            const SizedBox(height: 20),

            // ── Profile Card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0D7377), Color(0xFF14C38E)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: const Color(0xFF0D7377).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(name.isNotEmpty ? name[0].toUpperCase() : "?", style: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 12),
                  Text(name, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(email, style: GoogleFonts.poppins(fontSize: 13, color: Colors.white.withOpacity(0.85))),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Rating Display ──
            if (_ratingCount > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F8E9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF0D7377).withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D7377).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.star, color: Color(0xFFFCD34D), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppTranslations.get('Average Rating'),
                            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                _avgRating.toStringAsFixed(1),
                                style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377)),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                children: List.generate(5, (i) {
                                  return Icon(
                                    i < _avgRating.round() ? Icons.star : Icons.star_border,
                                    size: 16,
                                    color: const Color(0xFFFCD34D),
                                  );
                                }),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                "($_ratingCount)",
                                style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),
            _sectionHeader(AppTranslations.get('Full Name'), Icons.person_outline),
            _infoTile(AppTranslations.get('Full Name'), name, _editName, canEdit: true),

            const SizedBox(height: 16),
            _sectionHeader(AppTranslations.get('Email'), Icons.email_outlined),
            _infoTile(AppTranslations.get('Email'), email, _editEmail, canEdit: true),
            _infoTile(AppTranslations.get('Password'), "********", _editPassword, canEdit: true),

            const SizedBox(height: 16),
            _sectionHeader(AppTranslations.get('Motorcycle & Documents'), Icons.motorcycle),
            _docStatus(AppTranslations.get('Selfie Photo'), _riderData?["rider_photo"]),
            _docStatus(AppTranslations.get('License (Front)'), _riderData?["license_front"]),
            _docStatus(AppTranslations.get('License (Back)'), _riderData?["license_back"]),
            _docStatus(AppTranslations.get('Road Tax'), _riderData?["road_tax"]),
            _docStatus(AppTranslations.get('Motorcycle Photo'), _riderData?["motorcycle_photo"]),
            _docStatus(AppTranslations.get('Insurance'), _riderData?["insurance"]),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _editMotor,
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(AppTranslations.get('Update Documents'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D7377),
                  side: const BorderSide(color: Color(0xFF0D7377)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

            const SizedBox(height: 16),
            _sectionHeader(AppTranslations.get('Bank'), Icons.account_balance),
            _infoTile(AppTranslations.get('Bank'), "$bankType - $bankAccount", _editBank, canEdit: true),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0D7377)),
          const SizedBox(width: 8),
          Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF0D7377))),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value, VoidCallback onTap, {bool canEdit = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF2E3A46))),
              ],
            ),
          ),
          if (canEdit)
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D7377).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(AppTranslations.get('Edit'), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF0D7377))),
              ),
            ),
        ],
      ),
    );
  }

  Widget _docStatus(String label, dynamic url) {
    final hasDoc = url != null && url.toString().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(hasDoc ? Icons.check_circle : Icons.hourglass_empty, size: 16, color: hasDoc ? const Color(0xFF14C38E) : Colors.orange),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF2E3A46))),
          const Spacer(),
          Text(hasDoc ? AppTranslations.get('Available') : AppTranslations.get('Needs update'), style: GoogleFonts.poppins(fontSize: 11, color: hasDoc ? const Color(0xFF14C38E) : Colors.orange)),
        ],
      ),
    );
  }
}

// ─── Motor Edit Dialog ──────────────────────────────────────────
class _MotorEditDialog extends StatefulWidget {
  final Map<String, dynamic>? currentData;
  final ValueChanged<Map<String, String>> onSaved;

  const _MotorEditDialog({this.currentData, required this.onSaved});

  @override
  State<_MotorEditDialog> createState() => _MotorEditDialogState();
}

class _MotorEditDialogState extends State<_MotorEditDialog> {
  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance;
  final picker = ImagePicker();
  final uid = FirebaseAuth.instance.currentUser?.uid;

  Uint8List? _riderPhoto;
  Uint8List? _licenseFront;
  Uint8List? _licenseBack;
  Uint8List? _roadTax;
  Uint8List? _motorcyclePhoto;
  Uint8List? _insurance;
  bool _saving = false;

  Future<Uint8List?> _pick() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _btn(Icons.camera_alt, "Kamera", ImageSource.camera),
                _btn(Icons.photo_library, "Galeri", ImageSource.gallery),
              ],
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final x = await picker.pickImage(source: source, imageQuality: 70);
    if (x != null) return await x.readAsBytes();
    return null;
  }

  Widget _btn(IconData icon, String label, ImageSource src) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, src),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFF0D7377).withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Icon(icon, color: const Color(0xFF0D7377)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF0D7377))),
        ]),
      ),
    );
  }

  Widget _imageCard(String label, Uint8List? bytes, VoidCallback onPick) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 56,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bytes != null ? const Color(0xFF14C38E) : Colors.grey.shade300, width: bytes != null ? 2 : 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.horizontal(left: Radius.circular(11)),
              child: bytes != null
                  ? Image.memory(bytes, width: 56, height: 56, fit: BoxFit.cover)
                  : Container(width: 56, height: 56, color: const Color(0xFF0D7377).withOpacity(0.05), child: const Icon(Icons.camera_alt, color: Color(0xFF0D7377))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500))),
            if (bytes != null) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.check_circle, color: Color(0xFF14C38E), size: 18)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (uid == null) return;
    setState(() => _saving = true);

    final uploads = <String, Uint8List>{
      if (_riderPhoto != null) "rider_photo": _riderPhoto!,
      if (_licenseFront != null) "license_front": _licenseFront!,
      if (_licenseBack != null) "license_back": _licenseBack!,
      if (_roadTax != null) "road_tax": _roadTax!,
      if (_motorcyclePhoto != null) "motorcycle_photo": _motorcyclePhoto!,
      if (_insurance != null) "insurance": _insurance!,
    };

    final urls = <String, String>{};
    int idx = 0;
    for (final entry in uploads.entries) {
      try {
        final ref = storage.ref("rider_docs/$uid/${entry.key}.jpg");
        final tempFile = File("${Directory.systemTemp.path}/rider_upload_${idx}_${entry.key}.jpg");
        await tempFile.writeAsBytes(entry.value);
        await ref.putFile(tempFile);
        urls[entry.key] = await ref.getDownloadURL();
        await tempFile.delete();
      } catch (e) {
        urls[entry.key] = "";
      }
      idx++;
    }

    if (urls.isNotEmpty) {
      await firestore.collection("users").doc(uid).set(urls, SetOptions(merge: true));
    }

    if (mounted) {
      setState(() => _saving = false);
      widget.onSaved(urls);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Dokumen dikemas kini", style: GoogleFonts.poppins()), backgroundColor: const Color(0xFF14C38E), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppTranslations.get('Update Documents'), style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377))),
              const SizedBox(height: 4),
              Text(AppTranslations.get('Upload new images to replace'), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 16),
              _imageCard(AppTranslations.get('Selfie Photo'), _riderPhoto, () async { final f = await _pick(); if (f != null) setState(() => _riderPhoto = f); }),
              _imageCard(AppTranslations.get('License (Front)'), _licenseFront, () async { final f = await _pick(); if (f != null) setState(() => _licenseFront = f); }),
              _imageCard(AppTranslations.get('License (Back)'), _licenseBack, () async { final f = await _pick(); if (f != null) setState(() => _licenseBack = f); }),
              _imageCard(AppTranslations.get('Road Tax'), _roadTax, () async { final f = await _pick(); if (f != null) setState(() => _roadTax = f); }),
              _imageCard(AppTranslations.get('Motorcycle Photo (Plate visible)'), _motorcyclePhoto, () async { final f = await _pick(); if (f != null) setState(() => _motorcyclePhoto = f); }),
              _imageCard(AppTranslations.get('Insurance'), _insurance, () async { final f = await _pick(); if (f != null) setState(() => _insurance = f); }),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D7377),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(AppTranslations.get('Save Documents'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppTranslations.get('Close'), style: GoogleFonts.poppins(color: Colors.grey.shade500)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
