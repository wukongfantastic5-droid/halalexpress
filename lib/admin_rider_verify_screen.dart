import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminRiderVerifyScreen extends StatelessWidget {
  final firestore = FirebaseFirestore.instance;

  AdminRiderVerifyScreen({super.key});

  Future<void> _updateStatus(BuildContext context, String uid, String status) async {
    try {
      await firestore.collection("users").doc(uid).update({
        "rider_verified": status == "approved",
        "verification_status": status,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == "approved" ? "Rider diluluskan" : "Rider ditolak"),
          backgroundColor: status == "approved" ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      debugPrint("VERIFY ERROR: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Ralat: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection("users")
          .where("role", isEqualTo: "rider")
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text("Ralat: ${snapshot.error}", style: GoogleFonts.poppins(color: Colors.red)),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        docs.sort((a, b) {
          final aTime = (a.data() as Map)["created_at"];
          final bTime = (b.data() as Map)["created_at"];
          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }
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
          padding: const EdgeInsets.all(16),
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
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                          ),
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
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: status == "approved"
                                ? Colors.green
                                : status == "rejected"
                                    ? Colors.red
                                    : Colors.orange,
                          ),
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
