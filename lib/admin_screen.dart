import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'history_order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'notification_service.dart';
import 'tracking_map_screen.dart';
import 'widgets/order_timeline.dart';

class AdminScreen extends StatefulWidget {
  final bool isRider;

  const AdminScreen({super.key, this.isRider = false});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final firestore = FirebaseFirestore.instance;
  final AudioPlayer player = AudioPlayer();
  final Set<String> _newOrderPlayed = {};
  final Map<String, bool> _wazeOpened = {};
  final TextEditingController searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, bool> _nearShop = {};
  Map<String, bool> _nearDrop = {};
  Map<String, double> _shopDistances = {};
  int _activeOrderCount = 0;
  Timer? _proximityTimer;
  Timer? _riderLocationTimer;
  bool _isShowingOffer = false;
  bool _isAcceptingBatch = false;
  bool _riderVerified = false;
  final Set<String> _acceptingOrderIds = {};
  final Map<String, DateTime> _recentlyFailedIds = {};
  StreamSubscription? _riderVerificationSub;
  StreamSubscription? _ordersSub;
  List<QueryDocumentSnapshot>? _lastOrdersSnapshot;

  @override
  void initState() {
    super.initState();
    _startProximityCheck();
    _startRiderLocationUpdates();
    _listenRiderVerification();
    _listenOrders();
  }

  @override
  void dispose() {
    _proximityTimer?.cancel();
    _riderLocationTimer?.cancel();
    _riderVerificationSub?.cancel();
    _ordersSub?.cancel();
    player.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _listenRiderVerification() {
    if (!widget.isRider) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    debugPrint("[RIDER] _listenRiderVerification started for uid=$uid");
    _riderVerificationSub = firestore
        .collection("riders")
        .doc(uid)
        .snapshots()
        .listen((snap) {
      if (!snap.exists) { debugPrint("[RIDER] verification snap not exists"); return; }
      final verified = snap["rider_verified"] == true;
      debugPrint("[RIDER] verification snap: verified=$verified, _riderVerified=$_riderVerified");
      if (verified != _riderVerified) {
        setState(() => _riderVerified = verified);
      }
      if (verified && _lastOrdersSnapshot != null) {
        debugPrint("[RIDER] verification confirmed, re-processing ${_lastOrdersSnapshot!.length} stored orders");
        _processPendingOrders(_lastOrdersSnapshot!);
      } else if (verified && _lastOrdersSnapshot == null) {
        debugPrint("[RIDER] verification confirmed but no stored orders yet");
      }
    });
  }

  void _listenOrders() {
    if (!widget.isRider) { debugPrint("[RIDER] _listenOrders: not rider, skip"); return; }
    debugPrint("[RIDER] _listenOrders subscribing...");
    _ordersSub = firestore
        .collection("orders")
        .where("status", isNotEqualTo: "delivered")
        .snapshots()
        .listen((snap) {
      if (!mounted) { debugPrint("[RIDER] orders snap: not mounted"); return; }
      _lastOrdersSnapshot = snap.docs;
      debugPrint("[RIDER] orders snap received: ${snap.docs.length} docs, _riderVerified=$_riderVerified");
      for (final doc in snap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        debugPrint("[RIDER]   order ${doc.id}: status=${d["status"]}, rider_uid=${d["rider_uid"]}, offered_to=${d["offered_to"]}");
      }
      if (_riderVerified) {
        _processPendingOrders(snap.docs);
      } else {
        debugPrint("[RIDER] orders snap skipped: not verified yet");
      }
    });
  }

  void _processPendingOrders(List<QueryDocumentSnapshot> allDocs) {
    debugPrint("[RIDER] _processPendingOrders: totalDocs=${allDocs.length}, _riderVerified=$_riderVerified, _isShowingOffer=$_isShowingOffer, _isAcceptingBatch=$_isAcceptingBatch");
    if (!_riderVerified || _isShowingOffer || _isAcceptingBatch) {
      debugPrint("[RIDER] _processPendingOrders SKIPPED: verified=$_riderVerified showing=$_isShowingOffer accepting=$_isAcceptingBatch");
      return;
    }
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (currentUid.isEmpty) return;

    final pendingOfferedToMe = <MapEntry<String, Map<String, dynamic>>>[];
    final pendingUnclaimed = <QueryDocumentSnapshot>[];

    for (final doc in allDocs) {
      final d = doc.data() as Map<String, dynamic>;
      debugPrint("[RIDER] checking order ${doc.id}: status=${d["status"]}, rider_uid=${d["rider_uid"]}, offered_to=${d["offered_to"]}");
      if (d["status"] != "pending") {
        debugPrint("[RIDER]   skip: status is ${d["status"]} not pending");
        continue;
      }
      if ((d["rider_uid"] ?? "").toString().isNotEmpty) {
        debugPrint("[RIDER]   skip: rider_uid already set");
        continue;
      }
      if (_acceptingOrderIds.contains(doc.id)) {
        debugPrint("[RIDER]   skip: in _acceptingOrderIds");
        continue;
      }
      final lastFail = _recentlyFailedIds[doc.id];
      if (lastFail != null &&
          DateTime.now().difference(lastFail).inSeconds < 5) {
        debugPrint("[RIDER]   skip: recently failed ${DateTime.now().difference(lastFail).inSeconds}s ago");
        continue;
      }
      final offered = (d["offered_to"] ?? "").toString();
      debugPrint("[RIDER]   offered=$offered, currentUid=$currentUid");
      if (offered == currentUid) {
        pendingOfferedToMe.add(MapEntry(doc.id, d));
      } else {
        pendingUnclaimed.add(doc);
      }
    }

    debugPrint("[RIDER] pendingOfferedToMe=${pendingOfferedToMe.length}, pendingUnclaimed=${pendingUnclaimed.length}, _activeOrderCount=$_activeOrderCount");

    if (pendingOfferedToMe.isNotEmpty) {
      _showBatchOfferDialog(pendingOfferedToMe);
    } else if (pendingUnclaimed.isNotEmpty && _activeOrderCount < 3) {
      _tryClaimBatch(pendingUnclaimed);
    }
  }

  Future<void> _updateRiderLocation() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await firestore.collection("riders").doc(user.uid).set({
        "current_location": GeoPoint(position.latitude, position.longitude),
        "last_seen": Timestamp.now(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _startRiderLocationUpdates() {
    _updateRiderLocation();
    _riderLocationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateRiderLocation(),
    );
  }

  void _startProximityCheck() {
    _proximityTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        final currentLat = position.latitude;
        final currentLng = position.longitude;

        // Update rider location on Firestore
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          firestore.collection("riders").doc(user.uid).set({
            "current_location": GeoPoint(currentLat, currentLng),
            "last_seen": Timestamp.now(),
          }, SetOptions(merge: true)).catchError((_) {});
        }

        final snapshot = await firestore
            .collection("orders")
            .where("status", whereIn: ["accepted", "on the way"])
            .get();

        final nearShop = <String, bool>{};
        final nearDrop = <String, bool>{};
        for (var doc in snapshot.docs) {
          final d = doc.data();
          final shopLat = (d["shop_lat"] ?? 0).toDouble();
          final shopLng = (d["shop_lng"] ?? 0).toDouble();
          if (shopLat != 0 && shopLng != 0) {
            final dist = calculateDistance(currentLat, currentLng, shopLat, shopLng);
            nearShop[doc.id] = dist <= 1.0;
          }
          final dropLat = (d["drop_lat"] ?? 0).toDouble();
          final dropLng = (d["drop_lng"] ?? 0).toDouble();
          if (dropLat != 0 && dropLng != 0) {
            final dist = calculateDistance(currentLat, currentLng, dropLat, dropLng);
            nearDrop[doc.id] = dist <= 1.0;
          }
        }

        // Calculate distances from rider to shop for ALL non-delivered orders
        final allSnapshot = await firestore
            .collection("orders")
            .where("status", isNotEqualTo: "delivered")
            .get();
        final shopDist = <String, double>{};
        for (var doc in allSnapshot.docs) {
          final d = doc.data();
          final shopLat = (d["shop_lat"] ?? 0).toDouble();
          final shopLng = (d["shop_lng"] ?? 0).toDouble();
          if (shopLat != 0 && shopLng != 0) {
            final dist = calculateDistance(currentLat, currentLng, shopLat, shopLng);
            shopDist[doc.id] = dist;
          }
        }

        if (mounted) setState(() {
          _nearShop = nearShop;
          _nearDrop = nearDrop;
          _shopDistances = shopDist;
        });
      } catch (_) {}
    });
  }

  /// Try to claim ALL eligible pending orders at once (batch), set offered_to for each
  Future<void> _tryClaimBatch(List<QueryDocumentSnapshot> pendingDocs) async {
    if (!widget.isRider) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final riderSnap = await firestore.collection("riders").doc(currentUser.uid).get();
      if (!riderSnap.exists) return;
      final riderData = riderSnap.data() as Map<String, dynamic>;
      if (riderData["rider_verified"] != true) return;
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final activeCount = (riderData["active_orders_count"] ?? 0) as int;
      final canTake = 3 - activeCount;
      if (canTake <= 0) return;

      // Filter eligible docs: within 3km, not rejected
      final eligible = <MapEntry<String, Map<String, dynamic>>>[];
      for (final doc in pendingDocs) {
        final d = doc.data() as Map<String, dynamic>;
        if (d["status"] != "pending") continue;
        if ((d["rider_uid"] ?? "").toString().isNotEmpty) continue;
        if ((d["offered_to"] ?? "").toString().isNotEmpty &&
            (d["offered_to"] ?? "").toString() != currentUser.uid) {
          // Check if someone else's offer expired
          final at = d["offer_started_at"] as Timestamp?;
          if (at != null) {
            final elapsed = DateTime.now().millisecondsSinceEpoch -
                at.toDate().millisecondsSinceEpoch;
            if (elapsed < 15000) continue;
          }
        }
        final rejected = (d["rejected_by"] as List?) ?? [];
        if (rejected.contains(currentUser.uid)) continue;

        final shopLat = (d["shop_lat"] ?? 0).toDouble();
        final shopLng = (d["shop_lng"] ?? 0).toDouble();
        if (shopLat == 0 || shopLng == 0) continue;
        final dist = calculateDistance(
          position.latitude, position.longitude, shopLat, shopLng,
        );
        if (dist > 3.0) continue;
        eligible.add(MapEntry(doc.id, d));
      }

      if (eligible.isEmpty) return;

      // Take only as many as we can
      final toClaim = eligible.take(canTake).toList();
      if (toClaim.isEmpty) return;

      // Atomically claim all via transaction
      await firestore.runTransaction((tx) async {
        for (final entry in toClaim) {
          final fresh = await tx.get(firestore.collection("orders").doc(entry.key));
          if (!fresh.exists) continue;
          final fd = fresh.data() as Map<String, dynamic>;
          if (fd["status"] != "pending") continue;
          if ((fd["rider_uid"] ?? "").toString().isNotEmpty) continue;
          final fo = (fd["offered_to"] ?? "").toString();
          if (fo.isNotEmpty && fo != currentUser.uid) {
            final fat = fd["offer_started_at"] as Timestamp?;
            if (fat != null) {
              final el = DateTime.now().millisecondsSinceEpoch -
                  fat.toDate().millisecondsSinceEpoch;
              if (el < 15000) continue;
            }
          }
          tx.update(firestore.collection("orders").doc(entry.key), {
            "offered_to": currentUser.uid,
            "offer_started_at": Timestamp.now(),
          });
        }
      });
    } catch (e) {
      debugPrint("Batch claim error: $e");
    }
  }

  /// Show ONE batch popup for all orders offered to this rider
  Future<void> _showBatchOfferDialog(List<MapEntry<String, Map<String, dynamic>>> offeredOrders) async {
    if (_isShowingOffer || offeredOrders.isEmpty) return;
    _isShowingOffer = true;

    final ordersList = offeredOrders.map((e) {
      final d = e.value;
      final fare = double.tryParse(
        (d["fare"] ?? d["total"] ?? "0").toString(),
      ) ?? 0;
      final shop = d["shop_name"] ?? "Kedai";
      final dist = _shopDistances[e.key];
      return _BatchOrderInfo(
        orderId: e.key,
        shopName: shop.toString(),
        fare: fare,
        distance: dist,
      );
    }).toList();

    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _BatchOfferDialog(
          orders: ordersList,
          onResult: (r) => Navigator.pop(ctx, r),
        ),
      );
    } catch (e) {
      debugPrint("[RIDER] _showBatchOfferDialog error: $e");
    } finally {
      _isShowingOffer = false;
      if (mounted) setState(() {});
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    if (result == "accept") {
      // Track these order IDs so they don't re-trigger
      for (final entry in offeredOrders) {
        _acceptingOrderIds.add(entry.key);
      }
      _isAcceptingBatch = true;
      if (mounted) setState(() {});

      // Show loading dialog until orders appear in active list
      final acceptedIds = offeredOrders.map((e) => e.key).toSet();
      final loadingCtx = context;
      if (loadingCtx.mounted) {
        showDialog(
          context: loadingCtx,
          barrierDismissible: false,
          builder: (_) => PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              content: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 48,
                      height: 48,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: Color(0xFF0D7377),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Sila tunggu...",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0D7377),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Pesanan sedang diproses",
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final acceptOk = await _acceptBatch(offeredOrders, currentUser);
      if (!acceptOk) {
        for (final entry in offeredOrders) {
          _acceptingOrderIds.remove(entry.key);
          _recentlyFailedIds[entry.key] = DateTime.now();
        }
      } else {
        for (final entry in offeredOrders) {
          _acceptingOrderIds.remove(entry.key);
        }
      }

      // Wait for orders to appear in active list (poll Firestore)
      if (acceptOk && mounted) {
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) break;
          final check = await firestore
              .collection("orders")
              .where(FieldPath.documentId, whereIn: acceptedIds.toList())
              .get();
          final allDone = check.docs.every((doc) {
            final s = (doc.data() as Map)["status"] as String? ?? "";
            return s == "accepted" || s == "on the way" || s == "delivered";
          });
          if (allDone) break;
        }
      }

      // Close loading dialog
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      _isAcceptingBatch = false;
      if (mounted) setState(() {});
    } else {
      // Reject ALL — add rider to each order's rejected_by
      final batch = firestore.batch();
      for (final entry in offeredOrders) {
        final ref = firestore.collection("orders").doc(entry.key);
        batch.update(ref, {
          "rejected_by": FieldValue.arrayUnion([currentUser.uid]),
          "offered_to": FieldValue.delete(),
          "offer_started_at": FieldValue.delete(),
        });
      }
      await batch.commit();
    }
  }

  /// Accept batch: assign riders + optimize route order
  /// Returns true if the batch was committed successfully
  Future<bool> _acceptBatch(
    List<MapEntry<String, Map<String, dynamic>>> orders,
    User currentUser,
  ) async {
    try {
      final riderSnap = await firestore.collection("riders").doc(currentUser.uid).get();
      final riderData = riderSnap.data() as Map<String, dynamic>?;
      var riderName = riderData?["full_name"] as String?;
      if (riderName == null || riderName.isEmpty) {
        final userSnap = await firestore.collection("users").doc(currentUser.uid).get();
        riderName = userSnap["full_name"] as String? ?? "Rider";
      }

      // Find current max batch_priority among rider's active orders
      final existingOrders = await firestore
          .collection("orders")
          .where("rider_uid", isEqualTo: currentUser.uid)
          .where("status", whereIn: ["accepted", "on the way"])
          .get();
      int maxPriority = -1;
      for (final doc in existingOrders.docs) {
        final d = doc.data();
        final bp = d["batch_priority"];
        if (bp is int && bp > maxPriority) maxPriority = bp;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final batchId = DateTime.now().millisecondsSinceEpoch.toString();

      // Sort by distance from rider to shop (nearest pickup first)
      final sorted = List<MapEntry<String, Map<String, dynamic>>>.from(orders);
      sorted.sort((a, b) {
        final aDist = calculateDistance(
          position.latitude, position.longitude,
          (a.value["shop_lat"] ?? 0).toDouble(),
          (a.value["shop_lng"] ?? 0).toDouble(),
        );
        final bDist = calculateDistance(
          position.latitude, position.longitude,
          (b.value["shop_lat"] ?? 0).toDouble(),
          (b.value["shop_lng"] ?? 0).toDouble(),
        );
        return aDist.compareTo(bDist);
      });

      // Assign priorities — use batch write for atomicity (all at once)
      final writeBatch = firestore.batch();
      for (int i = 0; i < sorted.length; i++) {
        final entry = sorted[i];
        writeBatch.update(firestore.collection("orders").doc(entry.key), {
          "status": "accepted",
          "rider": riderName,
          "rider_name": riderName,
          "rider_uid": currentUser.uid,
          "batch_id": batchId,
          "batch_priority": maxPriority + 1 + i,
          "batch_total": sorted.length,
          "offered_to": FieldValue.delete(),
          "offer_started_at": FieldValue.delete(),
        });
      }
      writeBatch.set(
        firestore.collection("riders").doc(currentUser.uid),
        {"active_orders_count": FieldValue.increment(sorted.length)},
        SetOptions(merge: true),
      );
      await writeBatch.commit();
      return true;
    } catch (e) {
      _isAcceptingBatch = false;
      if (mounted) setState(() {});
      debugPrint("Accept batch error: $e");
      return false;
    }
  }

  void updateStatus(String id, String status) {
    firestore.collection("orders").doc(id).update({
      "status": status,
    });
    print("STATUS UPDATED: $status");
  }

  Future<void> assignMe(BuildContext context, String id, Map<String, dynamic> data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.handshake, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 20),
                Text(
                  "Pengesahan Tugas",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0D7377),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F8E9).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _detailRow("Barang Runcit", _fmtItems(data)),
                      const SizedBox(height: 8),
                      _detailRow("Kedai", data["shop_name"] ?? ""),
                      const SizedBox(height: 8),
                      _detailRow("Butiran", data["details"] ?? ""),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  "Adakah anda pasti mahu mengambil tugas ini?",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF0D7377)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          "Batal",
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0D7377),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                          ),
                        ),
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            "Ya, Ambil Tugas",
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      String riderName = "";
      String riderUid = currentUser?.uid ?? "";

      if (currentUser != null) {
        final riderDoc =
            await firestore.collection("riders").doc(currentUser.uid).get();
        riderName = riderDoc["full_name"] as String? ?? "";
        if (riderName.isEmpty) {
          final userDoc =
              await firestore.collection("users").doc(currentUser.uid).get();
          riderName = userDoc["full_name"] as String? ?? "";
        }
      }

      await firestore.collection("orders").doc(id).update({
        "rider": riderName,
        "rider_name": riderName,
        "rider_uid": riderUid,
        "status": "accepted",
      });

      if (riderUid.isNotEmpty) {
        await firestore.collection("riders").doc(riderUid).set({
          "active_orders_count": FieldValue.increment(1),
        }, SetOptions(merge: true));
      }

      if (!context.mounted) return;
      if (widget.isRider && mounted) {
        setState(() => _activeOrderCount++);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Tugas diambil oleh $riderName"),
          backgroundColor: const Color(0xFF14C38E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      debugPrint("ASSIGN ME ERROR: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Gagal mengambil tugas"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _fmtItems(Map<String, dynamic> data) {
    final items = data["items"];
    if (items is List && items.isNotEmpty) {
      return items.map((item) {
        final name = (item["name"] ?? "").toString().trim();
        final qty = (item["qty"] ?? 1) as int;
        if (name.isEmpty) return "";
        return qty > 1 ? "$name ×$qty" : name;
      }).where((s) => s.isNotEmpty).join(", ");
    }
    return data["grocery"] ?? "-";
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label: ",
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: const Color(0xFF0D7377),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> delete(String id) async {
    // Read order data first, then delete
    final snap = await firestore.collection("orders").doc(id).get();
    if (snap.exists) {
      final d = snap.data() as Map<String, dynamic>;
      final riderUid = (d["rider_uid"] ?? "").toString();
      if (riderUid.isNotEmpty) {
        await firestore.collection("riders").doc(riderUid).set({
          "active_orders_count": FieldValue.increment(-1),
        }, SetOptions(merge: true));
      }
    }
    await firestore.collection("orders").doc(id).delete();
    if (mounted) setState(() {});
    print("ORDER DELETED");
  }

  double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double p = 0.017453292519943295;
    final c = cos;

    final a = 0.5 -
        c((lat2 - lat1) * p) / 2 +
        c(lat1 * p) *
            c(lat2 * p) *
            (1 - c((lon2 - lon1) * p)) /
            2;

    return 12742 * asin(sqrt(a));
  }

  Future<void> openWaze(String location) async {
    if (location.trim().isEmpty) {
      return;
    }

    final Uri uri = Uri.parse(
      "https://waze.com/ul?q=${Uri.encodeComponent(location)}&navigate=yes",
    );

    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      print(e);
    }
  }

  Future<void> openWazeCoords(double lat, double lng) async {
    final Uri uri = Uri.parse(
      "https://waze.com/ul?ll=$lat,$lng&navigate=yes",
    );
    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      print(e);
    }
  }

  Future<void> openWhatsApp(String phone) async {
    if (phone.trim().isEmpty) {
      return;
    }

    String cleanPhone = phone
        .replaceAll("+", "")
        .replaceAll(" ", "")
        .replaceAll("-", "");

    if (cleanPhone.startsWith("0")) {
      cleanPhone = "6$cleanPhone";
    }

    final Uri uri = Uri.parse(
      "https://wa.me/$cleanPhone",
    );

    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      print(e);
    }
  }

  Future<void> pickedOrder({
    required BuildContext context,
    required String orderId,
    required String phone,
  }) async {
    print("========== PICKED ORDER ==========");

    if (phone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Nombor WhatsApp pelanggan tidak ditemui"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LoadingDialog(message: "Dalam Proses..."),
    );

    String cleanPhone = phone
        .replaceAll("+", "")
        .replaceAll(" ", "")
        .replaceAll("-", "");

    if (cleanPhone.startsWith("0")) {
      cleanPhone = "6$cleanPhone";
    }

    String message =
        "Hi, barang runcit anda telah diambil oleh rider. "
    "Sila lihat gambar bukti pengambilan di bawah.";

    final Uri whatsappUri = Uri.parse(
      "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}",
    );

    try {
      bool launched = await launchUrl(
        whatsappUri,
        mode: LaunchMode.externalApplication,
      );

      if (context.mounted) Navigator.pop(context);

      if (launched) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _LoadingDialog(message: "Sila tunggu pengambilan barang tugas dalam proses..."),
        );

        await Future.delayed(
          Duration(seconds: 15),
        );

        if (context.mounted) Navigator.pop(context);

        bool? done = await showDialog(
          context: context,
          builder: (context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFF1F8E9)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Bukti Pengambilan",
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0D7377),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Adakah anda sudah mengambil dan menghantar gambar bukti pengambilan kepada pelanggan?",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(
                              "No",
                              style: GoogleFonts.poppins(color: Colors.grey.shade600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D7377),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(
                              "Yes",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );

        if (done == true) {
          await firestore
              .collection("orders")
              .doc(orderId)
              .update({
            "status": "on the way",
            "picked_at": Timestamp.now(),
          });

          showDialog(
            context: context,
            builder: (context) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Color(0xFFF1F8E9)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF14C38E).withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Barang Diambil",
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0D7377),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Gambar bukti pengambilan telah berjaya dihantar kepada pelanggan.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF14C38E),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            "Selesai",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> completeDelivery({
    required BuildContext context,
    required String orderId,
    required String phone,
    required double dropLat,
    required double dropLng,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LoadingDialog(message: "Sila Tunggu Dalam Proses..."),
    );

    LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission ==
              LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (context.mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Kebenaran lokasi ditolak"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Position position =
          await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      double currentLat = position.latitude;
      double currentLng = position.longitude;

      double distance = calculateDistance(
        currentLat,
        currentLng,
        dropLat,
        dropLng,
      );

      if (distance > 1.0) {
        if (context.mounted) Navigator.pop(context);
        showDialog(
        context: context,
        builder: (context) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Color(0xFFFEF2F2)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF4444).withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.location_off,
                      color: Colors.white,
                      size: 45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Lokasi Salah",
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "You must be within 1KM radius of customer location before completing delivery.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        "OK",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    if (phone.trim().isEmpty) {
      if (context.mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Customer WhatsApp not found"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String cleanPhone = phone
        .replaceAll("+", "")
        .replaceAll(" ", "")
        .replaceAll("-", "");

    if (cleanPhone.startsWith("0")) {
      cleanPhone = "6$cleanPhone";
    }

    String message =
        "Hi, pesanan runcit anda telah sampai. "
    "Sila lihat gambar bukti penghantaran di bawah.";

    final Uri whatsappUri = Uri.parse(
      "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}",
    );

    if (context.mounted) Navigator.pop(context);

    try {
      bool launched = await launchUrl(
        whatsappUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _LoadingDialog(message: "Sila tunggu penghantaran barang dalam proses..."),
        );

        await Future.delayed(
          Duration(seconds: 15),
        );

        if (context.mounted) Navigator.pop(context);

        bool? done = await showDialog(
          context: context,
          builder: (context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFF1F8E9)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      "Bukti Penghantaran",
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0D7377),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Adakah anda sudah hantar gambar bukti?",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(
                              "Tidak",
                              style: GoogleFonts.poppins(color: Colors.grey.shade600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D7377),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(
                              "Ya",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );

        if (done == true) {
          await firestore
              .collection("orders")
              .doc(orderId)
              .update({
            "status": "delivered",
            "delivered_at": Timestamp.now(),
          });

          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            await firestore.collection("riders").doc(currentUser.uid).set({
              "active_orders_count": FieldValue.increment(-1),
            }, SetOptions(merge: true));
          }
          if (mounted) setState(() => _activeOrderCount--);

          await player.play(
            AssetSource('audio/complete.mp3'),
          );

          showDialog(
            context: context,
            builder: (context) {
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Color(0xFFF1F8E9)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF14C38E).withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "Penghantaran Selesai",
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0D7377),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Penghantaran berjaya diselesaikan.",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF14C38E),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            "Done",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }
      }
    } catch (e) {
      print(e);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case "pending":
        return "Menunggu";
      case "accepted":
        return "Dijemput";
      case "on the way":
        return "Dalam Perjalanan";
      case "delivered":
        return "Selesai";
      default:
        return status;
    }
  }

  Future<void> _uploadReceipt(String orderId) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final file = File(picked.path);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = FirebaseStorage.instance.ref("receipts/${orderId}_$timestamp.jpg");
      final uploadTask = await ref.putFile(file);
      final url = await uploadTask.ref.getDownloadURL();

      await firestore.collection("orders").doc(orderId).update({
        "receipt_url": url,
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Resit berjaya dimuat naik"),
          backgroundColor: const Color(0xFF14C38E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      debugPrint("UPLOAD RECEIPT ERROR: $e");
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Gagal memuat naik resit"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openBatchRoute(List<QueryDocumentSnapshot> allOrders) {
    final stops = <Map<String, dynamic>>[];
    for (final doc in allOrders) {
      final d = doc.data() as Map<String, dynamic>;
      final rider = d["rider_uid"]?.toString() ?? "";
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? "";
      if (rider != currentUid) continue;
      final sLat = (d["shop_lat"] ?? 0).toDouble();
      final sLng = (d["shop_lng"] ?? 0).toDouble();
      final dLat = (d["drop_lat"] ?? 0).toDouble();
      final dLng = (d["drop_lng"] ?? 0).toDouble();
      if (sLat != 0 && sLng != 0) {
        stops.add({
          "name": "Ambil: ${d["shop_name"] ?? "Kedai"}",
          "lat": sLat,
          "lng": sLng,
        });
      }
      if (dLat != 0 && dLng != 0) {
        stops.add({
          "name": "Hantar: ${d["drop"] ?? "Pelanggan"}",
          "lat": dLat,
          "lng": dLng,
        });
      }
    }
    if (stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Tiada tugasan aktif untuk route"),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }
    // Sort: pickups first, then drop-offs (nearest first)
    stops.sort((a, b) {
      if (a["name"].toString().startsWith("Ambil") &&
          !b["name"].toString().startsWith("Ambil")) return -1;
      if (!a["name"].toString().startsWith("Ambil") &&
          b["name"].toString().startsWith("Ambil")) return 1;
      return 0;
    });
    // Build Google Maps URL with waypoints
    final origin = "${stops.first["lng"]},${stops.first["lat"]}";
    final dest = "${stops.last["lng"]},${stops.last["lat"]}";
    final waypoints = stops.length > 2
        ? stops.sublist(1, stops.length - 1).map((s) => "${s["lng"]},${s["lat"]}").join("|")
        : "";
    final url = waypoints.isNotEmpty
        ? "https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$dest&waypoints=$waypoints&travelmode=driving"
        : "https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$dest&travelmode=driving";
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) {});
  }

  void _showReceiptDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    "Tutup",
                    style: GoogleFonts.poppins(color: const Color(0xFF0D7377)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: StreamBuilder(
        stream: firestore
            .collection("orders")
            .where("status", isNotEqualTo: "delivered")
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D7377)),
              ),
            );
          }

          final allOrders = snapshot.data!.docs;

          // Sync active order count: self-heal from actual orders
          if (widget.isRider) {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              // Count actual non-delivered orders assigned to this rider
              final actualActive = allOrders.where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                return (d["rider_uid"] ?? "").toString() == user.uid &&
                    d["status"] != "delivered";
              }).length;
              final riderRef = firestore.collection("riders").doc(user.uid);
              riderRef.get().then((riderDoc) {
                if (riderDoc.exists && mounted) {
                  final stored = riderDoc["active_orders_count"];
                  final storedCount = (stored is int) ? stored : (stored is double ? stored.toInt() : 0);
                  if (storedCount != actualActive) {
                    // Self-heal: correct Firestore to match reality
                    riderRef.set({"active_orders_count": actualActive}, SetOptions(merge: true));
                  }
                  if (storedCount != _activeOrderCount || actualActive != _activeOrderCount) {
                    setState(() => _activeOrderCount = actualActive);
                  }
                }
              });
            }
          }

          final currentUid = FirebaseAuth.instance.currentUser?.uid ?? "";

          // Determine which ONE active order to show for this rider
          Iterable<QueryDocumentSnapshot> filtered;
          if (widget.isRider) {
            // Collect rider's active (non-delivered) orders
            final myActive = allOrders.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              return (d["rider_uid"] ?? "").toString() == currentUid &&
                  d["status"] != "delivered";
            }).toList();

            // Clear processing flag once data arrives
            _isAcceptingBatch = false;

            // Sort by priority (batch_priority first, then created_at)
            myActive.sort((a, b) {
              final ad = a.data() as Map<String, dynamic>;
              final bd = b.data() as Map<String, dynamic>;
              final ap = ad["batch_priority"];
              final bp = bd["batch_priority"];
              // Firestore may return int or double — handle both
              int pa = 999, pb = 999;
              if (ap is int) pa = ap;
              else if (ap is double) pa = ap.toInt();
              if (bp is int) pb = bp;
              else if (bp is double) pb = bp.toInt();
              if (pa != pb) return pa.compareTo(pb);
              // Fallback: older order first
              final aa = ad["created_at"] as Timestamp?;
              final bb = bd["created_at"] as Timestamp?;
              if (aa != null && bb != null) {
                return aa.toDate().compareTo(bb.toDate());
              }
              return 0;
            });

            final currentPriorityOrderId = myActive.isNotEmpty ? myActive.first.id : null;

            filtered = allOrders.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              // Never show pending orders in list (popup only)
              if (d["status"] == "pending") return false;
              if (d["status"] == "accepted" || d["status"] == "on the way") {
                // Only the one with highest priority
                return doc.id == currentPriorityOrderId;
              }
              return false;
            });
          } else {
            filtered = allOrders;
          }

          final orders = _searchQuery.isEmpty
              ? filtered.toList()
              : filtered.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final shop = (d["shop_name"] ?? "").toString().toLowerCase();
                  final drop = (d["drop"] ?? "").toString().toLowerCase();
                  return shop.contains(_searchQuery) || drop.contains(_searchQuery);
                }).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Pesanan Aktif",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0D7377),
                          ),
                        ),
                        if (widget.isRider)
                          Text(
                            "Tugas saya: $_activeOrderCount / 3",
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: _activeOrderCount >= 3
                                  ? Colors.red
                                  : const Color(0xFF0D7377),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        if (widget.isRider)
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.route, color: Colors.white),
                              tooltip: "Batch Route",
                              onPressed: () => _openBatchRoute(allOrders),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.history, color: Colors.white),
                            tooltip: "Order History",
                            onPressed: () {
                              final uid = FirebaseAuth.instance.currentUser?.uid;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => HistoryOrderScreen(riderUid: uid),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: searchController,
                  onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Cari kedai / pelanggan...",
                    hintStyle: GoogleFonts.poppins(color: Colors.white60, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.white60, size: 20),
                    filled: true,
                    fillColor: const Color(0xFF0D7377).withOpacity(0.15),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: const Color(0xFF0D7377).withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF0D7377)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isAcceptingBatch) ...[
                              CircularProgressIndicator(color: const Color(0xFF0D7377)),
                              SizedBox(height: 12),
                              Text("Memproses...",
                                style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500),
                              ),
                            ] else ...[
                              Icon(Icons.inbox, size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text("Tiada pesanan aktif",
                                style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey.shade400),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          final doc = orders[index];
                          final data =
                              doc.data() as Map<String, dynamic>;

                          String dropLocation =
                              data["drop"] ?? "";

                          String uid =
                              data["user_uid"] ?? "";

                          double dropLat =
                              (data["drop_lat"] ?? 0)
                                  .toDouble();

                          double dropLng =
                              (data["drop_lng"] ?? 0)
                                  .toDouble();

                          String userPhone = "";

                          if (data.containsKey("whatsapp")) {
                            userPhone =
                                data["whatsapp"] ?? "";
                          }

                          String status = data["status"] ?? "pending";
                          Color statusColor;
                          IconData statusIcon;
                          switch (status) {
                            case "pending":
                              statusColor = const Color(0xFFF59E0B);
                              statusIcon = Icons.hourglass_empty;
                              break;
                            case "accepted":
                              statusColor = const Color(0xFF6366F1);
                              statusIcon = Icons.thumb_up;
                              break;
                            case "on the way":
                              statusColor = const Color(0xFF0D7377);
                              statusIcon = Icons.delivery_dining;
                              break;
                            default:
                              statusColor = Colors.grey;
                              statusIcon = Icons.help;
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
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
                                  offset: const Offset(0, 6),
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
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                                          ),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(
                                          Icons.shopping_bag,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Pesanan Pelanggan",
                                              style: GoogleFonts.poppins(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF0D7377),
                                              ),
                                            ),
                                            FutureBuilder<DocumentSnapshot>(
                                              future: firestore
                                                  .collection("users")
                                                  .doc(uid)
                                                  .get(),
                                              builder: (context, userSnapshot) {
                                                if (!userSnapshot.hasData) {
                                                  return Text(
                                                    "Memuatkan...",
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 12,
                                                      color: Colors.grey.shade500,
                                                    ),
                                                  );
                                                }
                                                if (!userSnapshot.data!.exists) {
                                                  return Text(
                                                    "Pelanggan Tidak Dikenali",
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 12,
                                                      color: Colors.red.shade400,
                                                    ),
                                                  );
                                                }
                                                final userData =
                                                    userSnapshot.data!.data()
                                                        as Map<String, dynamic>;
                                                String customerName =
                                                    userData["full_name"] ??
                                                        "Unknown Customer";
                                                return Text(
                                                  customerName,
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.grey.shade700,
                                                  ),
                                                );
                                              },
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
                                          color: statusColor.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              statusIcon,
                                              size: 14,
                                              color: statusColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _statusLabel(status),
                                              style: GoogleFonts.poppins(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: statusColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F8E9).withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      children: [
                                        _infoRow(Icons.shopping_cart, "Barang Runcit", _fmtItems(data)),
                                        const SizedBox(height: 6),
                                        _infoRow(Icons.store, "Kedai", data["shop_name"] ?? ""),
                                        const SizedBox(height: 6),
                                        _infoRow(Icons.description, "Butiran", data["details"] ?? ""),
                                        const SizedBox(height: 6),
                                        _infoRow(Icons.location_on, "Lokasi Hantar", data["drop"] ?? ""),
                                        const SizedBox(height: 10),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                                            ),
                                            borderRadius: BorderRadius.circular(16),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF0D7377).withOpacity(0.3),
                                                blurRadius: 12,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: const Icon(Icons.monetization_on, color: Colors.white, size: 24),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      "Tambang",
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 12,
                                                        color: Colors.white.withOpacity(0.8),
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      "RM ${double.tryParse((data["fare"] ?? data["total"] ?? "0").toString())?.toStringAsFixed(2) ?? "0.00"}",
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 22,
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if ((data["distance_km"] ?? "").toString() != "0" &&
                                                  (data["distance_km"] ?? "").toString().isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.straighten, size: 14, color: Colors.white.withOpacity(0.8)),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        "${data["distance_km"]} km",
                                                        style: GoogleFonts.poppins(
                                                          fontSize: 13,
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        _infoRow(Icons.chat, "WhatsApp",
                                            userPhone.isEmpty ? "Tiada no telefon" : userPhone,
                                            valueColor: const Color(0xFF0D7377)),
                                        const SizedBox(height: 6),
                                        _infoRow(Icons.delivery_dining, "Rider", data["rider"] ?? "none"),
                                        if (widget.isRider && _shopDistances.containsKey(doc.id))
                                          _infoRow(
                                            Icons.near_me,
                                            "Jarak Saya",
                                            "${_shopDistances[doc.id]!.toStringAsFixed(1)} km dari kedai",
                                            valueColor: _shopDistances[doc.id]! <= 3.0
                                                ? const Color(0xFF14C38E)
                                                : Colors.red,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OrderTimeline(currentStatus: data["status"] ?? "pending"),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if ((data["status"] ?? "") == "pending")
                                        _actionButton(
                                          label: widget.isRider && _activeOrderCount >= 3
                                              ? "Tugas Penuh"
                                              : "Ambil Tugas",
                                          icon: Icons.handshake,
                                          color1: widget.isRider && _activeOrderCount >= 3
                                              ? Colors.grey
                                              : const Color(0xFF0D7377),
                                          color2: widget.isRider && _activeOrderCount >= 3
                                              ? Colors.grey
                                              : const Color(0xFF14C38E),
                                          onPressed: widget.isRider && _activeOrderCount >= 3
                                              ? null
                                              : () => assignMe(context, doc.id, data),
                                        ),
                                      if ((data["status"] ?? "") == "accepted") ...[
                                        _actionButton(
                                          label: "Waze",
                                          icon: Icons.navigation,
                                          color1: const Color(0xFFF59E0B),
                                          color2: const Color(0xFFFBBF24),
                                          onPressed: () {
                                            final shopLat = (data["shop_lat"] ?? 0).toDouble();
                                            final shopLng = (data["shop_lng"] ?? 0).toDouble();
                                            if (shopLat != 0 && shopLng != 0) {
                                              openWazeCoords(shopLat, shopLng);
                                            } else {
                                              openWaze(dropLocation);
                                            }
                                          },
                                        ),
                                        _actionButton(
                                          label: "Map",
                                          icon: Icons.map,
                                          color1: const Color(0xFF0D7377),
                                          color2: const Color(0xFF14C38E),
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TrackingMapScreen(
                                                orderId: doc.id,
                                                orderData: data,
                                                riderUid: FirebaseAuth.instance.currentUser?.uid,
                                              ),
                                            ),
                                          ),
                                        ),
                                        _actionButton(
                                          label: "Sudah Ambil",
                                          icon: Icons.shopping_bag,
                                          color1: _nearShop[doc.id] == true
                                              ? const Color(0xFF6366F1)
                                              : Colors.grey,
                                          color2: _nearShop[doc.id] == true
                                              ? const Color(0xFF818CF8)
                                              : Colors.grey,
                                          onPressed: _nearShop[doc.id] == true
                                              ? () {
                                                  pickedOrder(
                                                    context: context,
                                                    orderId: doc.id,
                                                    phone: userPhone,
                                                  );
                                                }
                                              : null,
                                        ),
                                      ],
                                      _actionButton(
                                        label: "WhatsApp",
                                        icon: Icons.chat,
                                        color1: const Color(0xFF14C38E),
                                        color2: const Color(0xFF0D7377),
                                        onPressed: () => openWhatsApp(userPhone),
                                      ),
                                      if ((data["status"] ?? "") == "on the way")
                                        data["receipt_url"] != null && (data["receipt_url"] ?? "").toString().isNotEmpty
                                            ? GestureDetector(
                                                onTap: () => _showReceiptDialog(data["receipt_url"]),
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(9),
                                                    child: Image.network(
                                                      data["receipt_url"],
                                                      height: 60,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : _actionButton(
                                                label: "Resit Kedai",
                                                icon: Icons.receipt_long,
                                                color1: const Color(0xFFF59E0B),
                                                color2: const Color(0xFFFBBF24),
                                                onPressed: () => _uploadReceipt(doc.id),
                                              ),
                                      if ((data["status"] ?? "") == "on the way") ...[
                                        _actionButton(
                                          label: "Waze",
                                          icon: Icons.navigation,
                                          color1: const Color(0xFFF59E0B),
                                          color2: const Color(0xFFFBBF24),
                                          onPressed: () {
                                            final dropLat2 = (data["drop_lat"] ?? 0).toDouble();
                                            final dropLng2 = (data["drop_lng"] ?? 0).toDouble();
                                            if (dropLat2 != 0 && dropLng2 != 0) {
                                              openWazeCoords(dropLat2, dropLng2);
                                            } else {
                                              openWaze(data["drop"] ?? "");
                                            }
                                          },
                                        ),
                                        _actionButton(
                                          label: "Map",
                                          icon: Icons.map,
                                          color1: const Color(0xFF0D7377),
                                          color2: const Color(0xFF14C38E),
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TrackingMapScreen(
                                                orderId: doc.id,
                                                orderData: data,
                                                riderUid: FirebaseAuth.instance.currentUser?.uid,
                                              ),
                                            ),
                                          ),
                                        ),
                                        _actionButton(
                                          label: "Selesaikan",
                                          icon: Icons.check_circle,
                                          color1: _nearDrop[doc.id] == true
                                              ? const Color(0xFF14C38E)
                                              : Colors.grey,
                                          color2: _nearDrop[doc.id] == true
                                              ? const Color(0xFF0D7377)
                                              : Colors.grey,
                                          onPressed: _nearDrop[doc.id] == true
                                              ? () {
                                                  completeDelivery(
                                                    context: context,
                                                    orderId: doc.id,
                                                    phone: userPhone,
                                                    dropLat: dropLat,
                                                    dropLng: dropLng,
                                                  );
                                                }
                                              : null,
                                        ),
                                      ],
                                      if (!widget.isRider)
                                        _actionButton(
                                          label: "Delete",
                                          icon: Icons.delete,
                                          color1: const Color(0xFFEF4444),
                                          color2: const Color(0xFFDC2626),
                                          onPressed: () => delete(doc.id),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF0D7377).withOpacity(0.7)),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: valueColor ?? Colors.grey.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color1,
    required Color color2,
    VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: onPressed != null ? color1 : Colors.grey.shade400,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: onPressed != null ? 3 : 0,
        shadowColor: onPressed != null ? color1.withOpacity(0.3) : Colors.transparent,
      ),
      icon: Icon(icon, size: 18, color: onPressed != null ? Colors.white : Colors.white70),
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: onPressed != null ? Colors.white : Colors.white70,
        ),
      ),
      onPressed: onPressed,
    );
  }
}

class _BatchOrderInfo {
  final String orderId;
  final String shopName;
  final double fare;
  final double? distance;
  _BatchOrderInfo({
    required this.orderId,
    required this.shopName,
    required this.fare,
    this.distance,
  });
}

class _BatchOfferDialog extends StatefulWidget {
  final List<_BatchOrderInfo> orders;
  final ValueChanged<String> onResult;

  const _BatchOfferDialog({
    required this.orders,
    required this.onResult,
  });

  @override
  State<_BatchOfferDialog> createState() => _BatchOfferDialogState();
}

class _BatchOfferDialogState extends State<_BatchOfferDialog>
    with TickerProviderStateMixin {
  late AnimationController _countdownController;
  int _secondsLeft = 10;
  final AudioPlayer _alertPlayer = AudioPlayer();
  Timer? _vibrationTimer;
  bool _isAccepting = false;
  static const _vibrateChannel = MethodChannel('com.kampungrider/vibrate');

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
    _countdownController.addListener(() {
      final remaining = 10 - (_countdownController.value * 10).round();
      if (remaining != _secondsLeft && mounted) {
        setState(() => _secondsLeft = remaining);
      }
    });
    _countdownController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        widget.onResult("timeout");
      }
    });
    _countdownController.forward();
    _playAlertSound();
    _startVibration();
  }

  void _playAlertSound() {
    _alertPlayer.setReleaseMode(ReleaseMode.loop);
    _alertPlayer.play(AssetSource('audio/notification.mp3'));
  }

  void _startVibration() {
    _vibrateNow();
    _vibrationTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _vibrateNow();
    });
  }

  void _vibrateNow() {
    _vibrateChannel.invokeMethod('vibrate', 2000);
  }

  Future<void> _onAccept() async {
    if (_isAccepting) return;
    setState(() => _isAccepting = true);
    _countdownController.stop();
    _vibrationTimer?.cancel();
    _alertPlayer.stop();
    _vibrateChannel.invokeMethod('cancel');
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) widget.onResult("accept");
  }

  @override
  void dispose() {
    _countdownController.dispose();
    _alertPlayer.stop();
    _alertPlayer.dispose();
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    _vibrateChannel.invokeMethod('cancel');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.orders.length;
    return PopScope(
      canPop: _isAccepting,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF1F8E9)],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0D7377).withOpacity(0.3),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Icon(Icons.notifications_active,
                    color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                count > 1 ? "Anda Dapat $count Pesanan!" : "Pesanan Baru!",
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0D7377),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Column(
                    children: widget.orders.map((o) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.store, size: 16, color: const Color(0xFF0D7377)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              o.shopName,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                          Text(
                            "RM${o.fare.toStringAsFixed(0)}",
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0D7377),
                            ),
                          ),
                          if (o.distance != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              "${o.distance!.toStringAsFixed(1)}km",
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )).toList(),
                  ),
                ),
              ),
              if (_isAccepting)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(
                        color: Color(0xFF14C38E),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Memproses...",
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Color(0xFF0D7377),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                const SizedBox(height: 16),
                AnimatedBuilder(
                  animation: _countdownController,
                  builder: (context, _) {
                    final pct = _countdownController.value;
                    return SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: pct,
                            strokeWidth: 4,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF14C38E)),
                          ),
                          Text(
                            "$_secondsLeft",
                            style: GoogleFonts.poppins(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0D7377),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.close, color: Colors.white),
                        label: Text(
                          "Tolak",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _isAccepting
                            ? null
                            : () {
                                _countdownController.stop();
                                widget.onResult("reject");
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF14C38E),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: Text(
                          "Terima",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: _isAccepting ? null : _onAccept,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingDialog extends StatelessWidget {
  final String message;
  const _LoadingDialog({required this.message});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF0D7377)),
              const SizedBox(height: 16),
              Text(
                message,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xFF0D7377),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
