import 'package:shared_preferences/shared_preferences.dart';

class OfflineSettings {
  static const _wifiOnlyKey = 'offline_wifi_only';
  static const _limitMbKey = 'offline_storage_limit_mb';

  Future<bool> wifiOnly() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_wifiOnlyKey) ?? false;
  }

  Future<void> setWifiOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wifiOnlyKey, value);
  }

  Future<int> limitMb() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_limitMbKey) ?? 500;
  }

  Future<void> setLimitMb(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final safe = value < 100 ? 100 : (value > 5000 ? 5000 : value);
    await prefs.setInt(_limitMbKey, safe);
  }
}
