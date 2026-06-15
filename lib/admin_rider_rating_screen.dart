import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'translations.dart';

class AdminRiderRatingScreen extends StatefulWidget {
  const AdminRiderRatingScreen({super.key});

  @override
  State<AdminRiderRatingScreen> createState() => _AdminRiderRatingScreenState();
}

class _AdminRiderRatingScreenState extends State<AdminRiderRatingScreen> {
  final firestore = FirebaseFirestore.instance;
  String _searchQuery = "";
  String _sortBy = "rating";

  @override
  void initState() {
    super.initState();
    AppTranslations.languageNotifier.addListener(_onLangChange);
  }

  @override
  void dispose() {
    AppTranslations.languageNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSearchBar(),
        _buildSortButtons(),
        Expanded(child: _buildRiderList()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
           hintText: AppTranslations.get('Search rider...'),
          hintStyle: GoogleFonts.poppins(color: Colors.white.withOpacity(0.4), fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSortButtons() {
    final options = [
      ("rating", AppTranslations.get('Average Rating')),
      ("count", AppTranslations.get('Total')),
      ("name", AppTranslations.get('Full Name')),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: options.map((o) {
          final selected = _sortBy == o.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _sortBy = o.$1),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF14C38E) : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  o.$2,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRiderList() {
    return FutureBuilder<List<_RiderData>>(
      future: _fetchAllRidersWithRatings(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text("${AppTranslations.get('Error')}: ${snapshot.error}", style: GoogleFonts.poppins(color: Colors.red)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.white));
        }

        var riders = snapshot.data!;
        riders = riders.where((r) {
          if (_searchQuery.isEmpty) return true;
          return r.name.toLowerCase().contains(_searchQuery);
        }).toList();

        if (_sortBy == "rating") {
          riders.sort((a, b) => b.avgRating.compareTo(a.avgRating));
        } else if (_sortBy == "count") {
          riders.sort((a, b) => b.ratingCount.compareTo(a.ratingCount));
        } else {
          riders.sort((a, b) => a.name.compareTo(b.name));
        }

        for (int i = 0; i < riders.length; i++) {
          if (riders[i].ratingCount > 0) {
            riders[i].rank = i + 1;
          }
        }

        if (riders.isEmpty) {
          return Center(
            child: Text(
              AppTranslations.get('No riders'),
              style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.6), fontSize: 15),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: riders.length,
          itemBuilder: (context, index) => _RiderCard(rider: riders[index]),
        );
      },
    );
  }

  Future<List<_RiderData>> _fetchAllRidersWithRatings() async {
    final riderSnap = await firestore.collection("users").where("role", isEqualTo: "rider").get();
    final ratingSnap = await firestore.collection("ratings").get();

    final ratingMap = <String, List<Map<String, dynamic>>>{};
    for (final doc in ratingSnap.docs) {
      final data = doc.data();
      final ruid = data["rider_uid"]?.toString() ?? "";
      ratingMap.putIfAbsent(ruid, () => []);
      final m = data;
      m["id"] = doc.id;
      ratingMap[ruid]!.add(m);
    }

    final result = <_RiderData>[];
    for (final doc in riderSnap.docs) {
      final data = doc.data();
      final uid = doc.id;
      final name = (data["full_name"] ?? "").toString();
      final ratings = ratingMap[uid] ?? [];

      double avg = 0;
      int count = ratings.length;
      if (count > 0) {
        final sum = ratings.fold<double>(0, (s, r) => s + (r["rating"] ?? 0).toDouble());
        avg = sum / count;
      }

      result.add(_RiderData(
        uid: uid,
        name: name,
        avgRating: avg,
        ratingCount: count,
        ratings: ratings,
      ));
    }
    return result;
  }
}

class _RiderData {
  final String uid;
  final String name;
  final double avgRating;
  final int ratingCount;
  final List<Map<String, dynamic>> ratings;
  int rank;

  _RiderData({
    required this.uid,
    required this.name,
    required this.avgRating,
    required this.ratingCount,
    required this.ratings,
    this.rank = 0,
  });
}

class _RiderCard extends StatelessWidget {
  final _RiderData rider;
  const _RiderCard({required this.rider});

  Color _rankColor(int rank) {
    switch (rank) {
      case 1: return const Color(0xFFFFD700);
      case 2: return const Color(0xFFC0C0C0);
      case 3: return const Color(0xFFCD7F32);
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showRank = rider.rank > 0 && rider.ratingCount > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: rider.ratingCount > 0
              ? () => _showDetailDialog(context)
              : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: showRank ? _rankColor(rider.rank).withOpacity(0.4) : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Row(
              children: [
                if (showRank) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_rankColor(rider.rank), _rankColor(rider.rank).withOpacity(0.7)],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        "#${rider.rank}",
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (!showRank) const SizedBox(width: 32 + 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rider.name,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rider.ratingCount > 0
                            ? "${rider.ratingCount} ${AppTranslations.get('Rating').toLowerCase()}"
                            : AppTranslations.get('No ratings yet'),
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (rider.ratingCount > 0) ...[
                  Row(
                    children: List.generate(5, (i) {
                      return Icon(
                        i < rider.avgRating.round() ? Icons.star : Icons.star_border,
                        size: 14,
                        color: i < rider.avgRating.round() ? const Color(0xFFFCD34D) : Colors.white.withOpacity(0.25),
                      );
                    }),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    rider.avgRating.toStringAsFixed(1),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFFCD34D),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                rider.name,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1F2937),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ...List.generate(5, (i) {
                    return Icon(
                      i < rider.avgRating.round() ? Icons.star : Icons.star_border,
                      color: i < rider.avgRating.round() ? const Color(0xFFFCD34D) : Colors.grey.shade300,
                      size: 20,
                    );
                  }),
                  const SizedBox(width: 8),
                  Text(
                    rider.avgRating.toStringAsFixed(1),
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0D7377),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "${rider.ratingCount} ${AppTranslations.get('Rating').toLowerCase()}",
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 16),
              if (rider.ratings.isEmpty)
                Text(
                  AppTranslations.get('No ratings yet'),
                  style: GoogleFonts.poppins(color: Colors.grey.shade400),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rider.ratings.length,
                    itemBuilder: (ctx, i) {
                      final r = rider.ratings[i];
                      final rv = (r["rating"] ?? 0).toInt();
                      final cmt = r["comment"]?.toString() ?? "";
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: List.generate(5, (j) {
                                return Icon(
                                  j < rv ? Icons.star : Icons.star_border,
                                  size: 14,
                                  color: j < rv ? const Color(0xFFFCD34D) : Colors.grey.shade300,
                                );
                              }),
                            ),
                            if (cmt.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                cmt,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  AppTranslations.get('Close'),
                  style: GoogleFonts.poppins(color: const Color(0xFF0D7377), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
