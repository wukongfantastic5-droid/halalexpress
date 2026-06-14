import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:installed_apps/installed_apps.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class WalletTopupScreen extends StatefulWidget {
  const WalletTopupScreen({super.key});

  @override
  State<WalletTopupScreen> createState() => _WalletTopupScreenState();
}

class _WalletTopupScreenState extends State<WalletTopupScreen> {
  final firestore = FirebaseFirestore.instance;
  final amountCtrl = TextEditingController();
  double _balance = 0;
  bool _loading = true;
  bool _submitting = false;

  static const _adminWhatsApp = "60123456789";
  static const _adminPhone = "+60-12-345 6789";

  static const _allBanks = [
    {"name": "Touch 'n Go eWallet", "package": "my.com.tngdigital.ewallet", "icon": Icons.phone_android},
    {"name": "MAE (Maybank2U)", "package": "com.maybank2u.life", "icon": Icons.account_balance},
    {"name": "CIMB Octo", "package": "com.cimb.cimbocto", "icon": Icons.account_balance},
    {"name": "BIMB Mobile", "package": "com.bankislam.bimbmobile", "icon": Icons.account_balance},
  ];

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  Future<void> _loadBalance() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) { if (mounted) setState(() => _loading = false); return; }
      final doc = await firestore.collection("users").doc(uid).get();
      if (mounted) {
        setState(() {
          _balance = (doc.data()?["wallet_balance"] ?? 0).toDouble();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatRM(double v) {
    return NumberFormat.currency(locale: "ms_MY", symbol: "RM", decimalDigits: 2).format(v);
  }

  Future<void> _submitRequest() async {
    final amountText = amountCtrl.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _showSnack("Sila masukkan jumlah yang sah");
      return;
    }
    if (amount > 5000) {
      _showSnack("Jumlah maksimum RM5,000 untuk sekali top up");
      return;
    }
    _showBankSelection(amount);
  }

  void _showBankSelection(double amount) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Pilih Bank untuk Bayar",
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377)),
            ),
            const SizedBox(height: 6),
            Text(
              "Jumlah: ${_formatRM(amount)}",
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ..._allBanks.map((bank) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Navigator.pop(ctx);
                    _processPayment(amount, bank["name"] as String);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF0D7377), Color(0xFF14C38E)]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(bank["icon"] as IconData, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            bank["name"] as String,
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF2E3A46)),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _processPayment(double amount, String bankName) async {
    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
      final userDoc = await firestore.collection("users").doc(uid).get();
      final name = userDoc["full_name"] ?? "";
      final whatsapp = userDoc["whatsapp"] ?? "";

      await firestore.collection("topup_requests").add({
        "uid": uid,
        "customer_name": name,
        "customer_whatsapp": whatsapp,
        "amount": amount,
        "status": "pending",
        "bank": bankName,
        "created_at": FieldValue.serverTimestamp(),
      });

      amountCtrl.clear();
      if (mounted) _showQRDialog(amount, bankName);
    } catch (e) {
      _showSnack("Ralat: $e");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showQRDialog(double amount, String bankName) async {
    final qrDoc = await firestore.collection("settings").doc("wallet_qr").get();
    final b64 = qrDoc["image_b64"] as String?;
    final hasQR = b64?.isNotEmpty == true;
    final tngAccount = qrDoc.data()?["tng_account"] as String?;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "Bayar RM${amount.toStringAsFixed(2)}",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "Guna $bankName",
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              if (hasQR)
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                    image: DecorationImage(
                      image: MemoryImage(base64Decode(b64!)),
                      fit: BoxFit.contain,
                    ),
                  ),
                )
              else
                Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 60, color: const Color(0xFF0D7377).withOpacity(0.4)),
                        const SizedBox(height: 6),
                        Text("QR belum dimuat naik", style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade400)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              if (hasQR)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveQRToGallery(b64!),
                    icon: const Icon(Icons.download, size: 18),
                    label: Text("Simpan QR", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D7377),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => _showInstalledBanksSheet(),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text("Buka $bankName", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0D7377),
                    side: const BorderSide(color: Color(0xFF0D7377)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (tngAccount != null && tngAccount.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.phone_android, size: 18, color: const Color(0xFF0D7377)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Akaun TnG E-Wallet",
                              style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tngAccount,
                              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF2E3A46)),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: tngAccount));
                          _showSnack("Nombor akaun disalin");
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D7377),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy, size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                "Salin",
                                style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: const Color(0xFFE65100)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Selepas bayar, WhatsApp bukti bayaran ke $_adminPhone. Admin akan sahkan dalam 1-24 jam.",
                        style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFFBF360C)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveQRToGallery(String b64) async {
    try {
      final Uint8List bytes = base64Decode(b64);
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/qr_tng.png");
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: "QR TnG - BunnyFresh");
    } catch (e) {
      _showSnack("Ralat: $e");
    }
  }

  Future<void> _showInstalledBanksSheet() async {
    final installed = <Map<String, dynamic>>{};
    for (final bank in _allBanks) {
      final isInstalled = await InstalledApps.isAppInstalled(bank["package"] as String);
      if (isInstalled == true) {
        installed.add(bank);
      }
    }
    if (installed.isEmpty) {
      _showSnack("Tiada app bank dijumpai");
      return;
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Pilih App Bank",
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377)),
            ),
            const SizedBox(height: 6),
            Text(
              "Aplikasi bank yang dijumpai",
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            ...installed.map((bank) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Navigator.pop(ctx);
                    InstalledApps.startApp(bank["package"] as String);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF0D7377), Color(0xFF14C38E)]),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(bank["icon"] as IconData, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            bank["name"] as String,
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF2E3A46)),
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.poppins()), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF0D7377)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("Dompet Saya", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377))),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0D7377)))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _balanceCard(),
                  const SizedBox(height: 20),
                  _amountSection(),
                ],
              ),
            ),
    );
  }

  Widget _balanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D7377).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Baki Dompet",
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.white.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatRM(_balance),
            style: GoogleFonts.poppins(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Jumlah Top Up",
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0D7377),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixText: "RM ",
              prefixStyle: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0D7377),
              ),
              hintText: "0.00",
              hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submitRequest,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D7377),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      "Hantar Permohonan",
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: const Color(0xFFE65100)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Selepas bayar, WhatsApp bukti bayaran ke $_adminPhone untuk pengesahan. Admin akan sahkan dalam masa 1-24 jam.",
                    style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFFBF360C)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
