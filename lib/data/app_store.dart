import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class AppStore {
  static const _key = 'club_attendance_app_data';

  Future<AppData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AppData.initial();
    return AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(AppData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
  }
}
