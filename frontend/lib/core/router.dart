import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/auth_provider.dart';
import '../features/auth/login_screen.dart';
import '../features/home/home_screen.dart';
import '../features/jobs/job_number_screen.dart';
import '../features/jobs/floor_list_screen.dart';
import '../features/seals/seal_list_screen.dart';
import '../features/seals/seal_form_screen.dart';
import '../features/seals/seal_detail_screen.dart';
import '../features/sync/sync_screen.dart';
import '../features/management/management_home_screen.dart';
import '../features/management/jobs_admin_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/logs/logs_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authUser = ref.watch(authUserProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final loggedIn = authUser != null;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      if (loggedIn) {
        final role = authUser['role'] as String?;
        final isManagement = role == 'management' || role == 'admin';
        if (!isManagement && state.matchedLocation == '/reports') {
          return '/';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: '/',
        builder: (_, __) => const HomeScreen(),
        routes: [
          GoRoute(path: 'job-number', builder: (_, __) => const JobNumberScreen()),
          GoRoute(path: 'floors/:jobId', builder: (c, s) => FloorListScreen(jobId: s.pathParameters['jobId']!)),
          GoRoute(
            path: 'seals/:floorId',
            builder: (c, s) => SealListScreen(
              floorId: s.pathParameters['floorId']!,
              jobId: s.uri.queryParameters['jobId'] ?? '',
            ),
          ),
          GoRoute(
            path: 'seal/new',
            builder: (c, s) => SealFormScreen(
              jobId: s.uri.queryParameters['jobId'] ?? '',
              floorId: s.uri.queryParameters['floorId'] ?? '',
            ),
          ),
          GoRoute(path: 'seal/:id', builder: (c, s) => SealDetailScreen(sealId: s.pathParameters['id']!)),
          GoRoute(path: 'sync', builder: (_, __) => const SyncScreen()),
          GoRoute(path: 'management', builder: (_, __) => const ManagementHomeScreen()),
          GoRoute(path: 'jobs-admin', builder: (_, __) => const JobsAdminScreen()),
          GoRoute(path: 'reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: 'logs', builder: (_, __) => const LogsScreen()),
        ],
      ),
    ],
  );
});
