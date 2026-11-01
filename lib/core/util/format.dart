import 'package:intl/intl.dart';

abstract final class SdFormat {
  static final _num = NumberFormat.decimalPattern();
  static final _compact = NumberFormat.compact();
  static final _date = DateFormat('yyyy-MM-dd');
  static final _dateTime = DateFormat('yyyy-MM-dd · HH:mm');

  static String number(int n) => _num.format(n);
  static String compact(int n) => n < 10000 ? _num.format(n) : _compact.format(n);
  static String date(DateTime d) => _date.format(d.toLocal());
  static String dateTime(DateTime d) => _dateTime.format(d.toLocal());

  static String ago(DateTime t, {DateTime? now}) {
    final d = (now ?? DateTime.now()).difference(t);
    if (d.inSeconds < 60) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return date(t);
  }
}
