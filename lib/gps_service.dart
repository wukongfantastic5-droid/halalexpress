import 'package:geolocator/geolocator.dart';

class GPSService {

  static Future<bool> ensureGPS() async {

    bool serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {

      await Geolocator.openLocationSettings();

      return false;
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {

      permission =
          await Geolocator.requestPermission();
    }

    if (permission ==
        LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }
}