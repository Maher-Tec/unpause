import 'package:flutter_test/flutter_test.dart';
import 'package:unpause/models/project_status.dart';
import 'package:unpause/models/supabase_project.dart';

void main() {
  group('SupabaseProject.fromJson', () {
    test('maps the API ref and project fields', () {
      final project = SupabaseProject.fromJson({
        'id': 'internal-id',
        'ref': 'project-ref',
        'name': 'My project',
        'status': 'ACTIVE_HEALTHY',
        'region': 'eu-west-1',
        'created_at': '2026-10-15T10:00:00Z',
        'organization_id': 'org-id',
      });

      expect(project.id, 'project-ref');
      expect(project.name, 'My project');
      expect(project.status, ProjectStatus.activeHealthy);
      expect(project.region, 'eu-west-1');
      expect(project.createdAt, DateTime.parse('2026-10-15T10:00:00Z'));
      expect(project.organizationId, 'org-id');
    });

    test('maps inactive and restoring API states', () {
      expect(
        SupabaseProject.fromJson({'ref': 'p', 'status': 'INACTIVE'}).status,
        ProjectStatus.paused,
      );
      expect(
        SupabaseProject.fromJson({'ref': 'p', 'status': 'RESTORING'}).status,
        ProjectStatus.restoring,
      );
    });

    test('uses safe defaults for optional fields and unknown states', () {
      final project = SupabaseProject.fromJson({'ref': 'p'});

      expect(project.name, 'Unnamed project');
      expect(project.region, 'Unknown region');
      expect(project.organizationId, isEmpty);
      expect(project.status, ProjectStatus.unknown);
      expect(
        project.createdAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });
}
