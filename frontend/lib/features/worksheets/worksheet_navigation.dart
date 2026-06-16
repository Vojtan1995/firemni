import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Naviguje na obrazovku soupisů s volitelnými filtry v query parametrech.
/// Sdíleno mezi domovskou obrazovkou (dlaždice „Vyžaduje akci") a statistikami.
void goToSoupisy(
  BuildContext context, {
  String? status,
  String? jobId,
  String? reportStatus,
  String? workerId,
}) {
  final params = <String, String>{};
  if (status != null) params['status'] = status;
  if (jobId != null) params['jobId'] = jobId;
  if (reportStatus != null) params['reportStatus'] = reportStatus;
  if (workerId != null) params['workerId'] = workerId;
  final uri = Uri(path: '/soupisy', queryParameters: params.isEmpty ? null : params);
  context.go(uri.toString());
}
