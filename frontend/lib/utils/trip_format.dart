/// Display formatting shared by trip screens and form fields. [S2-04]
library;

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Nov 7, 2026"
String formatShortDate(DateTime d) =>
    '${_months[d.month - 1]} ${d.day}, ${d.year}';

/// "Nov 7 – 8, 2026", "Nov 30 – Dec 2, 2026" or "Dec 30, 2026 – Jan 2, 2027".
String formatDateRange(DateTime start, DateTime end) {
  if (start.year != end.year) {
    return '${formatShortDate(start)} – ${formatShortDate(end)}';
  }
  final startText = '${_months[start.month - 1]} ${start.day}';
  final endText = start.month == end.month
      ? '${end.day}'
      : '${_months[end.month - 1]} ${end.day}';
  return start == end
      ? formatShortDate(start)
      : '$startText – $endText, ${end.year}';
}

/// Inclusive day count: a same-day trip is 1 day.
int tripDayCount(DateTime start, DateTime end) =>
    end.difference(start).inDays + 1;

String formatDayCount(int days) => days == 1 ? '1 day' : '$days days';

/// "₱1,500" or "₱1,500.50".
String formatPeso(double value) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return parts[1] == '00' ? '₱$whole' : '₱$whole.${parts[1]}';
}

String formatBudgetRange(double min, double max) =>
    min == max ? formatPeso(min) : '${formatPeso(min)} – ${formatPeso(max)}';
