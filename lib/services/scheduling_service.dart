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
    int blockDefaultSlots = 2,
    double threeHourThreshold = 1.5,
    int optionalMaxMinutes = 120,
    bool limitTwoHourBlocksPerWeek = true,
    Set<String> excludedFromWeeklyTwoHourCap = const <String>{},
    String? morningStart,
    String? morningEnd,
    String? afternoonStart,
    String? afternoonEnd,
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
    // optionalMaxMinutes limite par semaine pour matières optionnelles
    // Répartition proportionnelle aux coefficients: le plus gros coeff a plus d'heures
    final coeffs = await db.getClassSubjectCoefficients(targetClass.name, computedYear);
    final coreSubjects = subjects.where((c) => !isOptional(c) && !isEPS(c.name)).toList();
    double sumW = 0;
    for (final c in coreSubjects) {
      sumW += (coeffs[c.name] ?? 1.0);
    }
    // Baseline: chaque matière non optionnelle a au moins 1 séance
    final int baseTotal = (sessionsPerSubject * coreSubjects.length).clamp(0, 10000);
    // Distribution de base (1 par matière)
    final Map<String, int> alloc = { for (final c in coreSubjects) c.name: 1 };
    int remaining = (baseTotal - coreSubjects.length).clamp(0, 10000);
    if (remaining > 0 && sumW > 0) {
      // Parts proportionnelles + plus grands restes
      final Map<String, double> raw = {
        for (final c in coreSubjects)
          c.name: ((coeffs[c.name] ?? 1.0) / sumW) * remaining
      };
      int distributed = 0;
      // Appliquer floor
      for (final c in coreSubjects) {
        final f = raw[c.name]!.floor();
        if (f > 0) {
          alloc[c.name] = (alloc[c.name] ?? 0) + f;
          distributed += f;
        }
      }
      // Distribuer les restes aux plus gros restes d'abord
      final remainders = coreSubjects
          .map((c) => MapEntry(c.name, raw[c.name]! - raw[c.name]!.floor()))
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      int left = remaining - distributed;
      int idx = 0;
      while (left > 0 && idx < remainders.length) {
        alloc[remainders[idx].key] = (alloc[remainders[idx].key] ?? 0) + 1;
        left--;
        idx++;
      }
    }
    // Remplir targetSessions avec allocations calculées
    for (final c in subjectsOrder) {
      if (isOptional(c)) {
        targetSessions[c.name] = 2; // cap 2h (effectif contraint par optionalMinutes)
        optionalMinutes[c.name] = 0;
      } else if (isEPS(c.name)) {
        targetSessions[c.name] = 2; // deux séances courtes
      } else {
        targetSessions[c.name] = (alloc[c.name] ?? 1).clamp(1, 1000);
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
    // Compteur des blocs de 2h par matière pour la semaine (cap global)
    final Map<String, int> twoHourBlocksCount = {};
    // Greedy placement: iterate subjects, place target sessions scanning shuffled days/timeSlots.
    for (final course in subjectsOrder) {
      final subj = course.name;
      final teacher = findTeacherFor(subj)?.name ?? '';
      final int need = (targetSessions[subj] ?? sessionsPerSubject).clamp(0, 1000);
      int placedHours = 0;
      outer:
      for (final day in daysOrder) {
        // EPS: ensure different days if possible
        if (isEPS(subj) && epsDaysUsed.contains(day) && epsDaysUsed.length < daysOrder.length) {
          continue;
        }
        // Blocs réalistes: EPS=1h, sinon 2h consécutives/jour si plusieurs heures à placer
        final int remainingHours = (need - placedHours).clamp(0, 1000);
        int desiredBlock = 1;
        if (!isEPS(subj)) {
          desiredBlock = remainingHours >= 2 ? 2 : 1;
        }

      // Traverse slots sorted by start time to ensure true contiguity
        final List<String> sortedSlots = List<String>.from(timeSlots);
        sortedSlots.sort((a, b) {
          int sa = _parseHHmm(a.split(' - ').first);
          int sb = _parseHHmm(b.split(' - ').first);
          return sa.compareTo(sb);
        });
        for (int si = 0; si < sortedSlots.length; si++) {
          final slot = sortedSlots[si];
          if (breakSlots.contains(slot)) continue;
          final parts = slot.split(' - ');
          final start = parts.first;
          final end = parts.length > 1 ? parts[1] : parts.first;
          final slotMin = _slotMinutes(start, end);
          // Determine actual block for optional cap
          int blockSlots = desiredBlock;
          // Cap hebdo: au plus un bloc 2h par matière
          if (limitTwoHourBlocksPerWeek && blockSlots == 2 && !excludedFromWeeklyTwoHourCap.contains(subj)) {
            final used = twoHourBlocksCount[subj] ?? 0;
            if (used >= 1) blockSlots = 1;
          }
          if (isOptional(course)) {
            final remaining = optionalMaxMinutes - (optionalMinutes[subj] ?? 0);
            blockSlots = remaining >= (2 * slotMin) ? min(2, desiredBlock) : 1;
          }
          // Ne pas dépasser les heures restantes cette semaine ni le cap par jour
          blockSlots = min(blockSlots, remainingHours);
          // Pre-check availability for contiguous block
          int totalBlockMin = 0;
          bool canPlace = true;
          // Cap par jour pour la matière: max 2 créneaux si matière chargée, sinon 1
          final int currentSubjCount = (classSubjectDaily[day]?[subj] ?? 0);
          final int perDaySubjectCap = !isEPS(subj) && remainingHours >= 2 ? 2 : 1;
          if (currentSubjCount >= perDaySubjectCap) {
            canPlace = false;
          }
          // Clamp block to what's allowed remaining today
          blockSlots = min(blockSlots, perDaySubjectCap - currentSubjCount);
          if (blockSlots <= 0) { canPlace = false; }
          int baseSeg = -1; // 0=morning, 1=afternoon, -1=unknown
          for (int k = 0; k < blockSlots; k++) {
            final idx = si + k;
            if (idx >= sortedSlots.length) { canPlace = false; break; }
            final s = sortedSlots[idx];
            if (breakSlots.contains(s)) { canPlace = false; break; }
            final p = s.split(' - ');
            final st = p.first;
            final en = p.length > 1 ? p[1] : p.first;
            final m = _slotMinutes(st, en);
          // Restriction: rester dans le même segment (matin/après-midi) si défini
          if (morningStart != null && morningEnd != null && afternoonStart != null && afternoonEnd != null) {
            final t = _parseHHmm(st);
            final mStart = _parseHHmm(morningStart);
            final mEnd = _parseHHmm(morningEnd);
            final aStart = _parseHHmm(afternoonStart);
            final aEnd = _parseHHmm(afternoonEnd);
            int seg = -1;
            if (t >= mStart && t < mEnd) seg = 0; else if (t >= aStart && t < aEnd) seg = 1;
            if (baseSeg == -1) baseSeg = seg;
            if (seg != -1 && baseSeg != -1 && seg != baseSeg) { canPlace = false; break; }
          }
          totalBlockMin += m;
          if (hasClassConflict(day, st)) { canPlace = false; break; }
          if (teacher.isNotEmpty && ((teacherBusyAll[teacher]?.contains('$day|$st') ?? false) || hasTeacherConflict(teacher, day, st) || (teacherUnavail[teacher]?.contains('$day|$st') == true))) { canPlace = false; break; }
          // Per-day limits (anticipate full block)
          if (classMaxPerDay != null && classMaxPerDay > 0) {
            final cntClass = (classDailyCount[day] ?? 0);
            if (cntClass + (k + 1) > classMaxPerDay) { canPlace = false; break; }
          }
          if (subjectMaxPerDay != null && subjectMaxPerDay > 0) {
            final bySubj = classSubjectDaily[day] ?? <String,int>{};
            final cntSubj = (bySubj[subj] ?? 0);
            if (cntSubj + (k + 1) > subjectMaxPerDay) { canPlace = false; break; }
          }
          if (teacherMaxPerDay != null && teacherMaxPerDay > 0 && teacher.isNotEmpty) {
            final tDay = teacherDaily[teacher] ?? <String,int>{};
            final cntT = tDay[day] ?? 0;
            if (cntT + (k + 1) > teacherMaxPerDay) { canPlace = false; break; }
          }
          // Respecter le clamp appliqué plus haut
          if (k + 1 > blockSlots) { canPlace = false; break; }
        }
          // Optional cap
          if (isOptional(course) && (optionalMinutes[subj] ?? 0) + totalBlockMin > optionalMaxMinutes) {
            canPlace = false;
          }
          // Teacher weekly hours cap
          if (canPlace && enforceTeacherWeeklyHours && teacher.isNotEmpty) {
            final max = (teachersList.firstWhere((t) => t.name == teacher, orElse: () => Staff.empty()).weeklyHours) ?? 0;
            final maxMin = max > 0 ? max * 60 : 0;
            if (maxMin > 0 && (teacherLoad[teacher] ?? 0) + totalBlockMin > maxMin) canPlace = false;
          }
          if (!canPlace) continue;

          // Place the contiguous block
          for (int k = 0; k < blockSlots; k++) {
            final idx = si + k;
            final s = sortedSlots[idx];
            final p = s.split(' - ');
            final st = p.first;
            final en = p.length > 1 ? p[1] : p.first;
            final m = _slotMinutes(st, en);
            final entry = TimetableEntry(
              subject: subj,
              teacher: teacher,
              className: targetClass.name,
              academicYear: computedYear,
              dayOfWeek: day,
              startTime: st,
              endTime: en,
              room: '',
            );
            await db.insertTimetableEntry(entry);
            current = await db.getTimetableEntries(
              className: targetClass.name,
              academicYear: computedYear,
            );
            if (teacher.isNotEmpty) {
              teacherLoad[teacher] = (teacherLoad[teacher] ?? 0) + m;
              teacherDaily[teacher]![day] = (teacherDaily[teacher]![day] ?? 0) + 1;
              teacherBusyAll.putIfAbsent(teacher, () => <String>{}).add('$day|$st');
            }
            classDailyCount[day] = (classDailyCount[day] ?? 0) + 1;
            final byS = classSubjectDaily[day] ?? <String,int>{};
            byS[subj] = (byS[subj] ?? 0) + 1;
            classSubjectDaily[day] = byS;
            created++;
            if (isOptional(course)) {
              optionalMinutes[subj] = (optionalMinutes[subj] ?? 0) + m;
            }
          }
          placedHours += blockSlots;
          if (blockSlots == 2 && limitTwoHourBlocksPerWeek) {
            twoHourBlocksCount[subj] = (twoHourBlocksCount[subj] ?? 0) + 1;
          }
          if (isEPS(subj)) epsDaysUsed.add(day);
          if (placedHours >= need) break outer;
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
    int optionalMaxMinutes = 120,
    String? morningStart,
    String? morningEnd,
    String? afternoonStart,
    String? afternoonEnd,
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
    // Limite minutes/semaine pour matières optionnelles
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
      for (int si = 0; si < slotsOrder.length; si++) {
        final slot = slotsOrder[si];
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

        // Tenter de créer un bloc de 2h consécutif pour les classes (hors pauses/EPS), dans le même segment
        final isEPSsubj = subj.toLowerCase().contains('eps') || subj.toLowerCase().contains('sport') || subj.toLowerCase().contains('éducation physique') || subj.toLowerCase().contains('education physique');
        if (!isEPSsubj) {
          final int nextIdx = si + 1;
          if (nextIdx < slotsOrder.length) {
            final nextSlot = slotsOrder[nextIdx];
            if (!breakSlots.contains(nextSlot)) {
              final nStart = nextSlot.split(' - ').first;
              final nKey = '$day|$nStart';
              if (!classBusy.contains(nKey)) {
                // Respecter disponibilité enseignant si défini
                bool teacherOk = true;
                if (teacherName.isNotEmpty) {
                  final busy = teacherBusy[teacherName] ?? const <String>{};
                  final un = teacherUnavail[teacherName] ?? const <String>{};
                  if (busy.contains(nKey) || un.contains(nKey)) teacherOk = false;
                }
                // Vérifier segment (matin/après-midi) si défini
                bool sameSegment = true;
                if (morningStart != null && morningEnd != null && afternoonStart != null && afternoonEnd != null) {
                  int segOf(String hhmm) {
                    final t = _parseHHmm(hhmm);
                    final mStart = _parseHHmm(morningStart);
                    final mEnd = _parseHHmm(morningEnd);
                    final aStart = _parseHHmm(afternoonStart);
                    final aEnd = _parseHHmm(afternoonEnd);
                    if (t >= mStart && t < mEnd) return 0;
                    if (t >= aStart && t < aEnd) return 1;
                    return -1;
                  }
                  final seg0 = segOf(start);
                  final seg1 = segOf(nStart);
                  if (seg0 != -1 && seg1 != -1 && seg0 != seg1) sameSegment = false;
                }
                if (teacherOk && sameSegment) {
                  final nParts = nextSlot.split(' - ');
                  final nEnd = nParts.length > 1 ? nParts[1] : nParts.first;
                  final entry2 = TimetableEntry(
                    subject: subj,
                    teacher: teacherName,
                    className: targetClass.name,
                    academicYear: computedYear,
                    dayOfWeek: day,
                    startTime: nParts.first,
                    endTime: nEnd,
                    room: '',
                  );
                  await db.insertTimetableEntry(entry2);
                  classBusy.add(nKey);
                  if (teacherName.isNotEmpty) {
                    teacherBusy.putIfAbsent(teacherName, () => <String>{}).add(nKey);
                  }
                  created++;
                  if (optionalMinutes.containsKey(subj)) {
                    final nMin = _slotMinutes(nParts.first, nEnd);
                    optionalMinutes[subj] = (optionalMinutes[subj] ?? 0) + nMin;
                  }
                  // Sauter le slot suivant car consommé pour le bloc
                  si = nextIdx;
                }
              }
            }
          }
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
    int optionalMaxMinutes = 120,
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

    // Limite minutes/semaine pour matières optionnelles
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
    int optionalMaxMinutes = 120,
    bool limitTwoHourBlocksPerWeek = true,
    Set<String> excludedFromWeeklyTwoHourCap = const <String>{},
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
