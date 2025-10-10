import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _kDaysKey = 'timetable_days';
const _kSlotsKey = 'timetable_slots';
const _kBreakSlotsKey = 'timetable_break_slots';
const _kMorningStartKey = 'timetable_morning_start';
const _kMorningEndKey = 'timetable_morning_end';
const _kAfternoonStartKey = 'timetable_afternoon_start';
const _kAfternoonEndKey = 'timetable_afternoon_end';
const _kSessionMinutesKey = 'timetable_session_minutes';
const _kBlockDefaultSlotsKey = 'timetable_block_default_slots';
const _kThreeHourThresholdKey = 'timetable_three_hour_threshold';

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

Future<String> loadMorningStart() async {
  final p = await SharedPreferences.getInstance();
  return p.getString(_kMorningStartKey) ?? '08:00';
}

Future<String> loadMorningEnd() async {
  final p = await SharedPreferences.getInstance();
  return p.getString(_kMorningEndKey) ?? '12:00';
}

Future<String> loadAfternoonStart() async {
  final p = await SharedPreferences.getInstance();
  return p.getString(_kAfternoonStartKey) ?? '13:00';
}

Future<String> loadAfternoonEnd() async {
  final p = await SharedPreferences.getInstance();
  return p.getString(_kAfternoonEndKey) ?? '16:00';
}

Future<int> loadSessionMinutes() async {
  final p = await SharedPreferences.getInstance();
  return p.getInt(_kSessionMinutesKey) ?? 60;
}

Future<void> saveMorningStart(String v) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kMorningStartKey, v);
}

Future<void> saveMorningEnd(String v) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kMorningEndKey, v);
}

Future<void> saveAfternoonStart(String v) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kAfternoonStartKey, v);
}

Future<void> saveAfternoonEnd(String v) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kAfternoonEndKey, v);
}

Future<void> saveSessionMinutes(int minutes) async {
  final p = await SharedPreferences.getInstance();
  await p.setInt(_kSessionMinutesKey, minutes);
}

Future<int> loadBlockDefaultSlots() async {
  final p = await SharedPreferences.getInstance();
  return p.getInt(_kBlockDefaultSlotsKey) ?? 2;
}

Future<void> saveBlockDefaultSlots(int slots) async {
  final p = await SharedPreferences.getInstance();
  await p.setInt(_kBlockDefaultSlotsKey, slots);
}

Future<double> loadThreeHourThreshold() async {
  final p = await SharedPreferences.getInstance();
  final val = p.getDouble(_kThreeHourThresholdKey);
  if (val != null) return val;
  final asString = p.getString(_kThreeHourThresholdKey);
  if (asString != null) {
    final parsed = double.tryParse(asString);
    if (parsed != null) return parsed;
  }
  return 1.5;
}

Future<void> saveThreeHourThreshold(double v) async {
  final p = await SharedPreferences.getInstance();
  await p.setDouble(_kThreeHourThresholdKey, v);
}
