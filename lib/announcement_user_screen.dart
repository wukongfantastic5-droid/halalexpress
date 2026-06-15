import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'translations.dart';

class AnnouncementUserScreen extends StatelessWidget {

  final firestore = FirebaseFirestore.instance;

  AnnouncementUserScreen({super.key});

  String _formatDate(DateTime d) {
    final months = [
      "Jan", "Feb", "Mac", "Apr", "Mei", "Jun",
      "Jul", "Ogos", "Sep", "Okt", "Nov", "Dis"
    ];
    return "${d.day} ${months[d.month - 1]} ${d.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D7377),
            Color(0xFF14C38E),
            Color(0xFF1A237E).withOpacity(0.2),
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            AppTranslations.get('Latest Info'),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection("announcements")
              .orderBy("created_at", descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "Error loading announcements",
                    style: GoogleFonts.poppins(color: Colors.red.shade300),
                  ),
                ),
              );
            }

            if (!snapshot.hasData) {
              return Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }

            final docs = snapshot.data!.docs;

            if (docs.isEmpty) {
              return Center(
                child: Container(
                  padding: EdgeInsets.all(32),
                  margin: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.15),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.campaign_outlined,
                        size: 64,
                        color: Colors.white.withOpacity(0.4),
                      ),
                      SizedBox(height: 16),
                      Text(
                        "No latest info",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
              itemCount: docs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 16),
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.2),
                          Colors.white.withOpacity(0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.campaign_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppTranslations.get('Announcements'),
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "${docs.length} latest info",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final data = docs[index - 1].data() as Map<String, dynamic>;
                final time = (data["created_at"] as Timestamp?)?.toDate();
                final isRecent = time != null &&
                    DateTime.now().difference(time).inDays < 3;

                return AnimatedContainer(
                  duration: Duration(milliseconds: 400),
                  margin: EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isRecent
                          ? Color(0xFF14C38E).withOpacity(0.4)
                          : Colors.white.withOpacity(0.15),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 15,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isRecent
                                    ? Color(0xFF14C38E).withOpacity(0.2)
                                    : Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                isRecent ? Icons.new_releases_rounded : Icons.campaign_outlined,
                                color: isRecent ? Color(0xFF14C38E) : Colors.white.withOpacity(0.8),
                                size: 22,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data["title"] ?? "",
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    data["message"] ?? "",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: Colors.white.withOpacity(0.85),
                                    ),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (isRecent)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Color(0xFF14C38E).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Color(0xFF14C38E).withOpacity(0.3),
                                  ),
                                ),
                                child: Text(
                                  "BARU",
                                  style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF14C38E),
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (time != null) ...[
                          SizedBox(height: 12),
                          Divider(color: Colors.white.withOpacity(0.1), height: 1),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 13,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              SizedBox(width: 6),
                              Text(
                                _formatDate(time),
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
