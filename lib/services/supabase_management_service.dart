import 'package:dio/dio.dart';

import '../models/supabase_project.dart';

class SupabaseManagementException implements Exception {
  const SupabaseManagementException({
    this.statusCode,
    this.retryAfter,
    required this.message,
  });

  final int? statusCode;
  final Duration? retryAfter;
  final String message;

  @override
  String toString() => message;
}

class SupabaseManagementService {
  SupabaseManagementService(String token, {Dio? client})
    : _dio =
          client ??
          Dio(
            BaseOptions(
              baseUrl: 'https://api.supabase.com',
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          ) {
    _dio.options.connectTimeout ??= const Duration(seconds: 15);
    _dio.options.sendTimeout ??= const Duration(seconds: 15);
    _dio.options.receiveTimeout ??= const Duration(seconds: 30);
    _dio.options.headers['Authorization'] = 'Bearer $token';
    _dio.options.headers['Accept'] = 'application/json';
  }

  final Dio _dio;

  Future<List<SupabaseProject>> listProjects() async {
    final response = await _request(
      () => _dio.get<List<dynamic>>('/v1/projects'),
    );
    final data = response.data;
    if (data is! List) {
      throw const SupabaseManagementException(
        message: 'Unexpected response from Supabase API',
      );
    }
    try {
      return data.map((project) {
        if (project is! Map) {
          throw const FormatException('Project entry is not an object');
        }
        return SupabaseProject.fromJson(Map<String, dynamic>.from(project));
      }).toList();
    } on Object {
      throw const SupabaseManagementException(
        message: 'Supabase returned invalid project data',
      );
    }
  }

  Future<void> restoreProject(String projectRef) async {
    await _request(
      () => _dio.post<void>(
        '/v1/projects/${Uri.encodeComponent(projectRef)}/restore',
      ),
    );
  }

  Future<SupabaseProject> getProject(String projectRef) async {
    final response = await _request(
      () => _dio.get<Map<String, dynamic>>(
        '/v1/projects/${Uri.encodeComponent(projectRef)}',
      ),
    );
    final data = response.data;
    if (data == null) {
      throw const SupabaseManagementException(
        message: 'Unexpected response from Supabase API',
      );
    }
    try {
      return SupabaseProject.fromJson(data);
    } on Object {
      throw const SupabaseManagementException(
        message: 'Supabase returned invalid project data',
      );
    }
  }

  Future<Response<T>> _request<T>(
    Future<Response<T>> Function() request,
  ) async {
    try {
      return await request();
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      throw SupabaseManagementException(
        statusCode: statusCode,
        retryAfter: _retryAfter(error.response?.headers),
        message: _messageFor(statusCode, error),
      );
    }
  }

  Duration? _retryAfter(Headers? headers) {
    final raw = headers?.value('retry-after');
    if (raw == null) return null;
    final trimmed = raw.trim();
    final seconds = int.tryParse(trimmed);
    if (seconds != null) {
      return seconds <= 0 ? null : Duration(seconds: seconds);
    }
    final retryAt = _parseHttpDate(trimmed);
    if (retryAt == null) return null;
    final delay = retryAt.difference(DateTime.now().toUtc());
    return delay.isNegative || delay == Duration.zero ? null : delay;
  }

  DateTime? _parseHttpDate(String value) {
    const months = {
      'Jan': 1,
      'Feb': 2,
      'Mar': 3,
      'Apr': 4,
      'May': 5,
      'Jun': 6,
      'Jul': 7,
      'Aug': 8,
      'Sep': 9,
      'Oct': 10,
      'Nov': 11,
      'Dec': 12,
    };
    final imf = RegExp(
      r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) ([A-Z][a-z]{2}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    final rfc850 = RegExp(
      r'^(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), (\d{2})-([A-Z][a-z]{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    final asctime = RegExp(
      r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) ([A-Z][a-z]{2})\s+(\d{1,2}) (\d{2}):(\d{2}):(\d{2}) (\d{4})$',
    ).firstMatch(value);

    int? day;
    int? month;
    int? year;
    int? hour;
    int? minute;
    int? second;
    if (imf != null) {
      day = int.tryParse(imf[1]!);
      month = months[imf[2]];
      year = int.tryParse(imf[3]!);
      hour = int.tryParse(imf[4]!);
      minute = int.tryParse(imf[5]!);
      second = int.tryParse(imf[6]!);
    } else if (rfc850 != null) {
      day = int.tryParse(rfc850[1]!);
      month = months[rfc850[2]];
      final shortYear = int.tryParse(rfc850[3]!);
      year = shortYear == null
          ? null
          : (DateTime.now().year ~/ 100) * 100 + shortYear;
      if (year != null && year > DateTime.now().year + 50) year -= 100;
      hour = int.tryParse(rfc850[4]!);
      minute = int.tryParse(rfc850[5]!);
      second = int.tryParse(rfc850[6]!);
    } else if (asctime != null) {
      month = months[asctime[1]];
      day = int.tryParse(asctime[2]!);
      hour = int.tryParse(asctime[3]!);
      minute = int.tryParse(asctime[4]!);
      second = int.tryParse(asctime[5]!);
      year = int.tryParse(asctime[6]!);
    } else {
      return null;
    }

    if (day == null ||
        month == null ||
        year == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }
    final date = DateTime.utc(year, month, day, hour, minute, second);
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        date.hour != hour ||
        date.minute != minute ||
        date.second != second) {
      return null;
    }
    return date;
  }

  String _messageFor(int? statusCode, DioException error) {
    switch (statusCode) {
      case 401:
        return 'Token invalid or expired. Connect a new token.';
      case 403:
        return 'Token lacks permission. Project listing needs Projects (account-wide) Read; restoring needs Project Settings Read-write for this project.';
      case 429:
        return 'Supabase rate limited the request. Retrying shortly.';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'Supabase API error, try again';
      default:
        if (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout) {
          return 'Network error, check connection';
        }
        return 'Request failed${statusCode == null ? '' : ' (HTTP $statusCode)'}';
    }
  }
}
