import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _kDaysKey = 'timetable_days';
const _kSlotsKey = 'timetable_slots';
const _kBreakSlotsKey = 'timetable_break_slots';
const _kClassBreakSlotsMapKey = 'timetable_class_break_slots_map';
const _kMorningStartKey = 'timetable_morning_start';
const _kMorningEndKey = 'timetable_morning_end';
const _kAfternoonStartKey = 'timetable_afternoon_start';
const _kAfternoonEndKey = 'timetable_afternoon_end';
const _kSessionMinutesKey = 'timetable_session_minutes';
const _kBlockDefaultSlotsKey = 'timetable_block_default_slots';
const _kThreeHourThresholdKey = 'timetable_three_hour_threshold';
const _kOptionalMaxMinutesKey = 'timetable_optional_max_minutes';
const _kCapTwoHourBlocksWeeklyKey = 'timetable_cap_two_hour_blocks_weekly';
const _kTwoHourCapExcludedSubjectsKey = 'timetable_two_hour_cap_excluded_subjects';
const _kGridZoomKey = 'timetable_grid_zoom';
const _kLeftPanelWidthKey = 'timetable_left_panel_width';
const _kShowSummariesKey = 'timetable_show_summaries';
const _kShowClassListKey = 'timetable_show_class_list';
const _kTimetableTourSeenKey = 'timetable_tour_seen';

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

// Per-class break slots mapping
Future<Map<String, Set<String>>> loadClassBreakSlotsMap() async {
  final p = await SharedPreferences.getInstance();
  final s = p.getString(_kClassBreakSlotsMapKey);
  if (s == null || s.isEmpty) return <String, Set<String>>{};
  try {
    final raw = jsonDecode(s);
    if (raw is Map<String, dynamic>) {
      final out = <String, Set<String>>{};
      raw.forEach((k, v) {
        if (v is List) {
          out[k] = v.map<String>((e) => e.toString()).toSet();
        }
      });
      return out;
    }
  } catch (_) {}
  return <String, Set<String>>{};
}

Future<void> saveClassBreakSlotsMap(Map<String, Set<String>> map) async {
  final p = await SharedPreferences.getInstance();
  final enc = <String, List<String>>{};
  map.forEach((k, v) => enc[k] = v.toList());
  await p.setString(_kClassBreakSlotsMapKey, jsonEncode(enc));
}

Future<void> saveClassBreaksForClasses(Set<String> classKeys, Set<String> breaks) async {
  final current = await loadClassBreakSlotsMap();
  for (final key in classKeys) {
    current[key] = Set<String>.from(breaks);
  }
  await saveClassBreakSlotsMap(current);
}

Future<Set<String>> loadBreakSlotsForClass(String classKey) async {
  final map = await loadClassBreakSlotsMap();
  return map[classKey] ?? <String>{};
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

Future<int> loadOptionalMaxMinutes() async {
  final p = await SharedPreferences.getInstance();
  return p.getInt(_kOptionalMaxMinutesKey) ?? 120;
}

Future<void> saveOptionalMaxMinutes(int minutes) async {
  final p = await SharedPreferences.getInstance();
  await p.setInt(_kOptionalMaxMinutesKey, minutes);
}

Future<bool> loadCapTwoHourBlocksWeekly() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kCapTwoHourBlocksWeeklyKey) ?? true;
}

Future<void> saveCapTwoHourBlocksWeekly(bool value) async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kCapTwoHourBlocksWeeklyKey, value);
}

Future<Set<String>> loadTwoHourCapExcludedSubjects() async {
  final p = await SharedPreferences.getInstance();
  final s = p.getString(_kTwoHourCapExcludedSubjectsKey);
  if (s == null || s.isEmpty) return <String>{};
  final data = jsonDecode(s);
  if (data is List) return data.map<String>((e) => e.toString()).toSet();
  return <String>{};
}

Future<void> saveTwoHourCapExcludedSubjects(Set<String> subjects) async {
  final p = await SharedPreferences.getInstance();
  await p.setString(_kTwoHourCapExcludedSubjectsKey, jsonEncode(subjects.toList()));
}

// UI preferences
Future<double> loadGridZoom() async {
  final p = await SharedPreferences.getInstance();
  final v = p.getDouble(_kGridZoomKey);
  if (v != null && v > 0.2 && v < 5.0) return v;
  // Backward compatibility if stored as string
  final s = p.getString(_kGridZoomKey);
  final parsed = s != null ? double.tryParse(s) : null;
  if (parsed != null && parsed > 0.2 && parsed < 5.0) return parsed;
  return 1.0;
}

Future<void> saveGridZoom(double zoom) async {
  final p = await SharedPreferences.getInstance();
  await p.setDouble(_kGridZoomKey, zoom);
}

Future<double> loadLeftPanelWidth() async {
  final p = await SharedPreferences.getInstance();
  return p.getDouble(_kLeftPanelWidthKey) ?? 200.0;
}

Future<void> saveLeftPanelWidth(double width) async {
  final p = await SharedPreferences.getInstance();
  await p.setDouble(_kLeftPanelWidthKey, width);
}

Future<bool> loadShowSummaries() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kShowSummariesKey) ?? false;
}

Future<void> saveShowSummaries(bool value) async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kShowSummariesKey, value);
}

Future<bool> loadShowClassList() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kShowClassListKey) ?? true;
}

Future<void> saveShowClassList(bool value) async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kShowClassListKey, value);
}

Future<bool> loadTimetableTourSeen() async {
  final p = await SharedPreferences.getInstance();
  return p.getBool(_kTimetableTourSeenKey) ?? false;
}

Future<void> saveTimetableTourSeen(bool value) async {
  final p = await SharedPreferences.getInstance();
  await p.setBool(_kTimetableTourSeenKey, value);
}
