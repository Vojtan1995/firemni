import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../database/database_provider.dart';
import '../jobs/jobs_cache_service.dart';
import '../../core/api/api_client.dart';
import '../../core/permissions.dart';

const _tokenKey = 'auth_token';
const _userKey = 'auth_user';
const _sessionRestoreTimeout = Duration(seconds: 10);

final authStorageProvider = Provider((_) => const FlutterSecureStorage());

final authTokenProvider = StateProvider<String?>((ref) => null);

final authUserProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

/// Current session user id for scoped offline sync (T6).
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authUserProvider)?['id'] as String?;
});

final authServiceProvider = Provider((ref) => AuthService(ref));

class LoginOutcome {
  const LoginOutcome({
    this.authenticated = false,
    this.mfaRequired = false,
    this.enrollmentRequired = false,
    this.challengeToken,
  });

  final bool authenticated;
  final bool mfaRequired;
  final bool enrollmentRequired;
  final String? challengeToken;
}

class AuthService {
  AuthService(this._ref);
  final Ref _ref;

  Dio get _dio => _ref.read(dioProvider);
  FlutterSecureStorage get _storage => _ref.read(authStorageProvider);

  Future<void> clearLocalSession() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _userKey);
    } catch (_) {}
    _ref.read(authTokenProvider.notifier).state = null;
    _ref.read(authUserProvider.notifier).state = null;
  }

  Future<void> _storeUser(Map<String, dynamic> user) async {
    await _storage.write(key: _userKey, value: jsonEncode(user));
  }

  Future<Map<String, dynamic>?> _readStoredUser() async {
    try {
      final raw = await _storage.read(key: _userKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isAuthRejection(Object error) {
    if (error is! DioException) return false;
    final status = error.response?.statusCode;
    return status == 401 || status == 403;
  }

  Future<bool> tryRestoreSession() async {
    try {
      final token = await _storage.read(key: _tokenKey);
      if (token == null) return false;
      _ref.read(authTokenProvider.notifier).state = token;
      try {
        final res = await _dio
            .get(
              '/api/auth/me',
              options: Options(
                sendTimeout: _sessionRestoreTimeout,
                receiveTimeout: _sessionRestoreTimeout,
              ),
            )
            .timeout(_sessionRestoreTimeout);
        final user = res.data as Map<String, dynamic>;
        await _storeUser(user);
        _ref.read(authUserProvider.notifier).state = user;
        return true;
      } catch (e) {
        if (_isAuthRejection(e)) {
          await clearLocalSession();
          return false;
        }
        final storedUser = await _readStoredUser();
        if (storedUser != null) {
          _ref.read(authUserProvider.notifier).state = storedUser;
          return true;
        }
        return false;
      }
    } catch (_) {
      await clearLocalSession();
      return false;
    }
  }

  Future<void> _storeSession(Map<String, dynamic> data) async {
    final token = data['token'] as String;
    final user = Map<String, dynamic>.from(data['user'] as Map);
    await _storage.write(key: _tokenKey, value: token);
    await _storeUser(user);
    _ref.read(authTokenProvider.notifier).state = token;
    _ref.read(authUserProvider.notifier).state = user;
  }

  Future<LoginOutcome> login(String username, String credential) async {
    final res = await _dio.post('/api/auth/login', data: {
      'username': username,
      'credential': credential,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    if (data['mfaRequired'] == true) {
      return LoginOutcome(
        mfaRequired: true,
        enrollmentRequired: data['enrollmentRequired'] == true,
        challengeToken: data['challengeToken'] as String?,
      );
    }
    await _storeSession(data);
    return const LoginOutcome(authenticated: true);
  }

  Future<Map<String, dynamic>> startMfaEnrollment(String challengeToken) async {
    final res = await _dio.post('/api/auth/mfa/enroll/start', data: {
      'challengeToken': challengeToken,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<List<String>> confirmMfaEnrollment(
    String challengeToken,
    String code,
  ) async {
    final res = await _dio.post('/api/auth/mfa/enroll/confirm', data: {
      'challengeToken': challengeToken,
      'code': code,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    await _storeSession(data);
    return (data['recoveryCodes'] as List).cast<String>();
  }

  Future<void> verifyMfaLogin(String challengeToken, String code) async {
    final res = await _dio.post('/api/auth/mfa/verify-login', data: {
      'challengeToken': challengeToken,
      'code': code,
    });
    await _storeSession(Map<String, dynamic>.from(res.data as Map));
  }

  Future<void> useMfaRecovery(String challengeToken, String code) async {
    final res = await _dio.post('/api/auth/mfa/recovery', data: {
      'challengeToken': challengeToken,
      'code': code,
    });
    await _storeSession(Map<String, dynamic>.from(res.data as Map));
  }

  Future<void> stepUpMfa(String code) async {
    await _dio.post('/api/auth/mfa/step-up', data: {'code': code});
  }

  Future<void> changePin(String currentPin, String newPin) async {
    final res = await _dio.post('/api/auth/change-pin', data: {
      'currentPin': currentPin,
      'newPin': newPin,
    });
    final user = res.data as Map<String, dynamic>;
    await _storeUser(user);
    _ref.read(authUserProvider.notifier).state = user;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/auth/logout');
    } catch (_) {}
    final userId = _ref.read(currentUserIdProvider);
    if (userId != null) {
      await JobsCacheService(_ref.read(databaseProvider)).clearUserScopedCache(userId);
    }
    await clearLocalSession();
  }

  String? get role => _ref.read(authUserProvider)?['role'] as String?;
  /// Status workera pro výběr ceníku (s materiálem / bez materiálu).
  /// Default bez materiálu, pokud chybí.
  String get materialMode =>
      (_ref.read(authUserProvider)?['materialMode'] as String?) ??
      'without_material';
  bool get isWorker => role == 'worker';
  bool get isVedeni => role == 'vedeni';
  bool get isAdmin => role == 'admin';
  bool get isSuperAdmin => isAdmin;
  bool get isManagement => isVedeni || isAdmin;
  bool get canChangeSealStatus => AppPermissions.has(role, 'seal.status');
  bool get canReviewSeal => isVedeni || isAdmin;
  bool get canInvoiceSeal => canChangeSealStatus;
  bool get canAccessReports => AppPermissions.canAccessReports(role);
  bool get canViewPriceList => AppPermissions.canViewPriceList(role);
  bool get canManagePriceList => AppPermissions.canManagePriceList(role);
  bool get canManageJobs => AppPermissions.canManageJobs(role);
  bool get canManageFloorDrawings =>
      AppPermissions.canManageFloorDrawings(role);
  bool get canManageUsers => AppPermissions.canManageUsers(role);
  bool get canViewLogs => AppPermissions.canViewLogs(role);
  bool get canAccessTrash => AppPermissions.canAccessTrash(role);
  bool get canViewSealHistory => AppPermissions.canViewSealHistory(role);
  bool get canViewStats => AppPermissions.canViewStats(role);
  bool get canManageWorksheets => AppPermissions.canManageWorksheets(role);
  bool get canCreateWorksheet => AppPermissions.canCreateWorksheet(role);
  bool get canSubmitWorksheet => AppPermissions.canSubmitWorksheet(role);
  bool get canReviewWorksheet => AppPermissions.canReviewWorksheet(role);
  bool get canInvoiceWorksheet => AppPermissions.canInvoiceWorksheet(role);
  bool get canDeleteWorksheet => AppPermissions.canDeleteWorksheet(role);
  bool get mustChangePin =>
      _ref.read(authUserProvider)?['mustChangePin'] == true;
}
