/// Client-side checks mirroring backend `TripCreate` rules, so users get
/// feedback before a request is sent. The backend stays authoritative. [S2-04]
class TripFormValidators {
  static const int titleMaxLength = 200;
  static const int maxTags = 30;

  /// Up to 10 whole digits and 2 decimals (`Numeric(12, 2)`), commas allowed.
  static final RegExp _money = RegExp(r'^\d{1,10}(\.\d{1,2})?$');

  static String? title(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Give your trip a name.';
    if (text.length > titleMaxLength) {
      return 'Keep the name under $titleMaxLength characters.';
    }
    return null;
  }

  /// Parses user money input such as "1,500" or "1500.5"; null if invalid.
  static double? parseMoney(String? value) {
    final text = (value ?? '').replaceAll(',', '').trim();
    if (!_money.hasMatch(text)) return null;
    return double.parse(text);
  }

  static String? budget(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Enter an amount.';
    if (parseMoney(value) == null) {
      return 'Use a positive amount with up to 2 decimals.';
    }
    return null;
  }

  static String? budgetMax(String? value, String? minValue) {
    final error = budget(value);
    if (error != null) return error;
    final min = parseMoney(minValue);
    if (min != null && parseMoney(value)! < min) {
      return 'Max budget must be at least the min.';
    }
    return null;
  }

  static String? dates(DateTime? start, DateTime? end) {
    if (start == null || end == null) return 'Pick your travel dates.';
    if (end.isBefore(start)) return 'End date must be on or after the start.';
    return null;
  }
}
