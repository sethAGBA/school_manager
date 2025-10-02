import 'package:intl/intl.dart';

DateTime? parseDdMmYyyy(String? dateString) {
  if (dateString == null || dateString.isEmpty) {
    return null;
  }
  try {
    return DateFormat('dd/MM/yyyy').parseStrict(dateString);
  } catch (e) {
    print('Error parsing date $dateString: $e');
    return null;
  }
}

String formatDdMmYyyy(DateTime? date) {
  if (date == null) {
    return '';
  }
  return DateFormat('dd/MM/yyyy').format(date);
}
