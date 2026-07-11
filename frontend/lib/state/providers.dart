import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenity/core/errors/app_exceptions.dart';
import 'package:serenity/models/app_models.dart';
import 'package:serenity/services/api_client.dart';
import 'package:serenity/services/secure_storage_service.dart';
import 'package:serenity/services/streaming_service.dart';

// ── Services ──────────────────────────────────────────────────────────────────

final storageProvider   = Provider<SecureStorageService>((_) => SecureStorageService());
final apiProvider       = Provider<ApiClient>((ref) => ApiClient(ref.read(storageProvider)));
final streamingProvider = Provider<StreamingService>(
    (ref) => StreamingService(ref.read(storageProvider)));

// ── Auth ──────────────────────────────────────────────────────────────────────

class AuthState {
  final bool isAuthenticated;
  final bool isLoading;
  final bool isInitialized;
  final String? error;
  final String? userId;

  const AuthState({
    this.isAuthenticated = false,
    this.isLoading       = false,
    this.isInitialized   = false,
    this.error,
    this.userId,
  });

  AuthState copyWith({
    bool? isAuthenticated, bool? isLoading, bool? isInitialized,
    String? error, String? userId,
  }) => AuthState(
    isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    isLoading:       isLoading       ?? this.isLoading,
    isInitialized:   isInitialized   ?? this.isInitialized,
    error:  error,
    userId: userId ?? this.userId,
  );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._api, this._storage) : super(const AuthState()) { _restore(); }

  final ApiClient _api;
  final SecureStorageService _storage;

  Future<void> _restore() async {
    try {
      await Future.any([_read(), Future.delayed(const Duration(seconds: 3))]);
    } catch (_) {
    } finally {
      if (mounted && !state.isInitialized) {
        state = const AuthState(isInitialized: true);
      }
    }
  }

  Future<void> _read() async {
    try {
      final token  = await _storage.getToken();
      final userId = await _storage.getUserId();
      if (token != null && token.isNotEmpty) {
        state = AuthState(isAuthenticated: true, isInitialized: true, userId: userId);
      } else {
        state = const AuthState(isInitialized: true);
      }
    } catch (_) {
      state = const AuthState(isInitialized: true);
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res    = await _api.post('/auth/login',
          data: {'email': email, 'password': password});
      final data   = res.data as Map<String, dynamic>;
      final token  = data['access_token'] as String? ?? '';
      final userId = data['user_id']      as String? ?? '';
      if (token.isEmpty) {
        state = state.copyWith(isLoading: false, error: 'Login failed.');
        return false;
      }
      await _storage.saveToken(token);
      await _storage.saveUserId(userId);
      state = AuthState(isAuthenticated: true, isInitialized: true, userId: userId);
      return true;
    } on AppException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Unexpected error.');
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String displayName,
    String? emergencyContactEmail,
    String? therapistEmail,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await _api.post('/auth/register', data: {
        'email':        email,
        'password':     password,
        'display_name': displayName,
        if (therapistEmail != null && therapistEmail.isNotEmpty)
          'therapist_email': therapistEmail,
        if (emergencyContactEmail != null && emergencyContactEmail.isNotEmpty)
          'emergency_contact_email': emergencyContactEmail,
      });
      final auth = AuthResponse.fromJson(res.data as Map<String, dynamic>);
      await _storage.saveToken(auth.accessToken);
      if (auth.userId != null) await _storage.saveUserId(auth.userId!);
      state = state.copyWith(
          isLoading: false, isAuthenticated: true, userId: auth.userId);
      return true;
    } on AppException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Connection failed');
      return false;
    }
  }

  Future<void> logout() async {
    try { await _storage.clearAll(); } catch (_) {}
    state = const AuthState(isInitialized: true);
  }

  Future<bool> deleteAccount(ApiClient api) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await api.delete('/user/account');
      await _storage.clearAll();
      state = const AuthState(isInitialized: true);
      return true;
    } on AppException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(isLoading: false, error: 'Could not delete account.');
      return false;
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.read(apiProvider), ref.read(storageProvider)),
);

// ── Journal (streaming) ───────────────────────────────────────────────────────

class JournalState {
  final bool isSubmitting;
  final String? streamStatusLabel;
  final JournalResponse? result;
  final String? error;

  const JournalState({
    this.isSubmitting      = false,
    this.streamStatusLabel,
    this.result,
    this.error,
  });

  JournalState copyWith({
    bool? isSubmitting,
    String? streamStatusLabel,
    JournalResponse? result,
    String? error,
  }) => JournalState(
    isSubmitting:      isSubmitting      ?? this.isSubmitting,
    streamStatusLabel: streamStatusLabel ?? this.streamStatusLabel,
    result:            result            ?? this.result,
    error:             error,
  );
}

class JournalNotifier extends StateNotifier<JournalState> {
  JournalNotifier(this._streaming, this._ref) : super(const JournalState());

  final StreamingService _streaming;
  final Ref _ref;

  Future<bool> submit(String text, int? mood) async {
    print('📝 [JOURNAL] Submitting entry...');
    print('📝 [JOURNAL] Text length: ${text.length}');
    print('📝 [JOURNAL] Mood: $mood');

    state = const JournalState(isSubmitting: true, streamStatusLabel: 'Sending…');

    try {
      await for (final event in _streaming.streamJournalEntry(
        text: text,
        moodScore: mood,
      )) {
        print('📡 [JOURNAL] Event: ${event.status}');

        switch (event.status) {
          case JournalStreamStatus.analysing:
            state = state.copyWith(streamStatusLabel: 'Analysing your entry…');
            break;
          case JournalStreamStatus.reflecting:
            state = state.copyWith(streamStatusLabel: 'Reflecting on patterns…');
            break;
          case JournalStreamStatus.supporting:
            state = state.copyWith(streamStatusLabel: 'Building your support plan…');
            break;
          case JournalStreamStatus.finalising:
            state = state.copyWith(streamStatusLabel: 'Finalising insights…');
            break;
          case JournalStreamStatus.done:
            print('✅ [JOURNAL] Done! Result: ${event.result?.detectedEmotion}');
            print('✅ [JOURNAL] Full result: ${event.result}');

            // CRITICAL: Invalidate ALL providers before setting the result
            print('🔄 [JOURNAL] Invalidating all providers...');
            _ref.invalidate(statsProvider);
            _ref.invalidate(insightsProvider);
            _ref.invalidate(dailyMessageProvider);
            _ref.invalidate(chartProvider);

            // Wait for invalidation to complete
            await Future.delayed(const Duration(milliseconds: 800));

            // Set the result
            state = JournalState(result: event.result);
            print('✅ [JOURNAL] State updated with result');
            return true;

          case JournalStreamStatus.error:
            print('❌ [JOURNAL] Error: ${event.errorMessage}');
            state = JournalState(
              error: event.errorMessage ?? 'Analysis failed. Please try again.',
            );
            return false;
        }
      }
    } catch (e, stack) {
      print('❌ [JOURNAL] Exception: $e');
      print('❌ [JOURNAL] Stack: $stack');
      state = JournalState(error: 'Unexpected error: $e');
      return false;
    }

    return false;
  }

  void clear() {
    print('🔄 [JOURNAL] Clearing state');
    state = const JournalState();
  }
}

final journalProvider = StateNotifierProvider<JournalNotifier, JournalState>(
  (ref) => JournalNotifier(ref.read(streamingProvider), ref),
);

// ── Remote data providers ─────────────────────────────────────────────────────

final statsProvider = FutureProvider<ProgressStats>((ref) async {
  print('📊 [STATS] Fetching stats...');
  try {
    final res = await ref.read(apiProvider).get('/progress/stats');
    print('📊 [STATS] Response: ${res.data}');
    final stats = ProgressStats.fromJson(res.data as Map<String, dynamic>);
    print('📊 [STATS] Parsed: streak=${stats.currentStreak}, entries=${stats.totalEntries}');
    return stats;
  } catch (e, stack) {
    print('❌ [STATS] Error: $e');
    print('❌ [STATS] Stack: $stack');
    rethrow;
  }
});

final insightsProvider = FutureProvider<List<InsightItem>>((ref) async {
  print('🔄 [INSIGHTS] Starting fetch...');
  try {
    final res = await ref.read(apiProvider).get('/journal/insights');
    print('📦 [INSIGHTS] Status: ${res.statusCode}');
    print('📦 [INSIGHTS] Data type: ${res.data.runtimeType}');
    print('📦 [INSIGHTS] Raw response: ${res.data}');

    final data = res.data as Map<String, dynamic>;
    print('📊 [INSIGHTS] Keys: ${data.keys}');
    print('📊 [INSIGHTS] Insights length: ${(data['insights'] as List?)?.length ?? 0}');

    final insightsList = data['insights'] as List? ?? [];
    print('📊 [INSIGHTS] List type: ${insightsList.runtimeType}');

    final insights = insightsList.map((i) {
      print('🔍 [INSIGHTS] Processing item: $i');
      try {
        return InsightItem.fromJson(i as Map<String, dynamic>);
      } catch (e) {
        print('❌ [INSIGHTS] Failed to parse item: $e');
        rethrow;
      }
    }).toList();

    print('✅ [INSIGHTS] Parsed ${insights.length} insights');
    if (insights.isNotEmpty) {
      print('✅ [INSIGHTS] First: ${insights.first.detectedEmotion}');
      print('✅ [INSIGHTS] First ID: ${insights.first.id}');
    }
    return insights;
  } catch (e, stack) {
    print('❌ [INSIGHTS] Error: $e');
    print('❌ [INSIGHTS] Stack: $stack');
    rethrow;
  }
});

final dailyMessageProvider = FutureProvider<DailyMessage>((ref) async {
  print('💬 [DAILY] Fetching daily message...');
  try {
    final res = await ref.read(apiProvider).get('/daily-message');
    print('💬 [DAILY] Response: ${res.data}');
    return DailyMessage.fromJson(res.data as Map<String, dynamic>);
  } catch (e, stack) {
    print('❌ [DAILY] Error: $e');
    print('❌ [DAILY] Stack: $stack');
    rethrow;
  }
});

final chartProvider = FutureProvider<List<ChartDataPoint>>((ref) async {
  print('📈 [CHART] Fetching chart data...');
  try {
    final res = await ref.read(apiProvider).get('/progress/chart');
    final data = res.data as Map<String, dynamic>;
    return (data['chart'] as List)
        .map((p) => ChartDataPoint.fromJson(p as Map<String, dynamic>))
        .toList();
  } catch (e, stack) {
    print('❌ [CHART] Error: $e');
    print('❌ [CHART] Stack: $stack');
    rethrow;
  }
});

// ── Consent ───────────────────────────────────────────────────────────────────

class ConsentState {
  final bool emailReminders;
  final bool therapistEscalation;
  final bool rehabEscalation;
  final bool dataAnalytics;
  final bool isSaving;
  final String? error;
  final bool saved;

  const ConsentState({
    this.emailReminders = false,
    this.therapistEscalation = false,
    this.rehabEscalation = false,
    this.dataAnalytics = false,
    this.isSaving = false,
    this.error,
    this.saved = false,
  });

  ConsentState copyWith({
    bool? emailReminders,
    bool? therapistEscalation,
    bool? rehabEscalation,
    bool? dataAnalytics,
    bool? isSaving,
    String? error,
    bool? saved,
  }) => ConsentState(
    emailReminders: emailReminders ?? this.emailReminders,
    therapistEscalation: therapistEscalation ?? this.therapistEscalation,
    rehabEscalation: rehabEscalation ?? this.rehabEscalation,
    dataAnalytics: dataAnalytics ?? this.dataAnalytics,
    isSaving: isSaving ?? this.isSaving,
    error: error,
    saved: saved ?? this.saved,
  );
}

class ConsentNotifier extends StateNotifier<ConsentState> {
  ConsentNotifier(this._api) : super(const ConsentState());
  final ApiClient _api;

  void toggle({
    bool? emailReminders,
    bool? therapistEscalation,
    bool? rehabEscalation,
    bool? dataAnalytics,
  }) {
    state = state.copyWith(
      emailReminders: emailReminders,
      therapistEscalation: therapistEscalation,
      rehabEscalation: rehabEscalation,
      dataAnalytics: dataAnalytics,
      saved: false,
    );
  }

  Future<bool> save() async {
    state = state.copyWith(isSaving: true, error: null, saved: false);
    try {
      await _api.post('/consent', data: {
        'email_reminders': state.emailReminders,
        'therapist_escalation': state.therapistEscalation,
        'rehab_escalation': state.rehabEscalation,
        'data_analytics': state.dataAnalytics,
      });
      state = state.copyWith(isSaving: false, saved: true);
      return true;
    } on AppException catch (e) {
      state = state.copyWith(isSaving: false, error: e.message);
      return false;
    }
  }

  Future<bool> setTherapistConsent({
    required String therapistEmail,
    required bool consentGiven,
    bool journalAccess = false,
  }) async {
    state = state.copyWith(isSaving: true, error: null);
    try {
      await _api.post('/user/therapist-consent', data: {
        'therapist_email': therapistEmail,
        'consent_given': consentGiven,
        'journal_access_consent': journalAccess,
      });
      state = state.copyWith(isSaving: false, saved: true);
      return true;
    } on AppException catch (e) {
      state = state.copyWith(isSaving: false, error: e.message);
      return false;
    }
  }
}

final consentProvider = StateNotifierProvider<ConsentNotifier, ConsentState>(
  (ref) => ConsentNotifier(ref.read(apiProvider)),
);

// ── Therapist providers ───────────────────────────────────────────────────────

final therapistPatientsProvider = FutureProvider<List<TherapistPatient>>((ref) async {
  final res = await ref.read(apiProvider).get('/therapist/patients');
  final data = res.data as Map<String, dynamic>;
  return (data['patients'] as List)
      .map((p) => TherapistPatient.fromJson(p as Map<String, dynamic>))
      .toList();
});

final patientInsightsProvider =
    FutureProvider.family<List<PatientInsight>, String>((ref, patientId) async {
  final res = await ref.read(apiProvider)
      .get('/therapist/patients/$patientId/insights');
  final data = res.data as Map<String, dynamic>;
  return (data['insights'] as List)
      .map((i) => PatientInsight.fromJson(i as Map<String, dynamic>))
      .toList();
});