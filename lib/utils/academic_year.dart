import 'package:shared_preferences/shared_preferences.dart';

Future<String> getCurrentAcademicYear() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('academic_year') ?? '2024-2025';
} 