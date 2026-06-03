import 'package:intl/intl.dart';

/// Query parameters for work-summary and export endpoints (E1 / T9).
Map<String, String> buildReportsQueryParams({
  String? jobId,
  String? status,
  String? workerId,
  String? floorId,
  String? system,
  String? entryType,
  DateTime? from,
  DateTime? to,
}) {
  final params = <String, String>{};
  if (jobId != null && jobId.isNotEmpty) params['jobId'] = jobId;
  if (status != null && status.isNotEmpty) params['status'] = status;
  if (workerId != null && workerId.isNotEmpty) params['workerId'] = workerId;
  if (floorId != null && floorId.isNotEmpty) params['floorId'] = floorId;
  if (system != null && system.isNotEmpty) params['system'] = system;
  if (entryType != null && entryType.isNotEmpty) params['entryType'] = entryType;
  final dateFmt = DateFormat('yyyy-MM-dd');
  if (from != null) params['from'] = dateFmt.format(from);
  if (to != null) params['to'] = dateFmt.format(to);
  return params;
}
