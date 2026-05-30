import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/api/api_client.dart';

const _tokenKey = 'auth_token';
const _sessionRestoreTimeout = Duration(seconds: 10);

final authStorageProvider = Provider((_) => const FlutterSecureStorage());

final authTokenProvider = StateProvider<String?>((ref) => null);

final authUserProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

final authServiceProvider = Provider((ref) => AuthService(ref));

class AuthService {
  AuthService(this._ref);
  final Ref _ref;

  Dio get _dio => _ref.read(dioProvider);
  FlutterSecureStorage get _storage => _ref.read(authStorageProvider);

  Future<void> clearLocalSession() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
    _ref.read(authTokenProvider.notifier).state = null;
    _ref.read(authUserProvider.notifier).state = null;
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
        _ref.read(authUserProvider.notifier).state = res.data as Map<String, dynamic>;
        return true;
      } catch (_) {
        await clearLocalSession();
        return false;
      }
    } catch (_) {
      await clearLocalSession();
      return false;
    }
  }

  Future<void> login(String username, String pin) async {
    final res = await _dio.post('/api/auth/login', data: {
      'username': username,
      'pin': pin,
    });
    final data = res.data as Map<String, dynamic>;
    final token = data['token'] as String;
    await _storage.write(key: _tokenKey, value: token);
    _ref.read(authTokenProvider.notifier).state = token;
    _ref.read(authUserProvider.notifier).state = data['user'] as Map<String, dynamic>;
  }

  Future<void> logout() async {
    try {
      await _dio.post('/api/auth/logout');
    } catch (_) {}
    await clearLocalSession();
  }

  String? get role => _ref.read(authUserProvider)?['role'] as String?;
  bool get isWorker => role == 'worker';
  bool get isManagement => role == 'management' || role == 'admin';
  bool get isAdmin => role == 'admin';
}
