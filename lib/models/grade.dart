class Grade {
  final int? id;
  final String studentId;
  final String className;
  final String academicYear;
  final String subjectId;
  final String subject;
  final String term;
  final double value;
  final String? label;
  final double maxValue;
  final double coefficient;
  final String type;

  Grade({
    this.id,
    required this.studentId,
    required this.className,
    required this.academicYear,
    required this.subjectId,
    required this.subject,
    required this.term,
    required this.value,
    this.label,
    this.maxValue = 20,
    this.coefficient = 1,
    this.type = 'Devoir',
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'studentId': studentId,
    'className': className,
    'academicYear': academicYear,
    'subjectId': subjectId,
    'subject': subject,
    'term': term,
    'value': value,
    'label': label,
    'maxValue': maxValue,
    'coefficient': coefficient,
    'type': type,
  };

  factory Grade.fromMap(Map<String, dynamic> map) => Grade(
    id: map['id'],
    studentId: map['studentId'],
    className: map['className'],
    academicYear: map['academicYear'],
    subjectId: map['subjectId'] ?? '',
    subject: map['subject'] ?? '',
    term: map['term'],
    value: map['value'] is int
        ? (map['value'] as int).toDouble()
        : map['value'],
    label: map['label'],
    maxValue: map['maxValue'] != null
        ? (map['maxValue'] is int
              ? (map['maxValue'] as int).toDouble()
              : map['maxValue'])
        : 20.0,
    coefficient: map['coefficient'] != null
        ? (map['coefficient'] is int
              ? (map['coefficient'] as int).toDouble()
              : map['coefficient'])
        : 1.0,
    type: map['type'] ?? 'Devoir',
  );

  factory Grade.empty() => Grade(
    studentId: '',
    className: '',
    academicYear: '',
    subjectId: '',
    subject: '',
    term: '',
    value: 0,
  );
}
