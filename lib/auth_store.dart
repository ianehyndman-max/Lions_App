import 'package:shared_preferences/shared_preferences.dart';

class AuthStore {
  static Future<void> saveProfile(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_super', user['is_super'] == 1 || user['is_super'] == true);
    await prefs.setBool('is_admin', user['is_admin'] == 1 || user['is_admin'] == true);
    await prefs.setInt('member_id', int.tryParse(user['id'].toString()) ?? -1);
    await prefs.setInt('club_id', int.tryParse(user['lions_club_id'].toString()) ?? -1);
  }

  static Future<bool> isSuper() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_super') ?? false;
  }

  static Future<bool> isAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_admin') ?? false;
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