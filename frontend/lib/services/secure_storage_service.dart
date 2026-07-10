import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:serenity/core/constants/app_constants.dart';

class SecureStorageService {
  static const _s = FlutterSecureStorage(
    webOptions: WebOptions(dbName: 'serenity_vault', publicKey: 'serenity_pub'),
  );

  Future<void>  saveToken(String t)  => _s.write(key: AppConstants.tokenKey,      value: t);
  Future<String?> getToken()         => _s.read(key: AppConstants.tokenKey);
  Future<void>  deleteToken()        => _s.delete(key: AppConstants.tokenKey);
  Future<void>  saveUserId(String id)=> _s.write(key: AppConstants.userIdKey,      value: id);
  Future<String?> getUserId()        => _s.read(key: AppConstants.userIdKey);
  Future<void>  setOnboardingDone()  => _s.write(key: AppConstants.onboardingKey,  value: 'true');
  Future<bool>  isOnboardingDone()   async =>
      await _s.read(key: AppConstants.onboardingKey) == 'true';
  Future<void>  clearAll()           => _s.deleteAll();
}
