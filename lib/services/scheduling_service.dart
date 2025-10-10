import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/timetable_entry.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/utils/academic_year.dart';
import 'dart:math';

/// Naive timetable auto-scheduling helper.
///
/// - One session per subject by default.
/// - Avoids class and teacher conflicts.
/// - Uses provided days and timeSlots (e.g., ["08:00 - 09:00"]) to place entries.
class SchedulingService {
  final DatabaseService db;
  SchedulingService(this.db);

  int _parseHHmm(String t) {
    try {
      final parts = t.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      return h * 60 + m;
    } catch (_) {
      return 0;
    }
  }

  int _slotMinutes(String start, String end) {
    final sm = _parseHHmm(start);
    final em = _parseHHmm(end);
    final diff = em - sm;
    return diff > 0 ? diff : 60; // fallback 60min if invalid
  }

  int _hashSeed(String s) {
    int h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h == 0 ? 1 : h;
  }

  List<T> _shuffled<T>(List<T> items, Random rng) {
    final list = List<T>.from(items);
    for (int i = list.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
    return list;
  }

  /// Automatically generates a timetable for a given class.
  ///
  /// - If [clearExisting] is true, clears existing entries for the class/year.
  /// - [sessionsPerSubject] defines how many weekly sessions per subject to place.
  Future<int> autoGenerateForClass({
    required Class targetClass,
    required List<String> daysOfWeek,
    required List<String> timeSlots,
    Set<String> breakSlots = const {},
    bool clearExisting = false,
    int sessionsPerSubject = 1,
    bool enforceTeacherWeeklyHours = true,
    int? teacherMaxPerDay,
    int? classMaxPerDay,
    int? subjectMaxPerDay,
  }) async {
    final computedYear = targetClass.academicYear.isNotEmpty
        ? targetClass.academicYear
        : await getCurrentAcademicYear();

    if (clearExisting) {
      await db.deleteTimetableForClass(targetClass.name, computedYear);
    }

    // Get class subjects (fallback to all courses if none linked)
    List<Course> subjects = await db.getCoursesForClass(
      targetClass.name,
      computedYear,
    );
    if (subjects.isEmpty) {
      subjects = await db.getCourses();
    }

    // Diversify pattern per class using seeded shuffle
    final seedBase = '${targetClass.name}|$computedYear';
    final rng = Random(_hashSeed(seedBase));
    final daysOrder = _shuffled(daysOfWeek, rng);
    final slotsOrder = _shuffled(timeSlots, Random(rng.nextInt(1 << 31)));
    final subjectsOrder = _shuffled(subjects, Random(rng.nextInt(1 << 31)));

    // Build a quick teacher lookup: who can teach which subject for this class
    final teachers = await db.getStaff();
    Staff? findTeacherFor(String subject) {
      // First try a teacher assigned both the subject and the class
      final both = teachers.firstWhere(
        (t) =>
            t.courses.contains(subject) && t.classes.contains(targetClass.name),
        orElse: () => Staff.empty(),
      );
      if (both.id.isNotEmpty) return both;
      // Then any teacher who teaches the subject
      final any = teachers.firstWhere(
        (t) => t.courses.contains(subject),
        orElse: () => Staff.empty(),
      );
      return any.id.isNotEmpty ? any : null;
    }

    // Load current entries to detect conflicts
    List<TimetableEntry> current = await db.getTimetableEntries(
      className: targetClass.name,
      academicYear: computedYear,
    );

    final Map<String, int> classDailyCount = {};
    final Map<String, Map<String, int>> classSubjectDaily = {};
    for (final e in current) {
      final bySubj = classSubjectDaily[e.dayOfWeek] ?? <String,int>{};
      bySubj[e.subject] = (bySubj[e.subject] ?? 0) + 1;
      classSubjectDaily[e.dayOfWeek] = bySubj;
    }
    for (final e in current) {
      classDailyCount[e.dayOfWeek] = (classDailyCount[e.dayOfWeek] ?? 0) + 1;
    }

    // Track teacher weekly loads across all classes and unavailability
    final Map<String, int> teacherLoad = {};
    final teachersList = await db.getStaff();
    final Map<String, Set<String>> teacherUnavail = {};
    final Map<String, Map<String, int>> teacherDaily = {};
    for (final t in teachersList) {
      final entries = await db.getTimetableEntries(teacherName: t.name);
      int minutes = 0;
      for (final e in entries) {
        minutes += _slotMinutes(e.startTime, e.endTime);
      }
      teacherLoad[t.name] = minutes;
      final un = await db.getTeacherUnavailability(t.name, computedYear);
      teacherUnavail[t.name] = un
          .map((e) => '${e['dayOfWeek']}|${e['startTime']}')
          .toSet();
      final dayCount = <String, int>{};
      for (final e in entries) {
        dayCount[e.dayOfWeek] = (dayCount[e.dayOfWeek] ?? 0) + 1;
      }
      teacherDaily[t.name] = dayCount;
    }

    bool hasClassConflict(String day, String start) {
      return current.any(
        (e) =>
            e.dayOfWeek == day &&
            e.startTime == start &&
            e.className == targetClass.name,
      );
    }

    bool hasTeacherConflict(String teacher, String day, String start) {
      return current.any(
        (e) =>
            e.dayOfWeek == day && e.startTime == start && e.teacher == teacher,
      );
    }

    int created = 0;
    // Greedy placement: iterate subjects, place N sessions scanning days/timeSlots.
    for (final course in subjectsOrder) {
      final subj = course.name;
      final teacher = findTeacherFor(subj)?.name ?? '';
      int placed = 0;
      outer:
      for (final day in daysOrder) {
        for (final slot in slotsOrder) {
          if (breakSlots.contains(slot)) continue;
          final parts = slot.split(' - ');
          final start = parts.first;
          final end = parts.length > 1 ? parts[1] : parts.first;
          final slotMin = _slotMinutes(start, end);
          if (hasClassConflict(day, start)) continue;
          if (teacher.isNotEmpty && hasTeacherConflict(teacher, day, start))
            continue;
          if (teacher.isNotEmpty &&
              teacherUnavail[teacher]?.contains('$day|$start') == true)
            continue;

          if (classMaxPerDay != null && classMaxPerDay > 0) {
            final cnt = classDailyCount[day] ?? 0;
            if (cnt >= classMaxPerDay) continue;
          }

          if (subjectMaxPerDay != null && subjectMaxPerDay > 0) {
            final cntSubj = (classSubjectDaily[day] ?? const {})[subj] ?? 0;
            if (cntSubj >= subjectMaxPerDay) continue;
          }

          if (enforceTeacherWeeklyHours && teacher.isNotEmpty) {
            final max =
                teachersList
                    .firstWhere(
                      (t) => t.name == teacher,
                      orElse: () => Staff.empty(),
                    )
                    .weeklyHours ??
                0;
            final maxMin = max > 0 ? max * 60 : 0;
            if (maxMin > 0 && (teacherLoad[teacher] ?? 0) + slotMin > maxMin) continue;
          }
          if (teacherMaxPerDay != null &&
              teacherMaxPerDay > 0 &&
              teacher.isNotEmpty) {
            final perDay = teacherDaily[teacher]?[day] ?? 0;
            if (perDay >= teacherMaxPerDay) continue;
          }

          final entry = TimetableEntry(
            subject: subj,
            teacher: teacher,
            className: targetClass.name,
            academicYear: computedYear,
            dayOfWeek: day,
            startTime: start,
            endTime: end,
            room: '',
          );
          await db.insertTimetableEntry(entry);
          current = await db.getTimetableEntries(
            className: targetClass.name,
            academicYear: computedYear,
          );
          if (teacher.isNotEmpty) {
            teacherLoad[teacher] = (teacherLoad[teacher] ?? 0) + slotMin;
            teacherDaily[teacher]![day] =
                (teacherDaily[teacher]![day] ?? 0) + 1;
          }
          classDailyCount[day] = (classDailyCount[day] ?? 0) + 1;
          final bySubj = classSubjectDaily[day] ?? <String,int>{};
          bySubj[subj] = (bySubj[subj] ?? 0) + 1;
          classSubjectDaily[day] = bySubj;
          created++;
          placed++;
          if (placed >= sessionsPerSubject) break outer;
        }
      }
    }

    return created;
  }

  /// Saturate all available time slots for a class across selected days/time slots.
  /// Ignores per-day/weekly limits to fully fill the grid while avoiding conflicts
  /// and respecting teacher unavailability and existing entries.
  Future<int> autoSaturateForClass({
    required Class targetClass,
    required List<String> daysOfWeek,
    required List<String> timeSlots,
    Set<String> breakSlots = const {},
    bool clearExisting = false,
  }) async {
    final computedYear = targetClass.academicYear.isNotEmpty
        ? targetClass.academicYear
        : await getCurrentAcademicYear();

    if (clearExisting) {
      await db.deleteTimetableForClass(targetClass.name, computedYear);
    }

    // Subjects for the class; fallback to all
    List<Course> subjects = await db.getCoursesForClass(
      targetClass.name,
      computedYear,
    );
    if (subjects.isEmpty) subjects = await db.getCourses();
    if (subjects.isEmpty) return 0;

    final teachers = await db.getStaff();

    List<Staff> candidatesFor(String subj) {
      final both = teachers
          .where((t) =>
              t.courses.contains(subj) && t.classes.contains(targetClass.name))
          .toList();
      final any = teachers.where((t) => t.courses.contains(subj)).toList();
      return both.isNotEmpty ? both : any;
    }

    // Busy map for teachers across all classes
    final Map<String, Set<String>> teacherBusy = {};
    final allEntries = await db.getTimetableEntries();
    for (final e in allEntries) {
      teacherBusy.putIfAbsent(e.teacher, () => <String>{}).add('${e.dayOfWeek}|${e.startTime}');
    }
    // Teacher unavailability map for current year
    final Map<String, Set<String>> teacherUnavail = {};
    for (final t in teachers) {
      final un = await db.getTeacherUnavailability(t.name, computedYear);
      teacherUnavail[t.name] =
          un.map((e) => '${e['dayOfWeek']}|${e['startTime']}').toSet();
    }

    // Occupied slots for this class
    final classEntries = await db.getTimetableEntries(
      className: targetClass.name,
      academicYear: computedYear,
    );
    final Set<String> classBusy =
        classEntries.map((e) => '${e.dayOfWeek}|${e.startTime}').toSet();

    // Shuffle orders deterministically per class to diversify
    final rng = Random(_hashSeed('${targetClass.name}|$computedYear|sat'));
    final daysOrder = _shuffled(daysOfWeek, rng);
    final slotsOrder = _shuffled(timeSlots, Random(rng.nextInt(1 << 31)));
    final subjOrder = _shuffled(subjects, Random(rng.nextInt(1 << 31)));

    int created = 0;
    int idx = subjOrder.isNotEmpty ? rng.nextInt(subjOrder.length) : 0;
    for (final day in daysOrder) {
      for (final slot in slotsOrder) {
        if (breakSlots.contains(slot)) continue;
        final start = slot.split(' - ').first;
        final key = '$day|$start';
        if (classBusy.contains(key)) continue; // already has an entry

        // Choose subject in round-robin
        final subj = subjOrder[idx % subjOrder.length].name;
        idx++;

        // Find teacher without conflict/unavailability
        String teacherName = '';
        final shuffledCands = _shuffled(
          candidatesFor(subj),
          Random(_hashSeed('${targetClass.name}|$computedYear|$day|$start|$subj')),
        );
        for (final cand in shuffledCands) {
          final busy = teacherBusy[cand.name] ?? const <String>{};
          final un = teacherUnavail[cand.name] ?? const <String>{};
          if (busy.contains(key)) continue;
          if (un.contains(key)) continue;
          teacherName = cand.name;
          break;
        }

        final parts = slot.split(' - ');
        final end = parts.length > 1 ? parts[1] : parts.first;
        final entry = TimetableEntry(
          subject: subj,
          teacher: teacherName,
          className: targetClass.name,
          academicYear: computedYear,
          dayOfWeek: day,
          startTime: start,
          endTime: end,
          room: '',
        );
        await db.insertTimetableEntry(entry);
        classBusy.add(key);
        if (teacherName.isNotEmpty) {
          teacherBusy.putIfAbsent(teacherName, () => <String>{}).add(key);
        }
        created++;
      }
    }

    return created;
  }

  /// Saturate for a teacher across their assigned classes, filling free slots.
  Future<int> autoSaturateForTeacher({
    required Staff teacher,
    required List<String> daysOfWeek,
    required List<String> timeSlots,
    Set<String> breakSlots = const {},
    bool clearExisting = false,
  }) async {
    final computedYear = await getCurrentAcademicYear();
    if (clearExisting) {
      await db.deleteTimetableForTeacher(teacher.name, academicYear: computedYear);
    }

    // Teacher busy + unavailability
    final Set<String> tBusy = (await db.getTimetableEntries(teacherName: teacher.name))
        .map((e) => '${e.dayOfWeek}|${e.startTime}')
        .toSet();
    final tUn = (await db.getTeacherUnavailability(teacher.name, computedYear))
        .map((e) => '${e['dayOfWeek']}|${e['startTime']}')
        .toSet();

    // Class busy maps and class subjects intersection with teacher courses
    final classes = await db.getClasses();
    final rng = Random(_hashSeed('satteach|${teacher.name}|$computedYear'));
    final Map<String, Set<String>> classBusy = {};
    final Map<String, List<String>> classTeachables = {};
    final teacherClasses = _shuffled(teacher.classes, rng);
    for (final className in teacherClasses) {
      final cls = classes.firstWhere(
        (c) => c.name == className && c.academicYear == computedYear,
        orElse: () => Class(name: className, academicYear: computedYear),
      );
      final entries = await db.getTimetableEntries(
        className: cls.name,
        academicYear: cls.academicYear,
      );
      classBusy[cls.name] = entries.map((e) => '${e.dayOfWeek}|${e.startTime}').toSet();
      final classSubjects = await db.getCoursesForClass(cls.name, cls.academicYear);
      final teachable = classSubjects
          .where((c) => teacher.courses.contains(c.name))
          .map((c) => c.name)
          .toList();
      if (teachable.isEmpty) {
        final all = await db.getCourses();
        classTeachables[cls.name] = all
            .where((c) => teacher.courses.contains(c.name))
            .map((c) => c.name)
            .toList();
      } else {
        classTeachables[cls.name] = teachable;
      }
    }

    final Map<String, int> rrIndex = {};
    int created = 0;
    for (final day in _shuffled(daysOfWeek, rng)) {
      for (final slot in _shuffled(timeSlots, Random(rng.nextInt(1 << 31)))) {
        if (breakSlots.contains(slot)) continue;
        final start = slot.split(' - ').first;
        final key = '$day|$start';
        if (tBusy.contains(key) || tUn.contains(key)) continue;
        // Try to place teacher in one of their classes with a teachable subject
        bool placed = false;
        for (final className in teacher.classes) {
          final cb = classBusy[className] ?? <String>{};
          if (cb.contains(key)) continue;
          final teachables = classTeachables[className] ?? const <String>[];
          if (teachables.isEmpty) continue;
          final idx = (rrIndex[className] ?? 0) % teachables.length;
          final subj = teachables[idx];
          rrIndex[className] = idx + 1;
          final end = slot.split(' - ').length > 1
              ? slot.split(' - ')[1]
              : slot.split(' - ').first;
          final entry = TimetableEntry(
            subject: subj,
            teacher: teacher.name,
            className: className,
            academicYear: computedYear,
            dayOfWeek: day,
            startTime: start,
            endTime: end,
            room: '',
          );
          await db.insertTimetableEntry(entry);
          tBusy.add(key);
          cb.add(key);
          classBusy[className] = cb;
          created++;
          placed = true;
          break;
        }
        // If teacher cannot be placed in any class, leave the slot empty for teacher view
        if (!placed) {
          continue;
        }
      }
    }

    return created;
  }

  /// Auto-generate for a teacher across their assigned classes.
  Future<int> autoGenerateForTeacher({
    required Staff teacher,
    required List<String> daysOfWeek,
    required List<String> timeSlots,
    Set<String> breakSlots = const {},
    bool clearExisting = false,
    int sessionsPerSubject = 1,
    bool enforceTeacherWeeklyHours = true,
    int? teacherMaxPerDay,
    int? teacherWeeklyHours,
    int? classMaxPerDay,
    int? subjectMaxPerDay,
  }) async {
    final computedYear = await getCurrentAcademicYear();
    if (clearExisting) {
      await db.deleteTimetableForTeacher(
        teacher.name,
        academicYear: computedYear,
      );
    }

    int created = 0;
    int teacherLoad = 0;
    final Map<String, int> teacherDaily = {};
    final existingForTeacher = await db.getTimetableEntries(
      teacherName: teacher.name,
    );
    for (final e in existingForTeacher) {
      teacherDaily[e.dayOfWeek] = (teacherDaily[e.dayOfWeek] ?? 0) + 1;
      teacherLoad += _slotMinutes(e.startTime, e.endTime);
    }
    final Set<String> teacherUnavail = (await db.getTeacherUnavailability(
      teacher.name,
      computedYear,
    )).map((e) => '${e['dayOfWeek']}|${e['startTime']}').toSet();

    // Iterate classes the teacher is assigned to, shuffled per teacher
    final classes = await db.getClasses();
    final rng = Random(_hashSeed('teach|${teacher.name}|$computedYear'));
    final teacherClasses = _shuffled(teacher.classes, rng);
    for (final className in teacherClasses) {
      final cls = classes.firstWhere(
        (c) => c.name == className && c.academicYear == computedYear,
        orElse: () => Class(name: className, academicYear: computedYear),
      );

      // Only subjects that the teacher teaches and that are assigned to the class
      final classSubjects = await db.getCoursesForClass(
        cls.name,
        cls.academicYear,
      );
      final teachable = classSubjects
          .where((c) => teacher.courses.contains(c.name))
          .toList();

      List<TimetableEntry> current = await db.getTimetableEntries(
        className: cls.name,
        academicYear: cls.academicYear,
      );

      final Map<String, int> classSubjectDaily = {};
      for (final e in current) {
        classSubjectDaily["${e.dayOfWeek}|${e.subject}"] = (classSubjectDaily["${e.dayOfWeek}|${e.subject}"] ?? 0) + 1;
      }

      bool hasClassConflict(String day, String start) => current.any(
        (e) =>
            e.dayOfWeek == day &&
            e.startTime == start &&
            e.className == cls.name,
      );
      bool hasTeacherConflict(String day, String start) => current.any(
        (e) =>
            e.dayOfWeek == day &&
            e.startTime == start &&
            e.teacher == teacher.name,
      );

      final shuffledTeachables = _shuffled(teachable, Random(rng.nextInt(1 << 31)));
      for (final course in shuffledTeachables) {
        int placed = 0;
        outer:
        for (final day in _shuffled(daysOfWeek, Random(rng.nextInt(1 << 31)))) {
          for (final slot in _shuffled(timeSlots, Random(rng.nextInt(1 << 31)))) {
            if (breakSlots.contains(slot)) continue;
            final parts = slot.split(' - ');
            final start = parts.first;
            final end = parts.length > 1 ? parts[1] : parts.first;
            final slotMin = _slotMinutes(start, end);
            if (hasClassConflict(day, start)) continue;
            if (hasTeacherConflict(day, start)) continue;
            if (teacherMaxPerDay != null && teacherMaxPerDay > 0) {
              final cnt = teacherDaily[day] ?? 0;
              if (cnt >= teacherMaxPerDay) continue;
            }
            if (teacherUnavail.contains('$day|$start')) continue;
            if (classMaxPerDay != null && classMaxPerDay > 0) {
              final cntClass = current.where((e) => e.dayOfWeek == day).length;
              if (cntClass >= classMaxPerDay) continue;
            }
            if (subjectMaxPerDay != null && subjectMaxPerDay > 0) {
              final key = "$day|${course.name}";
              final cntSubj = classSubjectDaily[key] ?? 0;
              if (cntSubj >= subjectMaxPerDay) continue;
            }
            if (enforceTeacherWeeklyHours) {
              final max = (teacherWeeklyHours ?? teacher.weeklyHours) ?? 0;
              final maxMin = max > 0 ? max * 60 : 0;
              if (maxMin > 0 && teacherLoad + slotMin > maxMin) continue;
            }

            final entry = TimetableEntry(
              subject: course.name,
              teacher: teacher.name,
              className: cls.name,
              academicYear: cls.academicYear,
              dayOfWeek: day,
              startTime: start,
              endTime: end,
              room: '',
            );
            await db.insertTimetableEntry(entry);
            current = await db.getTimetableEntries(
              className: cls.name,
              academicYear: cls.academicYear,
            );
            teacherLoad += slotMin;
            teacherDaily[day] = (teacherDaily[day] ?? 0) + 1;
            final key = "$day|${course.name}";
            classSubjectDaily[key] = (classSubjectDaily[key] ?? 0) + 1;
            created++;
            placed++;
            if (placed >= sessionsPerSubject) break outer;
          }
        }
      }
    }

    return created;
  }
}
