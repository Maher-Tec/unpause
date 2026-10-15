import 'project_status.dart';

class SupabaseProject {
  const SupabaseProject({
    required this.id,
    required this.name,
    required this.status,
    required this.region,
    required this.createdAt,
    required this.organizationId,
  });

  final String id;
  final String name;
  final ProjectStatus status;
  final String region;
  final DateTime createdAt;
  final String organizationId;

  factory SupabaseProject.fromJson(Map<String, dynamic> json) {
    final ref = json['ref'] as String? ?? json['id'] as String? ?? '';
    final createdAtValue = json['created_at'] as String?;
    return SupabaseProject(
      id: ref,
      name: json['name'] as String? ?? 'Unnamed project',
      status: projectStatusFromString(json['status'] as String?),
      region: json['region'] as String? ?? 'Unknown region',
      createdAt: createdAtValue == null
          ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
          : DateTime.parse(createdAtValue),
      organizationId: json['organization_id'] as String? ?? '',
    );
  }
}
