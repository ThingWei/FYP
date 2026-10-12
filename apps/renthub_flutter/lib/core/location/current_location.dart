import 'package:geolocator/geolocator.dart';

class CurrentLocationFailure implements Exception {
  const CurrentLocationFailure(this.message,
      {this.appSettings, this.locationSettings});
  final String message;
  final bool? appSettings, locationSettings;
}

class CurrentLocationReading {
  const CurrentLocationReading(this.latitude, this.longitude, this.accuracy,
      {this.approximate = false});
  final double latitude, longitude, accuracy;
  final bool approximate;
}

abstract class CurrentLocationClient {
  Future<CurrentLocationReading> current();
  Future<void> settings({required bool app});
}

class AndroidCurrentLocationClient implements CurrentLocationClient {
  @override
  Future<CurrentLocationReading> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const CurrentLocationFailure(
          'Location services are off. Turn them on or place the pin manually.',
          locationSettings: true);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const CurrentLocationFailure(
          'Location permission is blocked. Allow it in Android settings or place the pin manually.',
          appSettings: true);
    }
    if (permission == LocationPermission.denied) {
      throw const CurrentLocationFailure(
          'Location permission was not granted. Search or place the pin manually.');
    }
    final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)));
    final accuracy = await Geolocator.getLocationAccuracy();
    return CurrentLocationReading(
        position.latitude, position.longitude, position.accuracy,
        approximate: accuracy == LocationAccuracyStatus.reduced);
  }

  @override
  Future<void> settings({required bool app}) async {
    if (app) {
      await Geolocator.openAppSettings();
    } else {
      await Geolocator.openLocationSettings();
    }
  }
}
