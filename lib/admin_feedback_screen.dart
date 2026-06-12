import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  final _search = TextEditingController();
  String _selectedType = "Semua";
  String _selectedDate = "Semua";
  bool _showFilters = false;

  final _types = ["Semua", "Cadangan", "Aduan", "Pujian", "Lain-lain"];
  final _dateFilters = ["Semua", "Hari Ini", "Minggu Ini", "Bulan Ini"];
  final _typeIcons = {
    "Cadangan": Icons.lightbulb_outline,
    "Aduan": Icons.report_problem_outlined,
    "Pujian": Icons.thumb_up_outlined,
    "Lain-lain": Icons.more_horiz,
  };
  final _typeColors = {
    "Cadangan": Colors.amber,
    "Aduan": Colors.red,
    "Pujian": Colors.green,
    "Lain-lain": Colors.grey,
  };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DateTime? _dateRangeStart() {
    final now = DateTime.now();
    switch (_selectedDate) {
      case "Hari Ini":
        return DateTime(now.year, now.month, now.day);
      case "Minggu Ini":
        return now.subtract(Duration(days: now.weekday - 1));
      case "Bulan Ini":
        return DateTime(now.year, now.month, 1);
      default:
        return null;
    }
  }

  bool _matchesSearch(Map<String, dynamic> data) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final name = (data["user_name"] ?? "").toString().toLowerCase();
    final msg = (data["message"] ?? "").toString().toLowerCase();
    return name.contains(q) || msg.contains(q);
  }

  String _formatDate(Timestamp t) {
    final d = t.toDate();
    return DateFormat("dd MMM yyyy, HH:mm").format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Maklum Balas",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF0D7377),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _showFilters ? Icons.filter_alt_off : Icons.filter_alt,
              color: Colors.white,
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE8F5E9),
              Color(0xFFF1F8E9),
              Color(0xFFFFFDE7),
            ],
          ),
        ),
        child: Column(
          children: [
            // Search bar
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _search,
                style: GoogleFonts.poppins(fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Cari maklum balas...",
                  hintStyle: GoogleFonts.poppins(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF0D7377)),
                  suffixIcon: _search.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            // Filters
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _showFilters ? 56 : 0,
              child: _showFilters
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF0D7377).withOpacity(0.2),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedType,
                                  isExpanded: true,
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF0D7377)),
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: const Color(0xFF0D7377),
                                  ),
                                  items: _types.map((t) {
                                    return DropdownMenuItem(
                                      value: t,
                                      child: Text(t),
                                    );
                                  }).toList(),
                                  onChanged: (v) {
                                    if (v != null) setState(() => _selectedType = v);
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF0D7377).withOpacity(0.2),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedDate,
                                  isExpanded: true,
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF0D7377)),
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: const Color(0xFF0D7377),
                                  ),
                                  items: _dateFilters.map((d) {
                                    return DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        d,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: const Color(0xFF0D7377),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (v) {
                                    if (v != null) setState(() => _selectedDate = v);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 8),
            // Feedback list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection("feedback")
                    .orderBy("created_at", descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "Ralat: ${snapshot.error}",
                        style: GoogleFonts.poppins(color: Colors.red),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF0D7377)),
                    );
                  }

                  var docs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (_selectedType != "Semua" && data["type"] != _selectedType) {
                      return false;
                    }
                    if (!_matchesSearch(data)) return false;
                    final start = _dateRangeStart();
                    if (start != null) {
                      final t = (data["created_at"] as Timestamp).toDate();
                      if (t.isBefore(start)) return false;
                    }
                    return true;
                  }).toList();

                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.feedback_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Tiada maklum balas",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final type = data["type"] ?? "Lain-lain";
                      final color = _typeColors[type] ?? Colors.grey;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 15,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      _typeIcons[type] ?? Icons.feedback,
                                      color: color,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data["user_name"] ?? "",
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF1F2937),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatDate(data["created_at"] as Timestamp),
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      type,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              Row(
                                children: List.generate(5, (i) {
                                  final rating = data["rating"] ?? 0;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(
                                      i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                      size: 20,
                                      color: i < rating ? Colors.amber.shade600 : Colors.grey.shade300,
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                data["message"] ?? "",
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  height: 1.5,
                                ),
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
