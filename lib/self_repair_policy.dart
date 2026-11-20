/// Redact configuration links, identifiers and credential-like values before
/// runtime diagnostics are sent to any optional AI/provider or support flow.
String redactSensitiveDiagnostic(String input) {
  var value = input;
  value = value.replaceAll(
    RegExp(r'(?:vmess|vless|trojan|ss|socks5?|hysteria2|tuic|wireguard)://\S+', caseSensitive: false),
    '[CONFIG_REDACTED]',
  );
  // Support plain key=value logs and JSON/YAML-style quoted keys/values.
  // Retain the key prefix so the sanitized diagnostic remains structurally useful.
  value = value.replaceAllMapped(
    RegExp(
      r'''(["']?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|session[_-]?token|client[_-]?secret|private[_-]?key|token|secret|password|uuid|authorization|cookie)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|Bearer\s+[A-Za-z0-9._~+/=-]+|[^\s,;}\]]+)''',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}"[REDACTED]"',
  );
  // Authorization headers and common GitHub credential formats can appear
  // without a nearby key=value label in exception messages.
  value = value.replaceAll(
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    'Bearer [REDACTED]',
  );
  value = value.replaceAll(
    RegExp(r'\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b'),
    '[TOKEN_REDACTED]',
  );
  value = value.replaceAllMapped(
    RegExp(r'([?&](?:key|token|auth|password|uuid)=)[^&#\s]+', caseSensitive: false),
    (match) => '${match.group(1)}[REDACTED]',
  );
  value = value.replaceAll(
    RegExp(r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b', caseSensitive: false),
    '[ID_REDACTED]',
  );
  return value.length > 1200 ? value.substring(0, 1200) : value;
}

enum RepairSeverity { info, warning, critical }
enum RepairAction {
  none,
  refreshNetworkEvidence,
  rebuildConfig,
  replaceDns,
  restartCurrentEngine,
  restoreLastKnownGood,
  requestSourcePatch,
}
enum PatchGateStatus { accepted, rejected }

class RepairObservation {
  const RepairObservation({
    required this.code,
    required this.severity,
    required this.repeatedCount,
    this.tunnelDataPlaneHealthy = false,
    this.lastActionFailed = false,
  });

  final String code;
  final RepairSeverity severity;
  final int repeatedCount;
  final bool tunnelDataPlaneHealthy;
  final bool lastActionFailed;
}

class RepairDecision {
  const RepairDecision(this.action, this.reason);
  final RepairAction action;
  final String reason;
}

RepairDecision decideRepair(RepairObservation observation) {
  if (observation.tunnelDataPlaneHealthy &&
      observation.severity != RepairSeverity.critical) {
    return const RepairDecision(
      RepairAction.none,
      'مسیر داده سالم است؛ از تعمیر و تعویض بی‌دلیل جلوگیری شد',
    );
  }
  if (observation.lastActionFailed && observation.repeatedCount >= 3) {
    return const RepairDecision(
      RepairAction.restoreLastKnownGood,
      'اقدام قبلی چند بار شکست خورده؛ بازگشت به وضعیت سالم',
    );
  }
  switch (observation.code) {
    case 'dns_failure':
      return const RepairDecision(RepairAction.replaceDns, 'خطای DNS');
    case 'config_invalid':
      return const RepairDecision(RepairAction.rebuildConfig, 'ساخت مجدد کانفیگ');
    case 'core_stopped':
      return const RepairDecision(RepairAction.restartCurrentEngine, 'موتور متوقف شده');
    case 'engine_unhealthy':
      return const RepairDecision(RepairAction.restartCurrentEngine, 'موتور فعلی ناسالم است؛ راه‌اندازی کنترل‌شده همان موتور');
    case 'source_defect':
    case 'native_plugin_defect':
      return const RepairDecision(
        RepairAction.requestSourcePatch,
        'نیازمند اصلاح سورس در محیط ساخت ایزوله',
      );
    case 'network_changed':
      return const RepairDecision(
        RepairAction.refreshNetworkEvidence,
        'شواهد شبکه پس از تغییر شبکه منقضی شده‌اند',
      );
    default:
      return const RepairDecision(RepairAction.none, 'شواهد کافی برای اقدام وجود ندارد');
  }
}

class PatchGateInput {
  const PatchGateInput({
    required this.signedByTrustedKey,
    required this.testsPassed,
    required this.staticAnalysisPassed,
    required this.rollbackSnapshotExists,
    required this.changedFiles,
    required this.diffLines,
    this.containsSecret = false,
  });

  final bool signedByTrustedKey;
  final bool testsPassed;
  final bool staticAnalysisPassed;
  final bool rollbackSnapshotExists;
  final List<String> changedFiles;
  final int diffLines;
  final bool containsSecret;
}

class PatchGateResult {
  const PatchGateResult(this.status, this.reasons);
  final PatchGateStatus status;
  final List<String> reasons;
}

const Set<String> protectedRuntimePaths = <String>{
  'android/app/src/main/AndroidManifest.xml',
  'android/app/build.gradle',
  'android/app/build.gradle.kts',
  'android/build.gradle',
  'android/build.gradle.kts',
  'android/settings.gradle',
  'android/settings.gradle.kts',
  'android/gradle.properties',
  'android/gradle/wrapper/gradle-wrapper.properties',
  'pubspec.yaml',
  'pubspec.lock',
};

const List<String> allowedSourcePatchRoots = <String>[
  'lib/',
  'test/',
  'tools/',
];

bool isAllowedSourcePatchPath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path.split('/').any((part) => part.isEmpty || part == '.' || part == '..')) {
    return false;
  }
  return allowedSourcePatchRoots.any((root) => path.startsWith(root));
}

PatchGateResult validateSourcePatch(PatchGateInput input) {
  final reasons = <String>[];
  if (!input.signedByTrustedKey) reasons.add('امضای معتبر وجود ندارد');
  if (!input.testsPassed) reasons.add('تست‌ها موفق نشده‌اند');
  if (!input.staticAnalysisPassed) reasons.add('تحلیل ایستا موفق نشده است');
  if (!input.rollbackSnapshotExists) reasons.add('نسخه بازگشت موجود نیست');
  if (input.containsSecret) reasons.add('احتمال افشای اطلاعات محرمانه');
  if (input.diffLines <= 0 || input.diffLines > 1200) {
    reasons.add('اندازه Patch خارج از محدوده مجاز است');
  }
  for (final path in input.changedFiles) {
    if (!isAllowedSourcePatchPath(path)) {
      reasons.add('مسیر خارج از محدوده مجاز است: $path');
    }
    if (protectedRuntimePaths.contains(path) ||
        path.startsWith('android/app/src/main/java/') ||
        path.startsWith('android/app/src/main/kotlin/')) {
      reasons.add('تغییر فایل محافظت‌شده نیازمند بازبینی انسانی است: $path');
    }
  }
  return PatchGateResult(
    reasons.isEmpty ? PatchGateStatus.accepted : PatchGateStatus.rejected,
    List<String>.unmodifiable(reasons),
  );
}
