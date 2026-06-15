import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'translations.dart';

class AdminWalletScreen extends StatefulWidget {
  const AdminWalletScreen({super.key});

  @override
  State<AdminWalletScreen> createState() => _AdminWalletScreenState();
}

class _AdminWalletScreenState extends State<AdminWalletScreen> {
  final firestore = FirebaseFirestore.instance;
  final _accountCtrl = TextEditingController();
  bool _accountSaving = false;
  String _filterStatus = "semua";
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    try {
      final doc = await firestore.collection("settings").doc("wallet_qr").get();
      if (doc.exists && doc.data()?["tng_account"] != null) {
        _accountCtrl.text = doc["tng_account"] as String;
      }
    } catch (_) {}
  }

  String _formatRM(double v) {
    return NumberFormat.currency(locale: "ms_MY", symbol: "RM", decimalDigits: 2).format(v);
  }

  Future<void> _approve(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final uid = data["uid"] as String?;
    final amount = (data["amount"] ?? 0).toDouble();
    if (uid == null || amount <= 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('Confirm Top Up'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          "${AppTranslations.get('Confirm top up of amount for user')} ${_formatRM(amount)} untuk ${data["customer_name"] ?? AppTranslations.get('Customer')}?",
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppTranslations.get('Confirm'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await firestore.runTransaction((tx) async {
        final userRef = firestore.collection("users").doc(uid);
        final userDoc = await tx.get(userRef);
        final currentBalance = (userDoc.data()?["wallet_balance"] ?? 0).toDouble();

        tx.update(userRef, {
          "wallet_balance": currentBalance + amount,
        });

        tx.update(doc.reference, {
          "status": "approved",
          "approved_at": FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Top up ${_formatRM(amount)} ${AppTranslations.get('Approved')}", style: GoogleFonts.poppins()),
            backgroundColor: const Color(0xFF14C38E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Ralat: $e", style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _reject(DocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('Reject this top up request?'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(AppTranslations.get('Reject this top up request?'), style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppTranslations.get('Reject'), style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await doc.reference.update({
        "status": "rejected",
        "rejected_at": FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppTranslations.get('Rejected'), style: GoogleFonts.poppins()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ralat: $e", style: GoogleFonts.poppins()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _uploadQR() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512);
    if (picked == null) return;

    try {
      final file = File(picked.path);
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      await firestore.collection("settings").doc("wallet_qr").set({
        "image_b64": b64,
        "updated_at": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("QR berjaya dimuat naik", style: GoogleFonts.poppins()),
            backgroundColor: const Color(0xFF14C38E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ralat: $e", style: GoogleFonts.poppins()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // QR MANAGEMENT CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "QR TnG Anda",
                        style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF0D7377)),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: _uploadQR,
                          icon: const Icon(Icons.upload_file, size: 16),
                          label: Text(AppTranslations.get('Upload Receipt'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D7377),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: firestore.collection("settings").doc("wallet_qr").snapshots(),
                      builder: (context, snap) {
                        final hasQR = snap.hasData && snap.data!.exists && (snap.data!["image_b64"] as String?)?.isNotEmpty == true;
                        final b64 = snap.data?["image_b64"] as String?;
                        return Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            image: hasQR
                                ? DecorationImage(
                                    image: MemoryImage(base64Decode(b64!)),
                                    fit: BoxFit.contain,
                                  )
                                : null,
                          ),
                  child: hasQR
                      ? null
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.qr_code_2_rounded, size: 50, color: const Color(0xFF0D7377).withOpacity(0.4)),
                              const SizedBox(height: 4),
                              Text("Belum ada QR", style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade400)),
                            ],
                          ),
                        ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _accountCtrl,
              decoration: InputDecoration(
                labelText: AppTranslations.get('Bank Account Number'),
                labelStyle: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF0D7377)),
                hintText: "019-1234567",
                hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
                prefixIcon: const Icon(Icons.phone_android, size: 20, color: Color(0xFF0D7377)),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              style: GoogleFonts.poppins(fontSize: 14),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _accountSaving ? null : _saveAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D7377),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _accountSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(AppTranslations.get('Save Account Number'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _manualAdjustCard(),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  AppTranslations.get('Confirm Top Up'),
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0D7377),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: _exporting ? null : _exportTopup,
                    icon: _exporting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.download, size: 16),
                    label: Text("Export", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D7377),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(AppTranslations.get('All'), "semua"),
                  const SizedBox(width: 8),
                  _filterChip(AppTranslations.get('Pending'), "pending"),
                  const SizedBox(width: 8),
                  _filterChip(AppTranslations.get('Approved'), "approved"),
                  const SizedBox(width: 8),
                  _filterChip(AppTranslations.get('Rejected'), "rejected"),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: firestore
                  .collection("topup_requests")
                  .orderBy("created_at", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    "Ralat: ${snapshot.error}",
                    style: GoogleFonts.poppins(fontSize: 13, color: Colors.red),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF0D7377)));
                }

                final allDocs = snapshot.data!.docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final status = d["status"] ?? "pending";
                  if (_filterStatus == "semua") return true;
                  return status == _filterStatus;
                }).toList();

                final pendingFiltered = allDocs.where((d) {
                  final s = (d.data() as Map<String, dynamic>)["status"] ?? "pending";
                  return s == "pending";
                }).toList();

                final historyFiltered = allDocs.where((d) {
                  final s = (d.data() as Map<String, dynamic>)["status"] ?? "pending";
                  return s != "pending";
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  _filterStatus == "semua"
                      ? "${allDocs.length} permohonan"
                      : _filterStatus == "pending"
                          ? "${pendingFiltered.length} permohonan menunggu"
                          : _filterStatus == "approved"
                              ? "${historyFiltered.length} permohonan disahkan"
                              : "${historyFiltered.length} permohonan ditolak",
                  style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                if (allDocs.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          AppTranslations.get('No requests'),
                          style: GoogleFonts.poppins(fontSize: 15, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                else ...[
                  if (pendingFiltered.isNotEmpty)
                    ...pendingFiltered.map((doc) => _requestCard(doc, false)),
                  if (historyFiltered.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                      Text(
                        AppTranslations.get('History'),
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0D7377),
                        ),
                      ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...historyFiltered.map((doc) => _requestCard(doc, true)),
                  ],
                ],
              ],
            );
            },
          ),
            const SizedBox(height: 32),
            _withdrawalSection(),
        ],
      ),
    ),
    );
  }

  Widget _withdrawalSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection("withdraw_requests")
          .orderBy("created_at", descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D7377))));
        }

        final pending = snap.data!.docs.where((d) => (d.data() as Map<String, dynamic>)["status"] == "pending").toList();
        final history = snap.data!.docs.where((d) => (d.data() as Map<String, dynamic>)["status"] != "pending").toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  AppTranslations.get('Rider Withdrawals'),
                  style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377)),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "${pending.length} ${AppTranslations.get('Pending')}",
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            if (pending.isEmpty && history.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text(AppTranslations.get('No withdrawal requests'), style: GoogleFonts.poppins(fontSize: 15, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            if (pending.isNotEmpty) ...[
              ...pending.map((doc) => _withdrawCard(doc, false)),
            ],
            if (history.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(AppTranslations.get('History'), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF0D7377))),
              const SizedBox(height: 8),
              ...history.map((doc) => _withdrawCard(doc, true)),
            ],
          ],
        );
      },
    );
  }

  Widget _withdrawCard(DocumentSnapshot doc, bool isHistory) {
    final data = doc.data() as Map<String, dynamic>;
    final amount = (data["amount"] ?? 0).toDouble();
    final status = data["status"] ?? "pending";
    final createdAt = data["created_at"] as Timestamp?;
    final riderName = data["rider_name"] ?? AppTranslations.get('Rider');
    final bankType = data["bank_type"] ?? "-";
    final bankAccount = data["bank_account"] ?? "-";

    final dateStr = createdAt != null ? DateFormat("dd/MM/yyyy HH:mm").format(createdAt.toDate()) : "-";

    Color statusColor;
    String statusText;
    switch (status) {
      case "approved":
        statusColor = const Color(0xFF14C38E);
        statusText = AppTranslations.get('Approved');
        break;
      case "rejected":
        statusColor = Colors.red;
        statusText = AppTranslations.get('Rejected');
        break;
      default:
        statusColor = const Color(0xFFFFA000);
        statusText = AppTranslations.get('Pending');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(riderName, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF2E3A46))),
                    const SizedBox(height: 2),
                    Text("$bankType - $bankAccount", style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(statusText, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(_formatRM(amount), style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377))),
              const Spacer(),
              Text(dateStr, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
          if (!isHistory) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _approveWithdraw(doc),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14C38E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(AppTranslations.get('Confirm'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _rejectWithdraw(doc),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(AppTranslations.get('Reject'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _approveWithdraw(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final amount = (data["amount"] ?? 0).toDouble();
    final riderId = data["rider_id"] as String?;
    if (riderId == null || amount <= 0) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('Confirm Withdrawal'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          "${AppTranslations.get('Confirm withdrawal for rider')} ${_formatRM(amount)} untuk ${data["rider_name"] ?? AppTranslations.get('Rider')}?",
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppTranslations.get('Confirm'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await firestore.runTransaction((tx) async {
        tx.update(doc.reference, {
          "status": "approved",
          "approved_at": FieldValue.serverTimestamp(),
        });

        final riderRef = firestore.collection("riders").doc(riderId);
        final riderDoc = await tx.get(riderRef);
        final curBalance = (riderDoc.data()?["wallet_balance"] ?? 0).toDouble();
        tx.update(riderRef, {
          "wallet_balance": (curBalance - amount).clamp(0, double.infinity),
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppTranslations.get('Withdrawal confirmed'), style: GoogleFonts.poppins()), backgroundColor: const Color(0xFF14C38E), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ralat: $e", style: GoogleFonts.poppins()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _rejectWithdraw(DocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('Reject Withdrawal'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(AppTranslations.get('Reject this withdrawal request?'), style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppTranslations.get('Reject'), style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.w600))),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await doc.reference.update({
        "status": "rejected",
        "rejected_at": FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppTranslations.get('Rejected'), style: GoogleFonts.poppins()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ralat: $e", style: GoogleFonts.poppins()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Widget _filterChip(String label, String value) {
    final selected = _filterStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0D7377) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF2E3A46),
          ),
        ),
      ),
    );
  }

  Future<void> _exportTopup() async {
    setState(() => _exporting = true);
    try {
      final snap = await firestore.collection("topup_requests").orderBy("created_at", descending: true).get();

      final excel = Excel.createExcel();
      final sheet = excel.sheets[excel.getDefaultSheet()!]!;

      final headerStyle = CellStyle(
        backgroundColorHex: ExcelColor.fromHexString("0D7377"),
        fontColorHex: ExcelColor.white,
        fontFamily: getFontFamily(FontFamily.Calibri),
        bold: true,
        fontSize: 14,
      );
      final bodyStyle = CellStyle(
        fontFamily: getFontFamily(FontFamily.Calibri),
        fontSize: 12,
      );

      final headers = [AppTranslations.get('Customer'), AppTranslations.get('WhatsApp Number'), AppTranslations.get('Total'), AppTranslations.get('Bank'), AppTranslations.get('Status'), AppTranslations.get('Date Applied'), AppTranslations.get('Date Resolved')];
      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      int row = 1;
      for (final doc in snap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        final created = (d["created_at"] as Timestamp?)?.toDate();
        final resolved = (d["approved_at"] as Timestamp?)?.toDate() ?? (d["rejected_at"] as Timestamp?)?.toDate();

        final statusMap = {
          "pending": AppTranslations.get('Pending'),
          "approved": AppTranslations.get('Approved'),
          "rejected": AppTranslations.get('Rejected'),
        };

        final values = [
          d["customer_name"] ?? AppTranslations.get('Customer'),
          d["customer_whatsapp"] ?? "-",
          "RM ${(d["amount"] ?? 0).toStringAsFixed(2)}",
          d["bank"] ?? "-",
          statusMap[d["status"]] ?? d["status"] ?? AppTranslations.get('Pending'),
          created != null ? DateFormat("dd/MM/yyyy HH:mm").format(created) : "-",
          resolved != null ? DateFormat("dd/MM/yyyy HH:mm").format(resolved) : "-",
        ];

        for (var i = 0; i < values.length; i++) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
          cell.value = TextCellValue(values[i].toString());
          cell.cellStyle = bodyStyle;
        }

        if (d["status"] == "approved") {
          for (var i = 0; i < values.length; i++) {
            final c = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
            c.cellStyle = bodyStyle.copyWith(backgroundColorHexVal: ExcelColor.fromHexString("E8F5E9"));
          }
        } else if (d["status"] == "rejected") {
          for (var i = 0; i < values.length; i++) {
            final c = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
            c.cellStyle = bodyStyle.copyWith(backgroundColorHexVal: ExcelColor.fromHexString("FFEBEE"));
          }
        }

        row++;
      }

      // auto width
      for (var i = 0; i < headers.length; i++) {
        sheet.setColumnWidth(i, 22);
      }

      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/topup_requests.xlsx");
      final bytes = excel.save();
      if (bytes == null) throw Exception(AppTranslations.get('Failed'));
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(file.path)], text: "Top Up Requests");
    } catch (e) {
      if (mounted) _showSnack("Ralat export: $e");
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _requestCard(DocumentSnapshot doc, bool isHistory) {
    final data = doc.data() as Map<String, dynamic>;
    final amount = (data["amount"] ?? 0).toDouble();
    final status = data["status"] ?? "pending";
    final createdAt = data["created_at"] as Timestamp?;

    final dateStr = createdAt != null
        ? DateFormat("dd/MM/yyyy HH:mm").format(createdAt.toDate())
        : "-";

    Color statusColor;
    String statusText;
    switch (status) {
      case "approved":
        statusColor = const Color(0xFF14C38E);
        statusText = AppTranslations.get('Approved');
        break;
      case "rejected":
        statusColor = Colors.red;
        statusText = AppTranslations.get('Rejected');
        break;
      default:
        statusColor = const Color(0xFFFFA000);
        statusText = AppTranslations.get('Pending');
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data["customer_name"] ?? AppTranslations.get('Customer'),
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2E3A46),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatRM(amount),
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0D7377),
                ),
              ),
              if (data["customer_whatsapp"] != null && data["customer_whatsapp"].toString().isNotEmpty)
                Text(
                  data["customer_whatsapp"].toString(),
                  style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          if (!isHistory) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _approve(doc),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14C38E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        AppTranslations.get('Confirm'),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _reject(doc),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        AppTranslations.get('Reject'),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _manualAdjustCard() {
    final searchCtrl = TextEditingController();
    return StatefulBuilder(
      builder: (context, setInnerState) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.swap_vertical_circle, size: 20, color: const Color(0xFF0D7377)),
                  const SizedBox(width: 8),
                  Text(
                    AppTranslations.get('My Wallet'),
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF0D7377)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: searchCtrl,
                decoration: InputDecoration(
                  hintText: AppTranslations.get('Search user...'),
                  hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF0D7377)),
                  suffixIcon: searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            searchCtrl.clear();
                            setInnerState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                style: GoogleFonts.poppins(fontSize: 13),
                onChanged: (_) => setInnerState(() {}),
              ),
              if (searchCtrl.text.trim().length >= 2)
                StreamBuilder<QuerySnapshot>(
                  stream: firestore
                      .collection("users")
                      .orderBy("full_name")
                      .startAt([searchCtrl.text.trim().toLowerCase()])
                      .endAt([searchCtrl.text.trim().toLowerCase() + '\uf8ff'])
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D7377)))),
                      );
                    }
                    final users = snap.data!.docs.where((d) {
                      final name = (d["full_name"] as String? ?? "").toLowerCase();
                      return name.contains(searchCtrl.text.trim().toLowerCase());
                    }).toList();
                    if (users.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(AppTranslations.get('No users found'), style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                      );
                    }
                    return Column(
                      children: users.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final name = data["full_name"] ?? AppTranslations.get('Customer');
                        final bal = (data["wallet_balance"] ?? 0).toDouble();
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(name, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF2E3A46))),
                                      const SizedBox(height: 2),
                                      Text(_formatRM(bal), style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377))),
                                    ],
                                  ),
                                ),
                                _adjustButton(doc.id, name, "+", true),
                                const SizedBox(width: 6),
                                _adjustButton(doc.id, name, "-", false),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _adjustButton(String uid, String name, String label, bool isAdd) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: () => _showAdjustDialog(uid, name, isAdd),
        style: ElevatedButton.styleFrom(
          backgroundColor: isAdd ? const Color(0xFF14C38E) : Colors.red.shade400,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
    );
  }

  Future<void> _showAdjustDialog(String uid, String name, bool isAdd) async {
    final ctrl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isAdd ? "Tambah Baki" : "Kurangkan Baki",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF0D7377)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: "RM ",
                prefixStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF0D7377)),
                hintText: "0.00",
                hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400),
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              Navigator.pop(ctx, v);
            },
            child: Text(
              isAdd ? "Tambah" : "Kurangkan",
              style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (amount == null || amount <= 0) return;
    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('Confirm'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          isAdd
              ? "Tambah ${_formatRM(amount)} untuk $name?"
              : "Kurangkan ${_formatRM(amount)} dari $name?",
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppTranslations.get('Yes'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await firestore.runTransaction((tx) async {
        final ref = firestore.collection("users").doc(uid);
        final doc = await tx.get(ref);
        final cur = (doc.data()?["wallet_balance"] ?? 0).toDouble();
        final newBal = isAdd ? cur + amount : (cur - amount).clamp(0, double.infinity);
        tx.update(ref, {"wallet_balance": newBal});
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${isAdd ? "Tambah" : "Kurangkan"} ${_formatRM(amount)} berjaya", style: GoogleFonts.poppins()),
            backgroundColor: const Color(0xFF14C38E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ralat: $e", style: GoogleFonts.poppins()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAccount() async {
    final account = _accountCtrl.text.trim();
    if (account.isEmpty) {
      _showSnack("Sila masukkan nombor akaun TnG");
      return;
    }
    setState(() => _accountSaving = true);
    try {
      await firestore.collection("settings").doc("wallet_qr").set({
        "tng_account": account,
        "updated_at": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) _showSnack("Nombor akaun disimpan");
    } catch (e) {
      if (mounted) _showSnack("Ralat: $e");
    } finally {
      if (mounted) setState(() => _accountSaving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: GoogleFonts.poppins()), behavior: SnackBarBehavior.floating),
    );
  }

} 

