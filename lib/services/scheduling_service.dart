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

    // Get class subjects (assigned to class)
    List<Course> subjects = await db.getCoursesForClass(
      targetClass.name,
      computedYear,
    );
    // If no subjects assigned, skip to avoid using a shared template across classes
    if (subjects.isEmpty) return 0;

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

    // Busy map for teachers across all classes to avoid same-hour clashes
    final Map<String, Set<String>> teacherBusyAll = {};
    final allEntriesForBusy = await db.getTimetableEntries();
    for (final e in allEntriesForBusy) {
      teacherBusyAll.putIfAbsent(e.teacher, () => <String>{}).add('${e.dayOfWeek}|${e.startTime}');
    }

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

    // Determine target weekly sessions per subject (weighted by coefficients)
    bool isOptional(Course c) => (c.categoryId ?? '').toLowerCase() == 'optional';
    bool isEPS(String name) {
      final s = name.toLowerCase();
      return s.contains('eps') || s.contains('sport') || s.contains('éducation physique') || s.contains('education physique');
    }
    final Map<String, int> targetSessions = {};
    final Map<String, int> optionalMinutes = {}; // subject -> minutes placed
    const int optionalMaxMinutes = 120; // 2h max/semaine
    // Weight by coefficients: need = round((coeff/avgCoeff) * sessionsPerSubject)
    final coeffs = await db.getClassSubjectCoefficients(targetClass.name, computedYear);
    double sumCoeff = 0;
    int countCoeff = 0;
    for (final c in subjects) {
      if (isOptional(c) || isEPS(c.name)) continue;
      final w = coeffs[c.name] ?? 1.0;
      sumCoeff += w;
      countCoeff++;
    }
    final avgCoeff = (countCoeff > 0 && sumCoeff > 0) ? (sumCoeff / countCoeff) : 1.0;
    for (final c in subjectsOrder) {
      if (isOptional(c)) {
        targetSessions[c.name] = 2; // cap by 2h; actual cap enforced by minutes
        optionalMinutes[c.name] = 0;
      } else if (isEPS(c.name)) {
        targetSessions[c.name] = 2; // two 1h sessions on different days
      } else {
        final w = coeffs[c.name] ?? 1.0;
        final scaled = (w / (avgCoeff <= 0 ? 1.0 : avgCoeff)) * sessionsPerSubject;
        final need = scaled.round().clamp(1, 1000);
        targetSessions[c.name] = need;
      }
    }

    // Seed optional minutes from existing timetable
    for (final e in current) {
      if (subjects.any((c) => c.name == e.subject && isOptional(c))) {
        final sm = _parseHHmm(e.startTime);
        final em = _parseHHmm(e.endTime);
        final diff = em > sm ? (em - sm) : 0;
        optionalMinutes[e.subject] = (optionalMinutes[e.subject] ?? 0) + diff;
      }
    }

    final Set<String> epsDaysUsed = {};

    int created = 0;
    // Greedy placement: iterate subjects, place target sessions scanning shuffled days/timeSlots.
    for (final course in subjectsOrder) {
      final subj = course.name;
      final teacher = findTeacherFor(subj)?.name ?? '';
      final need = (targetSessions[subj] ?? sessionsPerSubject).clamp(0, 1000);
      int placed = 0;
      outer:
      for (final day in daysOrder) {
        // EPS: ensure different days if possible
        if (isEPS(subj) && epsDaysUsed.contains(day) && epsDaysUsed.length < daysOrder.length) {
          continue;
        }
        for (final slot in slotsOrder) {
          if (breakSlots.contains(slot)) continue;
          final parts = slot.split(' - ');
          final start = parts.first;
          final end = parts.length > 1 ? parts[1] : parts.first;
          final slotMin = _slotMinutes(start, end);
          // Optional cap by minutes
          if (isOptional(course)) {
            final placedMin = optionalMinutes[subj] ?? 0;
            if (placedMin + slotMin > optionalMaxMinutes) continue;
          }
          if (hasClassConflict(day, start)) continue;
          // Avoid teacher clash across other classes at same hour
          if (teacher.isNotEmpty && (teacherBusyAll[teacher]?.contains('$day|$start') ?? false))
            continue;
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
            teacherBusyAll.putIfAbsent(teacher, () => <String>{}).add('$day|$start');
          }
          classDailyCount[day] = (classDailyCount[day] ?? 0) + 1;
          final bySubj = classSubjectDaily[day] ?? <String,int>{};
          bySubj[subj] = (bySubj[subj] ?? 0) + 1;
          classSubjectDaily[day] = bySubj;
          created++;
          placed++; // count 1 block
          if (isEPS(subj)) epsDaysUsed.add(day);
          if (isOptional(course)) {
            optionalMinutes[subj] = (optionalMinutes[subj] ?? 0) + slotMin;
          }
          // Determine block size: 1 for EPS, 2 for default, 3 for high coeff; facultatives up to 2h max
          int blockSlots = 2;
          final wSubj = coeffs[subj] ?? 1.0;
          if (isEPS(subj)) blockSlots = 1;
          else if (isOptional(course)) {
            // allow chaining 2 slots if cap allows, otherwise 1
            final remaining = optionalMaxMinutes - (optionalMinutes[subj] ?? 0);
            blockSlots = remaining >= (2 * slotMin) ? 2 : 1;
          } else if (wSubj >= avgCoeff * 1.5) {
            blockSlots = 3;
          } else {
            blockSlots = 2;
          }
          // Try to chain next contiguous slots within same day
          if (blockSlots > 1) {
            final allSlots = timeSlots; // original order
            final idxSlot = allSlots.indexOf(slot);
            for (int chain = 1; chain < blockSlots; chain++) {
              final nextIdx = idxSlot + chain;
              if (nextIdx >= allSlots.length) break;
              final nextSlot = allSlots[nextIdx];
              if (breakSlots.contains(nextSlot)) break;
              final nParts = nextSlot.split(' - ');
              final nStart = nParts.first;
              final nEnd = nParts.length > 1 ? nParts[1] : nParts.first;
              final nMin = _slotMinutes(nStart, nEnd);
              // Optional cap
              if (isOptional(course)) {
                final used = optionalMinutes[subj] ?? 0;
                if (used + nMin > optionalMaxMinutes) break;
              }
              // Conflicts
              if (hasClassConflict(day, nStart)) break;
              if (teacher.isNotEmpty && (teacherBusyAll[teacher]?.contains('$day|$nStart') ?? false)) break;
              if (teacher.isNotEmpty && hasTeacherConflict(teacher, day, nStart)) break;
              if (teacher.isNotEmpty && (teacherUnavail[teacher]?.contains('$day|$nStart') == true)) break;
              // Place chained slot
              final e2 = TimetableEntry(
                subject: subj,
                teacher: teacher,
                className: targetClass.name,
                academicYear: computedYear,
                dayOfWeek: day,
                startTime: nStart,
                endTime: nEnd,
                room: '',
              );
              await db.insertTimetableEntry(e2);
              current = await db.getTimetableEntries(
                className: targetClass.name,
                academicYear: computedYear,
              );
              if (teacher.isNotEmpty) {
                teacherLoad[teacher] = (teacherLoad[teacher] ?? 0) + nMin;
                teacherDaily[teacher]![day] = (teacherDaily[teacher]![day] ?? 0) + 1;
                teacherBusyAll.putIfAbsent(teacher, () => <String>{}).add('$day|$nStart');
              }
              classDailyCount[day] = (classDailyCount[day] ?? 0) + 1;
              final byS = classSubjectDaily[day] ?? <String,int>{};
              byS[subj] = (byS[subj] ?? 0) + 1;
              classSubjectDaily[day] = byS;
              created++;
              if (isOptional(course)) {
                optionalMinutes[subj] = (optionalMinutes[subj] ?? 0) + nMin;
              }
            }
          }
          if (placed >= need) break outer;
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

    // Optional cap tracking (per subject) by minutes (seeded from existing)
    const int optionalMaxMinutes = 120;
    final Map<String, int> optionalMinutes = {
      for (final c in subjects)
        if ((c.categoryId ?? '').toLowerCase() == 'optional') c.name: 0
    };
    for (final e in classEntries) {
      if (optionalMinutes.containsKey(e.subject)) {
        final sm = _parseHHmm(e.startTime);
        final em = _parseHHmm(e.endTime);
        final diff = em > sm ? (em - sm) : 0;
        optionalMinutes[e.subject] = (optionalMinutes[e.subject] ?? 0) + diff;
      }
    }

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

        // Enforce optional cap per subject for this class
        final parts = slot.split(' - ');
        final end = parts.length > 1 ? parts[1] : parts.first;
        final slotMin = _slotMinutes(parts.first, end);
        if (optionalMinutes.containsKey(subj)) {
          final used = optionalMinutes[subj] ?? 0;
          if (used + slotMin > optionalMaxMinutes) continue;
        }

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

        final entry = TimetableEntry(
          subject: subj,
          teacher: teacherName,
          className: targetClass.name,
          academicYear: computedYear,
          dayOfWeek: day,
          startTime: parts.first,
          endTime: end,
          room: '',
        );
        await db.insertTimetableEntry(entry);
        classBusy.add(key);
        if (teacherName.isNotEmpty) {
          teacherBusy.putIfAbsent(teacherName, () => <String>{}).add(key);
        }
        created++;
        if (optionalMinutes.containsKey(subj)) {
          optionalMinutes[subj] = (optionalMinutes[subj] ?? 0) + slotMin;
        }
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

    const int optionalMaxMinutes = 120;
    final Map<String, int> optionalMinutesByClassSubj = {}; // key: class|subj
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
        for (final className in teacherClasses) {
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
          // Enforce optional cap per class/subject
          final isOptional = (await db.getCoursesForClass(className, computedYear))
              .any((c) => c.name == subj && (c.categoryId ?? '').toLowerCase() == 'optional');
          if (isOptional) {
            final slotMin = _slotMinutes(start, end);
            final keyOS = '$className|$subj';
            final used = optionalMinutesByClassSubj[keyOS] ?? 0;
            if (used + slotMin > optionalMaxMinutes) {
              continue;
            }
            optionalMinutesByClassSubj[keyOS] = used + slotMin;
          }
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
      // Seed optional minutes per (class, subject) from existing entries
      const int optionalMaxMinutes = 120;
      final Map<String, int> optionalMinutesByClassSubj = {};
      final optionalSet = classSubjects
          .where((c) => (c.categoryId ?? '').toLowerCase() == 'optional')
          .map((c) => c.name)
          .toSet();
      for (final e in current) {
        if (optionalSet.contains(e.subject)) {
          final sm = _parseHHmm(e.startTime);
          final em = _parseHHmm(e.endTime);
          final diff = em > sm ? (em - sm) : 0;
          final keyOS = '${cls.name}|${e.subject}';
          optionalMinutesByClassSubj[keyOS] = (optionalMinutesByClassSubj[keyOS] ?? 0) + diff;
        }
      }

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
          // Enforce optional cap: subject optional for this class cannot exceed 120 minutes
          final isOptional = classSubjects.any((c) => c.name == course.name && (c.categoryId ?? '').toLowerCase() == 'optional');
          if (isOptional) {
            final keyOS = '${cls.name}|${course.name}';
            final used = optionalMinutesByClassSubj[keyOS] ?? 0;
            if (used + slotMin > optionalMaxMinutes) continue;
          }
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
            if (isOptional) {
              final keyOS = '${cls.name}|${course.name}';
              optionalMinutesByClassSubj[keyOS] = (optionalMinutesByClassSubj[keyOS] ?? 0) + slotMin;
            }
            if (placed >= sessionsPerSubject) break outer;
          }
        }
      }
    }

    return created;
  }
}
