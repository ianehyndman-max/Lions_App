import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

class AuthStore {
  static bool _isTruthy(dynamic value) {
    return value == 1 ||
        value == true ||
        value == '1' ||
        (value is List && value.isNotEmpty && value[0] == 1);
  }

  static Future<void> saveProfile(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_super', _isTruthy(user['is_super']));
    await prefs.setBool('is_admin', _isTruthy(user['is_admin']));
    await prefs.setBool(
        'is_conference_member', _isTruthy(user['is_conference_member']));
    await prefs.setInt('member_id', int.tryParse(user['id'].toString()) ?? -1);
    await prefs.setInt('club_id', int.tryParse(user['lions_club_id'].toString()) ?? -1);
  }

  static Future<void> refreshProfile() async {
    final memberId = await getMemberId();
    if (memberId == null) return;

    final res = await ApiClient.get('/members/$memberId');
    if (res.statusCode != 200) return;

    final body = jsonDecode(res.body);
    if (body is Map<String, dynamic>) {
      await saveProfile(body);
    }
  }

  static Future<bool> isSuper() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_super') ?? false;
  }

  static Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_admin') ?? false;
  }

  static Future<bool> isConferenceMember() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_conference_member') ?? false;
  }

  static Future<int?> getMemberId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('member_id');
    return (id == null || id < 0) ? null : id;
  }

  static Future<int?> getClubId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt('club_id');
    return (id == null || id < 0) ? null : id;
  }
}