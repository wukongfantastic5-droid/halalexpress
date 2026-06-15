import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'translations.dart';

class RiderWalletScreen extends StatefulWidget {
  const RiderWalletScreen({super.key});

  @override
  State<RiderWalletScreen> createState() => _RiderWalletScreenState();
}

class _RiderWalletScreenState extends State<RiderWalletScreen> {
  final firestore = FirebaseFirestore.instance;
  final uid = FirebaseAuth.instance.currentUser?.uid ?? "";

  String _formatRM(double v) {
    return NumberFormat.currency(locale: "ms_MY", symbol: "RM", decimalDigits: 2).format(v);
  }

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return const Center(child: Text("Not logged in"));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _balanceCard(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _actionButton(AppTranslations.get('Withdrawal'), Icons.arrow_upward, _showWithdrawDialog)),
            ],
          ),
          const SizedBox(height: 24),
          _withdrawalHistory(),
        ],
      ),
    );
  }

  Widget _balanceCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: firestore.collection("riders").doc(uid).snapshots(),
      builder: (context, snap) {
        final bal = (snap.data?.data() as Map<String, dynamic>?)?["wallet_balance"] ?? 0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: const Color(0xFF0D7377).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Column(
            children: [
              Text(AppTranslations.get('Wallet Balance'), style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 8),
              Text(
                _formatRM((bal as num).toDouble()),
                style: GoogleFonts.poppins(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0D7377),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  void _showWithdrawDialog() async {
    final riderDoc = await firestore.collection("riders").doc(uid).get();
    final riderData = riderDoc.data();
    final balance = (riderData?["wallet_balance"] ?? 0).toDouble();
    final bankType = riderData?["bank_type"] ?? "";
    final bankAccount = riderData?["bank_account"] ?? "";

    if (bankType.isEmpty || bankAccount.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppTranslations.get('Bank info incomplete. Contact admin.'), style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final ctrl = TextEditingController();
    if (!mounted) return;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(AppTranslations.get('Withdrawal'), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: const Color(0xFF0D7377))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Baki: ${_formatRM(balance)}", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF0D7377))),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance, size: 16, color: const Color(0xFF0D7377)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "$bankType - $bankAccount",
                      style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF2E3A46)),
                    ),
                  ),
                ],
              ),
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
            const SizedBox(height: 12),
            Text(
              AppTranslations.get('Withdrawal will be processed in 1-3 business days.'),
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500),
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
            child: Text(AppTranslations.get('Submit Withdrawal'), style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (result == null || result <= 0 || result > balance) {
      if (result != null && result > balance && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppTranslations.get('Insufficient balance'), style: GoogleFonts.poppins()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }

    final riderName = riderData?["full_name"] ?? "Rider";

    try {
      await firestore.collection("withdraw_requests").add({
        "rider_id": uid,
        "rider_name": riderName,
        "amount": result,
        "bank_type": bankType,
        "bank_account": bankAccount,
        "status": "pending",
        "created_at": FieldValue.serverTimestamp(),
        "notes": "Pengeluaran diproses dalam 1-3 hari bekerja",
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Permohonan pengeluaran dihantar", style: GoogleFonts.poppins()),
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

  Widget _withdrawalHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection("withdraw_requests")
          .where("rider_id", isEqualTo: uid)
          .orderBy("created_at", descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D7377)));
        }

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(AppTranslations.get('No withdrawals'), style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppTranslations.get('Previous Withdrawals'), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF0D7377))),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final amount = (d["amount"] ?? 0).toDouble();
              final status = d["status"] ?? "pending";
              final createdAt = d["created_at"] as Timestamp?;
              final approvedAt = d["approved_at"] as Timestamp?;
              final rejectedAt = d["rejected_at"] as Timestamp?;

              final dateStr = createdAt != null ? DateFormat("dd/MM/yyyy HH:mm").format(createdAt.toDate()) : "-";
              final resolvedStr = approvedAt != null
                  ? DateFormat("dd/MM/yyyy HH:mm").format(approvedAt.toDate())
                  : rejectedAt != null
                      ? DateFormat("dd/MM/yyyy HH:mm").format(rejectedAt.toDate())
                      : null;

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
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatRM(amount),
                            style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0D7377)),
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
                            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text("${AppTranslations.get('Date:')} $dateStr", style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                    if (resolvedStr != null)
                      Text("Siap: $resolvedStr", style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                    Text("${d["bank_type"] ?? "-"} - ${d["bank_account"] ?? "-"}", style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
