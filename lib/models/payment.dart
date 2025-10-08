class Payment {
  final int? id;
  final String studentId;
  final String className;
  final String classAcademicYear;
  final double amount;
  final String date;
  final String? comment;
  final bool isCancelled;
  final String? cancelledAt;

  Payment({
    this.id,
    required this.studentId,
    required this.className,
    required this.classAcademicYear,
    required this.amount,
    required this.date,
    this.comment,
    this.isCancelled = false,
    this.cancelledAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'className': className,
      'classAcademicYear': classAcademicYear,
      'amount': amount,
      'date': date,
      'comment': comment,
      'isCancelled': isCancelled ? 1 : 0,
      'cancelledAt': cancelledAt,
    };
  }

  factory Payment.fromMap(Map<String, dynamic> map) {
    final dynamic yearValue = map['classAcademicYear'] ?? map['academicYear'];
    return Payment(
      id: map['id'],
      studentId: map['studentId'],
      className: map['className'],
      classAcademicYear: yearValue is String
          ? yearValue
          : yearValue?.toString() ?? '',
      amount: map['amount'] is int
          ? (map['amount'] as int).toDouble()
          : map['amount'],
      date: map['date'],
      comment: map['comment'],
      isCancelled: map['isCancelled'] == 1,
      cancelledAt: map['cancelledAt'],
    );
  }

  factory Payment.fromJson(Map<String, dynamic> json) {
    final dynamic yearValue = json['classAcademicYear'] ?? json['academicYear'];
    return Payment(
      id: json['id'],
      studentId: json['studentId'],
      className: json['className'],
      classAcademicYear: yearValue is String
          ? yearValue
          : yearValue?.toString() ?? '',
      amount: json['amount'] is int
          ? (json['amount'] as int).toDouble()
          : json['amount'],
      date: json['date'],
      comment: json['comment'],
      isCancelled: json['isCancelled'] == true || json['isCancelled'] == 1,
      cancelledAt: json['cancelledAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'className': className,
      'classAcademicYear': classAcademicYear,
      'amount': amount,
      'date': date,
      'comment': comment,
      'isCancelled': isCancelled,
      'cancelledAt': cancelledAt,
    };
  }
}
