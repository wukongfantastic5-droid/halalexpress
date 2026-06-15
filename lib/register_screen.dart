import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

import 'place_search_field.dart';
import 'translations.dart';

class RegisterScreen extends StatefulWidget {
  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final fullName = TextEditingController();
  final accountName = TextEditingController();
  final email = TextEditingController();
  final whatsapp = TextEditingController();
  final address = TextEditingController();
  final password = TextEditingController();

  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  final storage = FirebaseStorage.instance;
  final picker = ImagePicker();

  double? addressLat;
  double? addressLng;

  bool loading = false;
  bool locating = false;
  String selectedRole = "customer";
  String _bankType = "";
  final _bankAccountCtrl = TextEditingController();
  final List<String> _bankTypes = [
    "CIMB Bank",
    "Maybank",
    "Bank Islam",
    "Bank Rakyat",
    "Public Bank",
    "RHB Bank",
    "Hong Leong Bank",
    "AmBank",
    "BSN",
    "Affin Bank",
    "OCBC Bank",
    "Standard Chartered",
  ];

  // Rider document images (bytes for cross-platform web/mobile)
  Uint8List? riderPhoto;
  Uint8List? licenseFront;
  Uint8List? licenseBack;
  Uint8List? roadTax;
  Uint8List? motorcyclePhoto;
  Uint8List? insurance;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    fullName.dispose();
    accountName.dispose();
    email.dispose();
    whatsapp.dispose();
    address.dispose();
    password.dispose();
    _bankAccountCtrl.dispose();
    super.dispose();
  }

  void showLocationLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            padding: EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 30,
                  offset: Offset(0, 10),
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
                    gradient: LinearGradient(
                      colors: [Color(0xFF0D7377), Color(0xFF14C38E)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  AppTranslations.get('Finding your location...'),
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0D7377),
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  AppTranslations.get('Please wait while we locate your GPS.'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> pinLocation() async {
    setState(() {
      locating = true;
    });
    showLocationLoading();

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        setState(() {
          locating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppTranslations.get('Please enable GPS')),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      addressLat = pos.latitude;
      addressLng = pos.longitude;
      address.text = "Lat: ${pos.latitude}, Lng: ${pos.longitude}";

      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() {
        locating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTranslations.get('Location detected successfully')),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      setState(() {
        locating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTranslations.get('Failed to get location')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  bool validPassword(String value) {
    RegExp regex = RegExp(r'^(?=.*[0-9])(?=.*[!@#$%^&*(),.?":{}|<>]).{6,}$');
    return regex.hasMatch(value);
  }

  void register() async {
    if (fullName.text.isEmpty ||
        accountName.text.isEmpty ||
        email.text.isEmpty ||
        whatsapp.text.isEmpty ||
        address.text.isEmpty ||
        password.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          content: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade600, Colors.red.shade400],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.cancel_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppTranslations.get('Please fill all fields'),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    if (!validPassword(password.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          content: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade600, Colors.red.shade400],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.cancel_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppTranslations.get('Password must contain:\n- Minimum 6 characters\n- 1 number\n- 1 symbol'),
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    setState(() => loading = true);

    try {
      // Validate rider documents
      if (selectedRole == "rider") {
        if (riderPhoto == null ||
            licenseFront == null ||
            licenseBack == null ||
            roadTax == null ||
            motorcyclePhoto == null ||
            insurance == null) {
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppTranslations.get('Please complete all rider documents')),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
        if (_bankType.isEmpty || _bankAccountCtrl.text.trim().isEmpty) {
          setState(() => loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppTranslations.get('Please select bank and enter account number')),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final existing = await firestore
          .collection("users")
          .where("account_name", isEqualTo: accountName.text.trim())
          .get();

      if (existing.docs.isNotEmpty) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppTranslations.get('Account name already in use')),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final user = await auth.createUserWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text.trim(),
      );

      final uid = user.user!.uid;

      // Upload rider documents if rider role
      Map<String, String> riderDocs = {};
      if (selectedRole == "rider") {
        final uploads = {
          "rider_photo": riderPhoto!,
          "license_front": licenseFront!,
          "license_back": licenseBack!,
          "road_tax": roadTax!,
          "motorcycle_photo": motorcyclePhoto!,
          "insurance": insurance!,
        };

        int idx = 0;
        for (final entry in uploads.entries) {
          try {
            final ref = storage.ref("rider_docs/$uid/${entry.key}.jpg");
            final tempFile = File("${Directory.systemTemp.path}/rider_upload_${idx}_${entry.key}.jpg");
            await tempFile.writeAsBytes(entry.value);
            await ref.putFile(tempFile);
            final url = await ref.getDownloadURL();
            riderDocs[entry.key] = url;
            await tempFile.delete();
          } catch (uploadError) {
            debugPrint("UPLOAD ERROR ${entry.key}: $uploadError");
            riderDocs[entry.key] = "";
          }
          idx++;
        }
      }

      await firestore.collection("users").doc(uid).set({
        "full_name": fullName.text.trim(),
        "account_name": accountName.text.trim(),
        "email": email.text.trim(),
        "whatsapp": whatsapp.text.trim(),
        "address": address.text,
        "address_lat": addressLat,
        "address_lng": addressLng,
        "role": selectedRole,
        "hasSeenTutorial": false,
        "created_at": Timestamp.now(),
        if (selectedRole == "rider") ...{
          "rider_verified": false,
          "verification_status": "pending",
          "rider_photo": riderDocs["rider_photo"] ?? "",
          "license_front": riderDocs["license_front"] ?? "",
          "license_back": riderDocs["license_back"] ?? "",
          "road_tax": riderDocs["road_tax"] ?? "",
          "motorcycle_photo": riderDocs["motorcycle_photo"] ?? "",
          "insurance": riderDocs["insurance"] ?? "",
        },
      });

      if (selectedRole == "rider") {
        await firestore.collection("riders").doc(uid).set({
          "full_name": fullName.text.trim(),
          "whatsapp": whatsapp.text.trim(),
          "rider_verified": false,
          "wallet_balance": 0.0,
          "bank_type": _bankType,
          "bank_account": _bankAccountCtrl.text.trim(),
          "created_at": Timestamp.now(),
        });
      }

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectedRole == "rider"
                ? AppTranslations.get('Rider registration successful. Awaiting admin verification.')
                : AppTranslations.get('Registration successful'),
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      setState(() => loading = false);

      String message = AppTranslations.get('Registration failed');
      if (e.code == "email-already-in-use")
        message = AppTranslations.get('Email already in use');
      else if (e.code == "invalid-email")
        message = AppTranslations.get('Invalid email');
      else if (e.code == "weak-password") message = AppTranslations.get('Password too weak');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      setState(() => loading = false);
      debugPrint("REGISTER ERROR: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${AppTranslations.get('Error')}: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Uint8List?> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(AppTranslations.get('Select Source'), style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _sourceOption(
                    icon: Icons.camera_alt,
                    label: AppTranslations.get('Camera'),
                    source: ImageSource.camera,
                  ),
                  _sourceOption(
                    icon: Icons.photo_library,
                    label: AppTranslations.get('Gallery'),
                    source: ImageSource.gallery,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (source == null) return null;
    final x = await picker.pickImage(source: source, imageQuality: 70);
    if (x != null) return await x.readAsBytes();
    return null;
  }

  Widget _sourceOption({
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D7377).withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: const Color(0xFF0D7377)),
            const SizedBox(height: 8),
            Text(label, style: GoogleFonts.poppins(
              fontSize: 13, color: const Color(0xFF0D7377),
            )),
          ],
        ),
      ),
    );
  }

  Widget _imageCard({
    required String label,
    required Uint8List? bytes,
    required VoidCallback onPick,
    IconData? fallbackIcon,
  }) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 80,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: bytes != null
                ? const Color(0xFF14C38E)
                : Colors.white.withOpacity(0.3),
            width: bytes != null ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius:
                  const BorderRadius.horizontal(left: Radius.circular(13)),
              child: bytes != null
                  ? Image.memory(bytes, width: 80, height: 80, fit: BoxFit.cover)
                  : Container(
                      width: 80,
                      height: 80,
                      color: const Color(0xFF0D7377).withOpacity(0.1),
                      child: Icon(fallbackIcon ?? Icons.camera_alt,
                          color: const Color(0xFF0D7377)),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                bytes != null ? label : label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: bytes != null ? FontWeight.w600 : FontWeight.w400,
                  color: bytes != null
                      ? const Color(0xFF0D7377)
                      : Colors.grey.shade600,
                ),
              ),
            ),
            if (bytes != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(Icons.check_circle,
                    color: const Color(0xFF14C38E), size: 22),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roleOption({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final isSelected = selectedRole == value;
    return GestureDetector(
      onTap: () => setState(() => selectedRole = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0D7377).withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color:
                    isSelected ? Colors.white : Colors.white.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    String? hint,
  }) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      margin: EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF0D7377).withOpacity(0.08),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: GoogleFonts.poppins(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Color(0xFF0D7377)),
          labelStyle:
              GoogleFonts.poppins(color: Color(0xFF0D7377).withOpacity(0.7)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Color(0xFF14C38E), width: 2),
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.85),
          contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D7377),
              Color(0xFF14C38E),
              Color(0xFF1A237E).withOpacity(0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              FadeTransition(
                opacity: _fadeAnimation,
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      SizedBox(height: 20),
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.3),
                              Colors.white.withOpacity(0.1)
                            ],
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.shopping_bag_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        AppTranslations.get('Register Account'),
                        style: GoogleFonts.poppins(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        AppTranslations.get('Join HalalExpress now'),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      SizedBox(height: 28),
                      Container(
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0.25),
                              Colors.white.withOpacity(0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 30,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Role selection
                            Container(
                              margin: const EdgeInsets.only(bottom: 18),
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _roleOption(
                                      icon: Icons.person_outline,
                                      label: AppTranslations.get('Customer'),
                                      value: "customer",
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: _roleOption(
                                      icon: Icons.motorcycle,
                                      label: AppTranslations.get('Rider'),
                                      value: "rider",
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildField(
                              controller: fullName,
                              label: AppTranslations.get('Full Name'),
                              icon: Icons.person_outline,
                            ),
                            _buildField(
                              controller: email,
                              label: AppTranslations.get('Email'),
                              icon: Icons.email_outlined,
                            ),
                            _buildField(
                              controller: whatsapp,
                              label: AppTranslations.get('WhatsApp Number'),
                              icon: Icons.phone_outlined,
                            ),
                            _buildField(
                              controller: accountName,
                              label: AppTranslations.get('Account Name'),
                              icon: Icons.account_circle_outlined,
                            ),
                            _buildField(
                              controller: password,
                              label: AppTranslations.get('Password'),
                              icon: Icons.lock_outline,
                              obscure: true,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0xFF0D7377)
                                              .withOpacity(0.08),
                                          blurRadius: 12,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: PlaceSearchField(
                                      controller: address,
                                      onSelected: (value, lat, lng) {
                                        address.text = value;
                                        addressLat = lat;
                                        addressLng = lng;
                                      },
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10),
                                AnimatedContainer(
                                  duration: Duration(milliseconds: 200),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: locating
                                            ? [
                                                Colors.grey,
                                                Colors.grey.shade400
                                              ]
                                            : [
                                                Color(0xFF14C38E),
                                                Color(0xFF0D7377)
                                              ],
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0xFF0D7377)
                                              .withOpacity(0.3),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: locating ? null : pinLocation,
                                        borderRadius: BorderRadius.circular(18),
                                        child: Container(
                                          width: 56,
                                          height: 56,
                                          child: Center(
                                            child: locating
                                                ? SizedBox(
                                                    width: 22,
                                                    height: 22,
                                                    child:
                                                        CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2.5,
                                                    ),
                                                  )
                                                : Icon(
                                                    Icons.pin_drop,
                                                    color: Colors.white,
                                                    size: 28,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (selectedRole == "rider") ...[
                              Container(
                                width: double.infinity,
                                margin:
                                    const EdgeInsets.only(top: 8, bottom: 14),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                      color: const Color(0xFFFCD34D)
                                          .withOpacity(0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.verified_user,
                                            size: 16,
                                            color: const Color(0xFFFCD34D)),
                                        const SizedBox(width: 8),
                                        Text(
                                          AppTranslations.get('Rider Documents'),
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    _imageCard(
                                      label: AppTranslations.get('Selfie Photo'),
                                      bytes: riderPhoto,
                                      fallbackIcon: Icons.person,
                                      onPick: () async {
                                        final f = await _pickImage();
                                        if (f != null)
                                          setState(() => riderPhoto = f);
                                      },
                                    ),
                                    _imageCard(
                                      label: AppTranslations.get('License (Front)'),
                                      bytes: licenseFront,
                                      fallbackIcon: Icons.credit_card,
                                      onPick: () async {
                                        final f = await _pickImage();
                                        if (f != null)
                                          setState(() => licenseFront = f);
                                      },
                                    ),
                                    _imageCard(
                                      label: AppTranslations.get('License (Back)'),
                                      bytes: licenseBack,
                                      fallbackIcon: Icons.credit_card,
                                      onPick: () async {
                                        final f = await _pickImage();
                                        if (f != null)
                                          setState(() => licenseBack = f);
                                      },
                                    ),
                                    _imageCard(
                                      label: AppTranslations.get('Road Tax'),
                                      bytes: roadTax,
                                      fallbackIcon: Icons.description,
                                      onPick: () async {
                                        final f = await _pickImage();
                                        if (f != null)
                                          setState(() => roadTax = f);
                                      },
                                    ),
                                    _imageCard(
                                      label: AppTranslations.get('Motorcycle Photo'),
                                      bytes: motorcyclePhoto,
                                      fallbackIcon: Icons.motorcycle,
                                      onPick: () async {
                                        final f = await _pickImage();
                                        if (f != null)
                                          setState(() => motorcyclePhoto = f);
                                      },
                                    ),
                                    _imageCard(
                                      label: AppTranslations.get('Insurance'),
                                      bytes: insurance,
                                      fallbackIcon: Icons.receipt,
                                      onPick: () async {
                                        final f = await _pickImage();
                                        if (f != null)
                                          setState(() => insurance = f);
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      AppTranslations.get('Bank Info (For Withdrawal)'),
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: DropdownButtonFormField<String>(
                                        value: _bankType.isEmpty ? null : _bankType,
                                        items: _bankTypes.map((b) => DropdownMenuItem(
                                          value: b,
                                          child: Text(b, style: GoogleFonts.poppins(fontSize: 13)),
                                        )).toList(),
                                        onChanged: (v) => setState(() => _bankType = v ?? ""),
                                        decoration: InputDecoration(
                                          border: InputBorder.none,
                                          hintText: AppTranslations.get('Select Bank'),
                                          hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade500),
                                        ),
                                        dropdownColor: Colors.white,
                                        style: GoogleFonts.poppins(fontSize: 13, color: const Color(0xFF2E3A46)),
                                        icon: const Icon(Icons.account_balance, color: Color(0xFF0D7377)),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _buildField(
                                      controller: _bankAccountCtrl,
                                      label: AppTranslations.get('Bank Account Number'),
                                      icon: Icons.credit_card,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                      AnimatedContainer(
                        duration: Duration(milliseconds: 200),
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF14C38E), Color(0xFF0D7377)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF0D7377).withOpacity(0.4),
                              blurRadius: 15,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: loading ? null : register,
                            borderRadius: BorderRadius.circular(18),
                            child: Center(
                              child: loading
                                  ? CircularProgressIndicator(
                                      color: Colors.white)
                                  : Text(
                                      AppTranslations.get('Register Account'),
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 40,
                left: 4,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 26),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
