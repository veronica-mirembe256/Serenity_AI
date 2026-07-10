class AppConstants {
  // FIX: change this to your real domain before deploying.
  // In dev: 'http://localhost:8080'
  // In production: 'https://your-serenity-domain.com'
  static const String baseUrl = 'http://localhost:8080';

  // Secure storage keys
  static const String tokenKey      = 'serenity_token';
  static const String userIdKey     = 'serenity_user_id';
  static const String onboardingKey = 'serenity_onboarding';

  // Risk levels
  static const String riskLow      = 'low';
  static const String riskModerate = 'moderate';
  static const String riskHigh     = 'high';

  // API timeouts
  // receiveTimeout must be long enough for the full LLM pipeline (~20s).
  // The streaming endpoint keeps the connection open the whole time.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 60);
}