import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminRiderVerifyScreen extends StatefulWidget {
  AdminRiderVerifyScreen({super.key});

  @override
  State<AdminRiderVerifyScreen> createState() => _AdminRiderVerifyScreenState();
}

class _AdminRiderVerifyScreenState extends State<AdminRiderVerifyScreen> {
  final firestore = FirebaseFirestore.instance;
  int _tabIndex = 0;

  Future<void> _updateStatus(BuildContext context, String uid, String status) async {
    try {
      await firestore.collection("users").doc(uid).update({
        "rider_verified": status == "approved",
        "verification_status": status,
      });

      if (status == "approved") {
        final userDoc = await firestore.collection("users").doc(uid).get();
        final fullName = userDoc["full_name"] ?? "";
        final whatsapp = userDoc["whatsapp"] ?? "";
        await firestore.collection("riders").doc(uid).set({
          "full_name": fullName,
          "whatsapp": whatsapp,
          "rider_verified": true,
        });
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == "approved" ? "Rider diluluskan" : "Rider ditolak"),
          backgroundColor: status == "approved" ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ralat: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // ─── Bank Request Approval ──────────────────────────────
  Future<void> _approveBankRequest(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final riderId = data["rider_id"] as String?;
    final newBankType = data["new_bank_type"] as String?;
    final newBankAccount = data["new_bank_account"] as String?;
    if (riderId == null || newBankType == null || newBankAccount == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Sahkan Tukar Bank", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          "Tukar bank rider kepada:\n$newBankType - $newBankAccount?",
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Batal", style: GoogleFonts.poppins(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Sahkan", style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600))),
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
        tx.update(firestore.collection("riders").doc(riderId), {
          "bank_type": newBankType,
          "bank_account": newBankAccount,
        });
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Tukar bank diluluskan", style: GoogleFonts.poppins()), backgroundColor: const Color(0xFF14C38E), behavior: SnackBarBehavior.floating),
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

  Future<void> _rejectBankRequest(DocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Tolak Tukar Bank", style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text("Tolak permohonan tukar bank ini?", style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Batal", style: GoogleFonts.poppins(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Tolak", style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.w600))),
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
          SnackBar(content: Text("Permohonan ditolak", style: GoogleFonts.poppins()), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
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
    return Column(
      children: [
        // Tab selector
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              _tabBtn("Pengesahan Rider", 0),
              _tabBtn("Tukar Bank Rider", 1),
            ],
          ),
        ),
        Expanded(
          child: _tabIndex == 0 ? _riderVerificationList() : _bankRequestList(),
        ),
      ],
    );
  }

  Widget _tabBtn(String label, int i) {
    final selected = _tabIndex == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? const Color(0xFF0D7377) : Colors.grey.shade600),
          ),
        ),
      ),
    );
  }

  // ─── Tab 1: Rider Verification List ─────────────────────
  Widget _riderVerificationList() {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection("users").where("role", isEqualTo: "rider").snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("Ralat: ${snapshot.error}", style: GoogleFonts.poppins(color: Colors.red)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs.toList();
        docs.sort((a, b) {
          final aTime = (a.data() as Map)["created_at"];
          final bTime = (b.data() as Map)["created_at"];
          if (aTime is Timestamp && bTime is Timestamp) return bTime.compareTo(aTime);
          return 0;
        });

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.motorcycle, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text("Tiada rider", style: GoogleFonts.poppins(color: Colors.grey.shade500)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final d = docs[index].data() as Map<String, dynamic>;
            final uid = docs[index].id;
            final status = d["verification_status"] ?? "pending";

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF0D7377), Color(0xFF14C38E)]),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d["full_name"] ?? "", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
                            Text(d["email"] ?? "", style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: status == "approved"
                              ? Colors.green.withOpacity(0.1)
                              : status == "rejected"
                                  ? Colors.red.withOpacity(0.1)
                                  : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          status == "approved" ? "Diluluskan" : status == "rejected" ? "Ditolak" : "Menunggu",
                          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600,
                            color: status == "approved" ? Colors.green : status == "rejected" ? Colors.red : Colors.orange),
                        ),
                      ),
                    ],
                  ),
                  if (d["rider_photo"] != null && (d["rider_photo"] as String).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _docImage("Gambar Diri", d["rider_photo"] ?? ""),
                          _docImage("Lesen Depan", d["license_front"] ?? ""),
                          _docImage("Lesen Belakang", d["license_back"] ?? ""),
                          _docImage("Cukai Jalan", d["road_tax"] ?? ""),
                          _docImage("Motor", d["motorcycle_photo"] ?? ""),
                          _docImage("Insurans", d["insurance"] ?? ""),
                        ],
                      ),
                    ),
                  ],
                  if (status == "pending") ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _updateStatus(context, uid, "approved"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text("Luluskan", style: GoogleFonts.poppins(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _updateStatus(context, uid, "rejected"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text("Tolak", style: GoogleFonts.poppins(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ─── Tab 2: Bank Change Requests ─────────────────────────
  Widget _bankRequestList() {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection("rider_bank_requests").orderBy("created_at", descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("Ralat: ${snapshot.error}", style: GoogleFonts.poppins(color: Colors.red)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        final pending = docs.where((d) => (d.data() as Map<String, dynamic>)["status"] == "pending").toList();
        final history = docs.where((d) => (d.data() as Map<String, dynamic>)["status"] != "pending").toList();

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text("Tiada permohonan tukar bank", style: GoogleFonts.poppins(color: Colors.grey.shade500)),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text("${pending.length} permohonan menunggu", style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            if (pending.isNotEmpty) ...[
              ...pending.map((doc) => _bankRequestCard(doc, false)),
              if (history.isNotEmpty) const SizedBox(height: 24),
            ],
            if (history.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.history, size: 16, color: const Color(0xFF0D7377)),
                  const SizedBox(width: 6),
                  Text("Sejarah", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF0D7377))),
                ],
              ),
              const SizedBox(height: 8),
              ...history.map((doc) => _bankRequestCard(doc, true)),
            ],
          ],
        );
      },
    );
  }

  Widget _bankRequestCard(DocumentSnapshot doc, bool isHistory) {
    final data = doc.data() as Map<String, dynamic>;
    final status = data["status"] ?? "pending";
    final createdAt = data["created_at"] as Timestamp?;
    final dateStr = createdAt != null ? DateFormat("dd/MM/yyyy HH:mm").format(createdAt.toDate()) : "-";

    Color statusColor;
    String statusText;
    switch (status) {
      case "approved":
        statusColor = const Color(0xFF14C38E);
        statusText = "Disahkan";
        break;
      case "rejected":
        statusColor = Colors.red;
        statusText = "Ditolak";
        break;
      default:
        statusColor = const Color(0xFFFFA000);
        statusText = "Menunggu";
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
                    Text(data["rider_name"] ?? "Rider", style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: const Color(0xFF2E3A46))),
                    const SizedBox(height: 2),
                    Text(dateStr, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade500)),
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
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Bank Lama: ${data["current_bank_type"] ?? "-"} - ${data["current_bank_account"] ?? "-"}",
                    style: GoogleFonts.poppins(fontSize: 12, color: Colors.red.shade400)),
                const SizedBox(height: 4),
                Text("Bank Baru: ${data["new_bank_type"] ?? "-"} - ${data["new_bank_account"] ?? "-"}",
                    style: GoogleFonts.poppins(fontSize: 12, color: const Color(0xFF14C38E), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (!isHistory) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _approveBankRequest(doc),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF14C38E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text("Sahkan", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => _rejectBankRequest(doc),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade50,
                        foregroundColor: Colors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text("Tolak", style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
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

  Widget _docImage(String label, String url) {
    if (url.isEmpty) return const SizedBox.shrink();
    return Container(
      width: 120,
      margin: const EdgeInsets.only(right: 8),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(url, fit: BoxFit.cover, width: 120),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}
