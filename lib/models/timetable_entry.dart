class TimetableEntry {
  final int? id;
  final String subject;
  final String teacher;
  final String className;
  final String academicYear;
  final String dayOfWeek;
  final String startTime;
  final String endTime;
  final String room;

  TimetableEntry({
    this.id,
    required this.subject,
    required this.teacher,
    required this.className,
    required this.academicYear,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.room,
  });

  factory TimetableEntry.fromMap(Map<String, dynamic> map) {
    return TimetableEntry(
      id: map['id'] as int?,
      subject: map['subject'] as String,
      teacher: map['teacher'] as String,
      className: map['className'] as String,
      academicYear: map['academicYear'] as String,
      dayOfWeek: map['dayOfWeek'] as String,
      startTime: map['startTime'] as String,
      endTime: map['endTime'] as String,
      room: map['room'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject': subject,
      'teacher': teacher,
      'className': className,
      'academicYear': academicYear,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'room': room,
    };
  }
}
