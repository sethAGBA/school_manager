import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _kDaysKey = 'timetable_days';
const _kSlotsKey = 'timetable_slots';
const _kBreakSlotsKey = 'timetable_break_slots';

const List<String> kDefaultDays = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
];

const List<String> kDefaultSlots = [
  '08:00 - 09:00',
  '09:00 - 10:00',
  '10:00 - 11:00',
  '11:00 - 12:00',
  '13:00 - 14:00',
  '14:00 - 15:00',
  '15:00 - 16:00',
];

Future<List<String>> loadDays() async {
  final p = await SharedPreferences.getInstance();
  final s = p.getString(_kDaysKey);
  if (s == null || s.isEmpty) return List.of(kDefaultDays);
  final data = jsonDecode(s);
  if (data is List) return data.map<String>((e) => e.toString()).toList();
  return List.of(kDefaultDays);
}

Future<void> saveDays(List<String> days) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kDaysKey, jsonEncode(days));
}

Future<List<String>> loadSlots() async {
  final p = await SharedPreferences.getInstance();
  final s = p.getString(_kSlotsKey);
  if (s == null || s.isEmpty) return List.of(kDefaultSlots);
  final data = jsonDecode(s);
  if (data is List) return data.map<String>((e) => e.toString()).toList();
  return List.of(kDefaultSlots);
}

Future<void> saveSlots(List<String> slots) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kSlotsKey, jsonEncode(slots));
}

Future<Set<String>> loadBreakSlots() async {
  final p = await SharedPreferences.getInstance();
  final s = p.getString(_kBreakSlotsKey);
  if (s == null || s.isEmpty) return <String>{};
  final data = jsonDecode(s);
  if (data is List) return data.map<String>((e) => e.toString()).toSet();
  return <String>{};
}

Future<void> saveBreakSlots(Set<String> breaks) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kBreakSlotsKey, jsonEncode(breaks.toList()));
}
