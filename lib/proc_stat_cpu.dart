/// Parses process CPU time from Linux/Android /proc/[pid]/stat.
///
/// The command name (field 2) is parenthesized and may itself contain spaces
/// or parentheses. Locate its final closing delimiter, then parse fields 14
/// (utime) and 15 (stime) relative to field 3. Whitespace is normalized so
/// repeated spaces cannot shift the CPU counters.
int? parseProcStatCpuTicks(String statLine) {
  final commandEnd = statLine.lastIndexOf(')');
  if (commandEnd < 0 || commandEnd + 1 >= statLine.length) return null;
  final fields = statLine.substring(commandEnd + 1).trim().split(RegExp(r'\s+'));
  // fields[0] is field 3 (state); utime/stime are fields 14/15.
  if (fields.length <= 12) return null;
  final userTicks = int.tryParse(fields[11]);
  final systemTicks = int.tryParse(fields[12]);
  if (userTicks == null || systemTicks == null || userTicks < 0 || systemTicks < 0) {
    return null;
  }
  return userTicks + systemTicks;
}
