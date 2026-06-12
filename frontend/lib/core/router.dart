import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/auth_provider.dart';
import '../core/permissions.dart';
import '../features/auth/change_pin_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/profile_screen.dart';
import '../features/home/home_screen.dart';
import '../features/jobs/job_number_screen.dart';
import '../features/jobs/floor_list_screen.dart';
import '../features/jobs/floor_plan_screen.dart';
import '../features/seals/seal_list_screen.dart';
import '../features/seals/seal_form_screen.dart';
import '../features/seals/seal_detail_screen.dart';
import '../features/sync/sync_screen.dart';
import '../features/management/management_home_screen.dart';
import '../features/management/jobs_admin_screen.dart';
import '../features/management/users_admin_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/pricing/price_list_screen.dart';
import '../features/logs/logs_screen.dart';
import '../features/jobs/my_jobs_screen.dart';
import '../features/jobs/jobs_screen.dart';
import '../features/messages/messages_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/search/search_screen.dart';
import '../features/admin/admin_trash_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/worksheets/worksheets_screen.dart';
import '../features/worksheets/saved_worksheets_screen.dart';
import '../features/worksheets/soupisy_screen.dart';
import '../features/worksheets/worksheet_detail_screen.dart';

/// Globální klíč pro dialogy nad celou aplikací (např. update checker).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Keeps a single [GoRouter] instance; re-runs redirect when auth changes.
class GoRouterRefresh extends ChangeNotifier {
  GoRouterRefresh(Ref ref) {
    ref.listen(authUserProvider, (_, __) => notifyListeners());
    ref.listen(authTokenProvider, (_, __) => notifyListeners());
  }
}

final _routerRefreshProvider = Provider<GoRouterRefresh>((ref) {
  final refresh = GoRouterRefresh(ref);
  ref.onDispose(refresh.dispose);
  return refresh;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    refreshListenable: refresh,
    initialLocation: '/login',
    redirect: (context, state) {
      final authUser = ref.read(authUserProvider);
      final loggedIn = authUser != null;
      final onLogin = state.matchedLocation == '/login';
      final onChangePin = state.matchedLocation == '/change-pin';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      if (loggedIn) {
        final mustChangePin = authUser['mustChangePin'] == true;
        if (mustChangePin && !onChangePin) return '/change-pin';
        if (!mustChangePin && onChangePin) return '/';
        final role = authUser['role'] as String?;
        const manageOnly = [
          '/jobs-admin',
          '/users-admin',
          '/logs',
          '/management',
        ];
        if (!AppPermissions.canAccessReports(role) &&
            !AppPermissions.canManageWorksheets(role) &&
            (state.matchedLocation == '/reports' ||
                state.matchedLocation == '/soupisy' ||
                state.matchedLocation == '/worksheets' ||
                state.matchedLocation.startsWith('/worksheets/'))) {
          return '/';
        }
        if (state.matchedLocation == '/reports' ||
            state.matchedLocation == '/worksheets') {
          return '/soupisy';
        }
        if (state.matchedLocation == '/stats' &&
            (role == 'worker' ||
                !AppPermissions.canViewStats(role))) {
          return '/';
        }
        if (!AppPermissions.canManageWorksheets(role) &&
            (state.matchedLocation == '/worksheets' ||
                state.matchedLocation.startsWith('/worksheets/'))) {
          return '/';
        }
        if (!AppPermissions.canViewPriceList(role) &&
            state.matchedLocation == '/price-list') {
          return '/';
        }
        if (!AppPermissions.canManageJobs(role) &&
            manageOnly.contains(state.matchedLocation)) {
          return '/';
        }
        if (role != 'admin' && state.matchedLocation == '/trash') {
          return '/';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/change-pin', builder: (_, __) => const ChangePinScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: '/',
        builder: (_, __) => const HomeScreen(),
        routes: [
          GoRoute(path: 'jobs', builder: (_, __) => const JobsScreen()),
          GoRoute(
              path: 'job-number',
              redirect: (_, __) => '/jobs'),
          GoRoute(
              path: 'job-number-legacy',
              builder: (_, __) => const JobNumberScreen()),
          GoRoute(
              path: 'floors/:jobId',
              builder: (c, s) =>
                  FloorListScreen(jobId: s.pathParameters['jobId']!)),
          GoRoute(
              path: 'floor-plan/:floorId',
              builder: (c, s) => FloorPlanScreen(
                jobId: s.uri.queryParameters['jobId'] ?? '',
                floorId: s.pathParameters['floorId']!,
                placeSealId: s.uri.queryParameters['placeSealId'],
                focusSealId: s.uri.queryParameters['focusSealId'],
                draftPlacement: s.uri.queryParameters['draftPlacement'] == '1',
                draftSealNumber: s.uri.queryParameters['sealNumber'],
              ),
            ),
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
          GoRoute(
            path: 'seal/:id/edit',
            builder: (c, s) => SealFormScreen(
              sealId: s.pathParameters['id'],
              jobId: s.uri.queryParameters['jobId'] ?? '',
              floorId: s.uri.queryParameters['floorId'] ?? '',
            ),
          ),
          GoRoute(
              path: 'seal/:id',
              builder: (c, s) =>
                  SealDetailScreen(sealId: s.pathParameters['id']!)),
          GoRoute(path: 'sync', builder: (_, __) => const SyncScreen()),
          GoRoute(
              path: 'my-jobs',
              redirect: (_, __) => '/jobs'),
          GoRoute(
              path: 'my-jobs-legacy',
              builder: (_, __) => const MyJobsScreen()),
          GoRoute(path: 'messages', builder: (_, __) => const MessagesScreen()),
          GoRoute(path: 'notifications', builder: (_, __) => const NotificationsScreen()),
          GoRoute(path: 'search', builder: (_, __) => const SearchScreen()),
          GoRoute(
              path: 'management',
              builder: (_, __) => const ManagementHomeScreen()),
          GoRoute(
              path: 'jobs-admin', builder: (_, __) => const JobsAdminScreen()),
          GoRoute(
              path: 'users-admin',
              builder: (_, __) => const UsersAdminScreen()),
          GoRoute(path: 'reports', builder: (_, __) => const ReportsScreen()),
          GoRoute(path: 'soupisy', builder: (_, __) => const SoupisyScreen()),
          GoRoute(
            path: 'saved-worksheets',
            builder: (_, __) => const SavedWorksheetsScreen(),
          ),
          GoRoute(path: 'worksheets', builder: (_, __) => const WorksheetsScreen()),
          GoRoute(
            path: 'worksheets/:id',
            builder: (c, s) => WorksheetDetailScreen(
              worksheetId: s.pathParameters['id']!,
            ),
          ),
          GoRoute(path: 'stats', builder: (_, __) => const StatsScreen()),
          GoRoute(path: 'price-list', builder: (_, __) => const PriceListScreen()),
          GoRoute(path: 'logs', builder: (_, __) => const LogsScreen()),
          GoRoute(path: 'trash', builder: (_, __) => const AdminTrashScreen()),
        ],
      ),
    ],
  );
});
