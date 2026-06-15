import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'translations.dart';

class AnnouncementScreen extends StatefulWidget {
  const AnnouncementScreen({super.key});

  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  final titleController = TextEditingController();
  final messageController = TextEditingController();

  final firestore = FirebaseFirestore.instance;

  bool loading = false;
  bool isUnderMaintenance = false;
  bool maintenanceLoading = false;

  @override
  void initState() {
    super.initState();
    checkMaintenanceStatus();
  }

  @override
  void dispose() {
    titleController.dispose();
    messageController.dispose();
    super.dispose();
  }

  Future<void> checkMaintenanceStatus() async {
    try {
      final doc = await firestore
          .collection("settings")
          .doc("app_settings")
          .get();
      if (doc.exists && mounted) {
        setState(() {
          isUnderMaintenance = doc["isUnderMaintenance"] ?? false;
        });
      }
    } catch (e) {
      debugPrint("CHECK MAINTENANCE ERROR: $e");
    }
  }

  Future<void> toggleMaintenance(bool value) async {
    setState(() => maintenanceLoading = true);

    try {
      await firestore
          .collection("settings")
          .doc("app_settings")
          .set({
        "isUnderMaintenance": value,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          isUnderMaintenance = value;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? "App offline (maintenance)"
                  : "App online (active)",
            ),
            backgroundColor: value ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("TOGGLE MAINTENANCE ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to toggle status"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => maintenanceLoading = false);
    }
  }

  Future<void> postAnnouncement() async {
    if (titleController.text.isEmpty || messageController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      await firestore.collection("announcements").add({
        "title": titleController.text.trim(),
        "message": messageController.text.trim(),
        "created_at": Timestamp.now(),
        "type": "admin",
        "pinned": false,
      });

      titleController.clear();
      messageController.clear();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Announcement posted"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("POST ANNOUNCEMENT ERROR: $e");

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to post"),
          backgroundColor: Colors.red,
        ),
      );
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> _confirmDelete(String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Delete Announcement",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: Text(
          "Are you sure you want to delete this announcement?",
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTranslations.get('Cancel'), style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppTranslations.get('Delete'),
              style: GoogleFonts.poppins(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await firestore.collection("announcements").doc(docId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Announcement deleted"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      debugPrint("DELETE ANNOUNCEMENT ERROR: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Failed to delete"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    isUnderMaintenance
                        ? const Color(0xFFF59E0B).withOpacity(0.9)
                        : const Color(0xFF14C38E).withOpacity(0.9),
                    isUnderMaintenance
                        ? const Color(0xFFD97706).withOpacity(0.9)
                        : const Color(0xFF0D7377).withOpacity(0.9),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: (isUnderMaintenance
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF14C38E))
                        .withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          isUnderMaintenance
                              ? Icons.cloud_off
                              : Icons.cloud_done,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUnderMaintenance
                                  ? "Offline (Maintenance)"
                                  : AppTranslations.get('Online (Active)'),
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              isUnderMaintenance
                                  ? AppTranslations.get('Users cannot login')
                                  : AppTranslations.get('Users can login'),
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      maintenanceLoading
                          ? SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Switch(
                              value: isUnderMaintenance,
                              onChanged: toggleMaintenance,
                              activeColor: Colors.white,
                              activeTrackColor: Colors.white.withOpacity(0.4),
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: Colors.white.withOpacity(0.3),
                            ),
                    ],
                  ),
                  if (isUnderMaintenance) ...[
                    const SizedBox(height: 14),
                    Text(
                      AppTranslations.get('Users cannot login until offline mode is turned off.'),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.95),
                    Colors.white.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.campaign,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        "Create Announcement",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0D7377),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: "Title",
                      hintText: "Enter announcement title",
                      hintStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF1F8E9).withOpacity(0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF0D7377),
                          width: 2,
                        ),
                      ),
                      labelStyle: GoogleFonts.poppins(color: Colors.grey.shade600),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: "Latest notification",
                      hintText: "Enter announcement message",
                      hintStyle: GoogleFonts.poppins(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: const Color(0xFFF1F8E9).withOpacity(0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF0D7377),
                          width: 2,
                        ),
                      ),
                      labelStyle: GoogleFonts.poppins(color: Colors.grey.shade600),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                    ),
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : postAnnouncement,
                      child: loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              AppTranslations.get('Send announcement'),
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.history,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  "Announcement History",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0D7377),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot>(
              stream: firestore
                  .collection("announcements")
                  .orderBy("created_at", descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            "Firestore error",
                            style: GoogleFonts.poppins(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF0D7377),
                        ),
                      ),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            AppTranslations.get('No announcements'),
                            style: GoogleFonts.poppins(
                              color: Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final docId = doc.id;

                    final time =
                        (data["created_at"] as Timestamp?)?.toDate();

                    String formattedTime = "";
                    if (time != null) {
                      formattedTime =
                          "${time.day.toString().padLeft(2, '0')}/"
                          "${time.month.toString().padLeft(2, '0')}/"
                          "${time.year} ${time.hour.toString().padLeft(2, '0')}:"
                          "${time.minute.toString().padLeft(2, '0')}";
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.95),
                            Colors.white.withOpacity(0.8),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 15,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.campaign,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  data["title"] ?? "",
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF0D7377),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            data["message"] ?? "",
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              height: 1.5,
                            ),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                formattedTime,
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                              const Spacer(),
                              Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _confirmDelete(docId),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: Colors.red.shade300,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
