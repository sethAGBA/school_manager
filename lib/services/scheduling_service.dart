import 'package:school_manager/models/class.dart';
import 'package:school_manager/models/course.dart';
import 'package:school_manager/models/staff.dart';
import 'package:school_manager/models/timetable_entry.dart';
import 'package:school_manager/services/database_service.dart';
import 'package:school_manager/utils/academic_year.dart';

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
    for (final course in subjects) {
      final subj = course.name;
      final teacher = findTeacherFor(subj)?.name ?? '';
      int placed = 0;
      outer:
      for (final day in daysOfWeek) {
        for (final slot in timeSlots) {
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

    // Iterate classes the teacher is assigned to
    final classes = await db.getClasses();
    for (final className in teacher.classes) {
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

      for (final course in teachable) {
        int placed = 0;
        outer:
        for (final day in daysOfWeek) {
          for (final slot in timeSlots) {
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
