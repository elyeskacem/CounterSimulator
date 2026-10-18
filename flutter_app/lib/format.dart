class Fmt {
  /// 11000 -> "11 000"
  static String intGrouped(double v) {
    final n = v.round();
    final digits = n.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
      out.write(digits[i]);
    }
    return (n < 0 ? '-' : '') + out.toString();
  }

  static String km1(double v) => v.toStringAsFixed(1);

  /// 1:52h for long durations, 12:05 for short ones.
  static String duration(double ms) {
    final totalSeconds = (ms / 1000).floor();
    final minutes = totalSeconds ~/ 60;
    final hours = minutes ~/ 60;
    if (hours > 0) {
      return '$hours:${(minutes % 60).toString().padLeft(2, '0')}h';
    }
    return '$minutes:${(totalSeconds % 60).toString().padLeft(2, '0')}';
  }
}
