// ── Auth ──────────────────────────────────────────────────────────────────────

class AuthResponse {
  final String accessToken;
  final String? userId;
  const AuthResponse({required this.accessToken, this.userId});

  factory AuthResponse.fromJson(Map<String, dynamic> j) => AuthResponse(
    accessToken: j['access_token'] as String? ?? '',
    userId:      j['user_id']      as String?,
  );
}

// ── Journal ───────────────────────────────────────────────────────────────────

class JournalResponse {
  final String entryId;
  final String detectedEmotion;
  final String patternInsight;
  final String relapseRiskLevel;
  final List<String> recommendations;
  final List<String> alternativeSuggestions;
  final String encouragementMessage;
  final String? medicationSupport;
  final String? stigmaReassurance;
  final int streak;
  final bool escalationTriggered;

  const JournalResponse({
    required this.entryId,
    required this.detectedEmotion,
    required this.patternInsight,
    required this.relapseRiskLevel,
    required this.recommendations,
    required this.alternativeSuggestions,
    required this.encouragementMessage,
    this.medicationSupport,
    this.stigmaReassurance,
    required this.streak,
    required this.escalationTriggered,
  });

  factory JournalResponse.fromJson(Map<String, dynamic> j) => JournalResponse(
    entryId:                j['entry_id']              as String? ?? '',
    detectedEmotion:        j['detected_emotion']       as String? ?? '',
    patternInsight:         j['pattern_insight']        as String? ?? '',
    relapseRiskLevel:       j['relapse_risk_level']     as String? ?? 'low',
    recommendations:        List<String>.from(j['recommendations']         ?? []),
    alternativeSuggestions: List<String>.from(j['alternative_suggestions'] ?? []),
    encouragementMessage:   j['encouragement_message'] as String?
                          ?? j['encouragement']        as String? ?? '',
    medicationSupport:      j['medication_support']    as String?,
    stigmaReassurance:      j['stigma_reassurance']    as String?,
    streak:                 j['streak']                as int? ?? 0,
    escalationTriggered:    j['escalation_triggered']  as bool? ?? false,
  );
}

// ── Insights ──────────────────────────────────────────────────────────────────

class InsightItem {
  final String id;
  final String detectedEmotion;
  final String patternInsight;
  final String relapseRiskLevel;
  final List<String> recommendations;
  final String encouragement;
  final DateTime createdAt;

  const InsightItem({
    required this.id,
    required this.detectedEmotion,
    required this.patternInsight,
    required this.relapseRiskLevel,
    required this.recommendations,
    required this.encouragement,
    required this.createdAt,
  });

  factory InsightItem.fromJson(Map<String, dynamic> j) => InsightItem(
    id:               j['id']                as String,
    detectedEmotion:  j['detected_emotion']  as String? ?? '',
    patternInsight:   j['pattern_insight']   as String? ?? '',
    relapseRiskLevel: j['relapse_risk_level'] as String? ?? 'low',
    recommendations:  List<String>.from(j['recommendations'] ?? []),
    encouragement:    j['encouragement']     as String? ?? '',
    createdAt:        DateTime.parse(j['created_at'] as String),
  );
}

// ── Progress ──────────────────────────────────────────────────────────────────

class WeeklySummary {
  final int entriesThisWeek;
  final double? averageMood;
  const WeeklySummary({required this.entriesThisWeek, this.averageMood});

  factory WeeklySummary.fromJson(Map<String, dynamic> j) => WeeklySummary(
    entriesThisWeek: j['entries_this_week'] as int? ?? 0,
    averageMood:     (j['average_mood']     as num?)?.toDouble(),
  );
}

class BadgeItem {
  final String badge;
  final String label;
  final DateTime awardedAt;
  const BadgeItem({required this.badge, required this.label, required this.awardedAt});

  factory BadgeItem.fromJson(Map<String, dynamic> j) => BadgeItem(
    badge:     j['badge']      as String,
    label:     j['label']      as String,
    awardedAt: DateTime.parse(j['awarded_at'] as String),
  );
}

class ProgressStats {
  final int currentStreak;
  final int longestStreak;
  final int totalEntries;
  final String? sobrietyStartDate;
  final WeeklySummary weeklySummary;
  final String latestRiskLevel;
  final String? latestEmotion;
  final List<BadgeItem> badges;

  const ProgressStats({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalEntries,
    this.sobrietyStartDate,
    required this.weeklySummary,
    required this.latestRiskLevel,
    this.latestEmotion,
    required this.badges,
  });

  factory ProgressStats.fromJson(Map<String, dynamic> j) => ProgressStats(
    currentStreak:     j['current_streak']  as int? ?? 0,
    longestStreak:     j['longest_streak']  as int? ?? 0,
    totalEntries:      j['total_entries']   as int? ?? 0,
    sobrietyStartDate: j['sobriety_start_date'] as String?,
    weeklySummary:     WeeklySummary.fromJson(
        (j['weekly_summary'] as Map<String, dynamic>?) ?? {}),
    latestRiskLevel:   j['latest_risk_level'] as String? ?? 'unknown',
    latestEmotion:     j['latest_emotion']    as String?,
    badges: (j['badges'] as List<dynamic>?)
        ?.map((b) => BadgeItem.fromJson(b as Map<String, dynamic>)).toList() ?? [],
  );
}

// ── Chart data (NEW — replaces hardcoded offsets in progress_page.dart) ───────

class ChartDataPoint {
  final DateTime date;
  final int entryCount;
  final double? avgMood;

  const ChartDataPoint({
    required this.date,
    required this.entryCount,
    this.avgMood,
  });

  factory ChartDataPoint.fromJson(Map<String, dynamic> j) => ChartDataPoint(
    date:       DateTime.parse(j['entry_date'] as String),
    entryCount: j['entry_count'] as int? ?? 0,
    avgMood:    (j['avg_mood'] as num?)?.toDouble(),
  );
}

// ── Daily message ─────────────────────────────────────────────────────────────

class DailyMessage {
  final String message;
  final int streak;
  final String moodTrend;
  const DailyMessage({required this.message, required this.streak, required this.moodTrend});

  factory DailyMessage.fromJson(Map<String, dynamic> j) => DailyMessage(
    message:   j['message']    as String,
    streak:    j['streak']     as int? ?? 0,
    moodTrend: j['mood_trend'] as String? ?? 'stable',
  );
}

// ── Therapist (NEW) ───────────────────────────────────────────────────────────

class TherapistPatient {
  final String patientId;
  final String displayName;
  final String recoveryType;
  final int currentStreak;
  final int totalEntries;
  final String? lastEntryDate;
  final String latestRiskLevel;
  final bool highRiskFlag;
  final bool journalAccess;

  const TherapistPatient({
    required this.patientId,
    required this.displayName,
    required this.recoveryType,
    required this.currentStreak,
    required this.totalEntries,
    this.lastEntryDate,
    required this.latestRiskLevel,
    required this.highRiskFlag,
    required this.journalAccess,
  });

  factory TherapistPatient.fromJson(Map<String, dynamic> j) => TherapistPatient(
    patientId:        j['patient_id']       as String,
    displayName:      j['display_name']     as String? ?? 'Unknown',
    recoveryType:     j['recovery_type']    as String? ?? 'both',
    currentStreak:    j['current_streak']   as int? ?? 0,
    totalEntries:     j['total_entries']    as int? ?? 0,
    lastEntryDate:    j['last_entry_date']  as String?,
    latestRiskLevel:  j['latest_risk_level'] as String? ?? 'unknown',
    highRiskFlag:     j['high_risk_flag']   as bool? ?? false,
    journalAccess:    j['journal_access']   as bool? ?? false,
  );
}

class PatientInsight {
  final String id;
  final String detectedEmotion;
  final String patternInsight;
  final String relapseRiskLevel;
  final List<String> recommendations;
  final String encouragement;
  final DateTime createdAt;

  const PatientInsight({
    required this.id,
    required this.detectedEmotion,
    required this.patternInsight,
    required this.relapseRiskLevel,
    required this.recommendations,
    required this.encouragement,
    required this.createdAt,
  });

  factory PatientInsight.fromJson(Map<String, dynamic> j) => PatientInsight(
    id:               j['id']                as String,
    detectedEmotion:  j['detected_emotion']  as String? ?? '',
    patternInsight:   j['pattern_insight']   as String? ?? '',
    relapseRiskLevel: j['relapse_risk_level'] as String? ?? 'low',
    recommendations:  List<String>.from(j['recommendations'] ?? []),
    encouragement:    j['encouragement']     as String? ?? '',
    createdAt:        DateTime.parse(j['created_at'] as String),
  );
}