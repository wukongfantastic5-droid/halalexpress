import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'translations.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _message = TextEditingController();
  String _selectedType = "Cadangan";
  int _rating = 5;
  bool _loading = false;

  final _types = ["Cadangan", "Aduan", "Pujian", "Lain-lain"];
  final _typeKeys = {
    "Cadangan": "Suggestion",
    "Aduan": "Complaint",
    "Pujian": "Praise",
    "Lain-lain": "Others",
  };
  final _icons = {
    "Cadangan": Icons.lightbulb_outline,
    "Aduan": Icons.report_problem_outlined,
    "Pujian": Icons.thumb_up_outlined,
    "Lain-lain": Icons.more_horiz,
  };

  String _translateType(String type) => AppTranslations.get(_typeKeys[type] ?? type);

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_message.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTranslations.get('Please enter feedback')),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      String userName = "Unknown";
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .get();
        userName = doc["full_name"] ?? user.email ?? "Unknown";
      }

      await FirebaseFirestore.instance.collection("feedback").add({
        "user_uid": user?.uid ?? "",
        "user_name": userName,
        "type": _selectedType,
        "message": _message.text.trim(),
        "rating": _rating,
        "created_at": Timestamp.now(),
      });

      _message.clear();
      setState(() => _loading = false);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 50),
                ),
                const SizedBox(height: 20),
                Text(
                  AppTranslations.get('Thank You!'),
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0D7377),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppTranslations.get('Your feedback has been sent.'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Text(
                              AppTranslations.get('Close'),
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTranslations.get('Failed to send feedback')),
          backgroundColor: Colors.red.shade400,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D7377),
            Color(0xFF14C38E),
            Color(0xFF1A237E),
          ],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            AppTranslations.get('Feedback'),
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.25),
                      Colors.white.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _icons[_selectedType],
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppTranslations.get('Send Feedback'),
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppTranslations.get('Feedback Type'),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedType,
                          isExpanded: true,
                          icon: Icon(
                            Icons.arrow_drop_down_circle_outlined,
                            color: const Color(0xFF0D7377),
                          ),
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: const Color(0xFF0D7377),
                            fontWeight: FontWeight.w500,
                          ),
                          items: _types.map((t) {
                            return DropdownMenuItem(
                              value: t,
                              child: Row(
                                children: [
                                  Icon(
                                    _icons[t]!,
                                    size: 20,
                                    color: const Color(0xFF0D7377),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(_translateType(t)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _selectedType = v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppTranslations.get('Rating'),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (i) {
                          final star = i + 1;
                          return GestureDetector(
                            onTap: () => setState(() => _rating = star),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                                size: 40,
                                color: star <= _rating
                                    ? Colors.amber.shade600
                                    : Colors.grey.shade300,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppTranslations.get('Message'),
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: TextField(
                        controller: _message,
                        maxLines: 6,
                        style: GoogleFonts.poppins(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: AppTranslations.get('Type your feedback or suggestion...'),
                          hintStyle: GoogleFonts.poppins(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0D7377).withOpacity(0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _loading ? null : _submit,
                            borderRadius: BorderRadius.circular(18),
                            child: Center(
                              child: _loading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          AppTranslations.get('Send'),
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
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
}
