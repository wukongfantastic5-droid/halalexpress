import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'translations.dart';

class ForceUpdateScreen extends StatefulWidget {
  final String downloadUrl;
  final String latestVersion;
  final String currentVersion;

  const ForceUpdateScreen({
    super.key,
    required this.downloadUrl,
    required this.latestVersion,
    required this.currentVersion,
  });

  @override
  State<ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<ForceUpdateScreen> {
  double _progress = 0;
  String _status = AppTranslations.get('Ready to download');
  bool _downloading = false;
  bool _done = false;
  bool _openFailed = false;
  String _filePath = "";
  StreamSubscription? _downloadSub;

  @override
  void dispose() {
    _downloadSub?.cancel();
    super.dispose();
  }

  Future<bool> _checkInstallPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final allowed = await MethodChannel("com.halalexpress/install_permission")
          .invokeMethod<bool>("canRequestPackageInstalls");
      return allowed == true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _openInstallSettings() async {
    try {
      await MethodChannel("com.halalexpress/install_permission")
          .invokeMethod("openInstallSettings");
    } catch (_) {}
  }

  Future<void> _requestInstallPermissionDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppTranslations.get('Install Permission'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          AppTranslations.get('Please enable "Install unknown apps" from this source in device settings to install the latest version.'),
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openInstallSettings();
            },
            child: Text(AppTranslations.get('Open Settings'), style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  Future<void> _startDownload() async {
    final canInstall = await _checkInstallPermission();
    if (!canInstall) {
      if (!mounted) return;
      await _requestInstallPermissionDialog();
    }

    setState(() {
      _downloading = true;
      _status = AppTranslations.get('Downloading...');
      _progress = 0;
      _done = false;
      _openFailed = false;
    });

    try {
      final dir = await getTemporaryDirectory();
      _filePath = "${dir.path}/halalexpress_${widget.latestVersion}.apk";
      final filePath = _filePath;

      final request = http.Request("GET", Uri.parse(widget.downloadUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        if (mounted) setState(() => _status = "${AppTranslations.get('Download failed')} (${response.statusCode})");
        return;
      }

      final totalBytes = response.contentLength ?? -1;
      var receivedBytes = 0;
      final file = File(filePath);
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && mounted) {
          setState(() {
            _progress = receivedBytes / totalBytes;
            _status = "${AppTranslations.get('Downloading...')} ${(_progress * 100).toStringAsFixed(0)}%";
          });
        }
      }

      await sink.close();

      if (!mounted) return;

      setState(() => _status = AppTranslations.get('Opening installer...'));

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      try {
        await MethodChannel("com.halalexpress/install_apk")
            .invokeMethod("installApk", filePath);
        setState(() {
          _done = true;
          _status = AppTranslations.get('Complete installation on next screen');
        });
      } catch (e) {
        setState(() {
          _done = true;
          _openFailed = true;
          _status = AppTranslations.get('Failed to open automatically. Open the APK file manually.');
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = "${AppTranslations.get('Error')}: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: const Color(0xFF0D7377),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: _done
                      ? const Icon(Icons.check_circle_outline, size: 48, color: Colors.white)
                      : const Icon(Icons.system_update_rounded, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 28),
                Text(
                  AppTranslations.get('Update Required'),
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  AppTranslations.get('New version available. Please download and install to continue using the app.'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "${AppTranslations.get('Current version')}: ",
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                      ),
                      Text(
                        widget.currentVersion,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.arrow_forward, size: 16, color: Colors.white.withOpacity(0.5)),
                      const SizedBox(width: 16),
                      Text(
                        "${AppTranslations.get('New version')}: ",
                        style: GoogleFonts.poppins(fontSize: 12, color: Colors.white70),
                      ),
                      Text(
                        widget.latestVersion,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF14C38E),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                if (_downloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 10,
                      backgroundColor: Colors.white.withOpacity(0.15),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF14C38E)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _status,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _done ? null : _startDownload,
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        AppTranslations.get('Download & Install'),
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0D7377),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  if (_done && !_openFailed) ...[
                    const SizedBox(height: 10),
                    Text(
                      AppTranslations.get('The installer will open automatically. Complete on the next screen.'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                  if (_done && _openFailed) ...[
                    const SizedBox(height: 10),
                    Text(
                      "${AppTranslations.get('File location:')} $_filePath",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _startDownload,
                      icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                      label: Text(
                        AppTranslations.get('Try opening again'),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Fetch latest release version + APK download URL from GitHub.
Future<Map<String, String>?> _fetchLatestRelease() async {
  try {
    final res = await http.Client().get(
      Uri.parse("https://api.github.com/repos/wukongfantastic5-droid/halalexpress/releases/latest"),
      headers: {"Accept": "application/vnd.github.v3+json"},
    );
    if (res.statusCode != 200) return null;
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tagName = (json["tag_name"] as String?) ?? "";
    final assets = json["assets"] as List<dynamic>? ?? [];
    String? apkUrl;
    for (final asset in assets) {
      final name = (asset as Map<String, dynamic>)["name"] as String? ?? "";
      if (name.endsWith(".apk")) {
        apkUrl = asset["browser_download_url"] as String?;
        break;
      }
    }
    if (tagName.isEmpty || apkUrl == null || apkUrl.isEmpty) return null;
    return {
      "version": tagName.replaceFirst(RegExp(r'^v'), ''),
      "url": apkUrl,
    };
  } catch (_) {
    return null;
  }
}

/// Compare two semantic versions. Returns true if [current] < [latest].
bool isVersionLower(String current, String latest) {
  final curParts = current.split('.').map(int.parse).toList();
  final latParts = latest.split('.').map(int.parse).toList();
  for (int i = 0; i < 3; i++) {
    final c = i < curParts.length ? curParts[i] : 0;
    final l = i < latParts.length ? latParts[i] : 0;
    if (c < l) return true;
    if (c > l) return false;
  }
  return false;
}

/// Check app status: maintenance from Firestore, latest version from GitHub.
/// Returns true if a blocking screen was shown (caller should not proceed).
Future<bool> checkAndShowUpdate(BuildContext context) async {
  try {
    // Step 1: Check maintenance from Firestore
    final settingsDoc = await FirebaseFirestore.instance
        .collection("settings")
        .doc("app_settings")
        .get();

    final isUnderMaintenance = settingsDoc.exists &&
        settingsDoc["isUnderMaintenance"] == true;

    // Step 2: Fetch latest release from GitHub
    final release = await _fetchLatestRelease();
    final ghVersion = release?["version"] ?? "";
    final ghUrl = release?["url"] ?? "";

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final hasUpdate = ghVersion.isNotEmpty &&
        ghUrl.isNotEmpty &&
        isVersionLower(currentVersion, ghVersion);

    if (!context.mounted) return false;

    // Maintenance mode, no update available
    if (isUnderMaintenance && !hasUpdate) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const _MaintenanceScreen()),
      );
      return true;
    }

    // Maintenance mode + update available -> force update
    if (isUnderMaintenance && hasUpdate) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ForceUpdateScreen(
            downloadUrl: ghUrl,
            latestVersion: ghVersion,
            currentVersion: currentVersion,
          ),
        ),
      );
      return true;
    }

    // Online, version mismatch -> force update
    if (!isUnderMaintenance && hasUpdate) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ForceUpdateScreen(
            downloadUrl: ghUrl,
            latestVersion: ghVersion,
            currentVersion: currentVersion,
          ),
        ),
      );
      return true;
    }

    // All good — proceed
    return false;
  } catch (_) {
    return false;
  }
}

class _MaintenanceScreen extends StatelessWidget {
  const _MaintenanceScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D7377),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.cloud_off, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 28),
                Text(
                  AppTranslations.get('Maintenance'),
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  AppTranslations.get('Service is under maintenance. Please try again later.'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

