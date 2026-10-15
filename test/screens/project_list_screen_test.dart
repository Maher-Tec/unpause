import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unpause/models/project_status.dart';
import 'package:unpause/models/supabase_project.dart';
import 'package:unpause/screens/project_list_screen.dart';
import 'package:unpause/services/supabase_management_service.dart';
import 'package:unpause/storage/token_storage.dart';

class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage(this.pending) : super();

  Set<String> pending;

  @override
  Future<Set<String>> getPendingRestores() async => Set.of(pending);

  @override
  Future<void> savePendingRestores(Set<String> projectRefs) async {
    pending = Set.of(projectRefs);
  }
}

class _FakeManagementService extends SupabaseManagementService {
  _FakeManagementService({
    this.failList = false,
    this.listStatus = ProjectStatus.paused,
    this.responseStatus = ProjectStatus.paused,
  }) : super('test-token');

  final bool failList;
  ProjectStatus listStatus;
  ProjectStatus responseStatus;
  int restoreCalls = 0;
  int getProjectCalls = 0;

  SupabaseProject projectWithStatus(ProjectStatus status) => SupabaseProject(
    id: 'project-ref',
    name: 'Paused project',
    status: status,
    region: 'eu-west-1',
    createdAt: DateTime.utc(2026, 10, 15),
    organizationId: 'org-id',
  );

  @override
  Future<List<SupabaseProject>> listProjects() async {
    if (failList) {
      throw const SupabaseManagementException(
        statusCode: 403,
        message: 'Token lacks permission',
      );
    }
    return [projectWithStatus(listStatus)];
  }

  @override
  Future<void> restoreProject(String projectRef) async {
    restoreCalls++;
  }

  @override
  Future<SupabaseProject> getProject(String projectRef) async {
    getProjectCalls++;
    return projectWithStatus(responseStatus);
  }
}

void main() {
  testWidgets(
    'keeps an unfinished restore pending until a fresh status check',
    (tester) async {
      final service = _FakeManagementService();
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ProjectListScreen(
            service: service,
            onResetToken: () async {},
            restorePollInterval: const Duration(seconds: 1),
            restoreTimeout: const Duration(seconds: 2),
            clock: () => tester.binding.clock.now(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Restore project'), findsOneWidget);

      await tester.tap(find.text('Restore project'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Restore project').last);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(service.restoreCalls, 1);
      expect(service.getProjectCalls, greaterThanOrEqualTo(1));
      expect(
        find.text('Restore request sent. Refresh status before trying again.'),
        findsNWidgets(2),
      );
      expect(find.text('Restore project'), findsNothing);

      await tester.tap(find.byTooltip('Refresh projects'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Restore project'), findsOneWidget);
    },
  );

  testWidgets('recovers a pending restore from secure storage after restart', (
    tester,
  ) async {
    final storage = _FakeTokenStorage({'project-ref'});
    final service = _FakeManagementService(
      listStatus: ProjectStatus.restoring,
      responseStatus: ProjectStatus.restoring,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectListScreen(
          service: service,
          tokenStorage: storage,
          onResetToken: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Restore project'), findsNothing);
    expect(
      find.text('Restore request sent. Refresh status before trying again.'),
      findsOneWidget,
    );
    expect(storage.pending, {'project-ref'});

    await tester.tap(find.byTooltip('Refresh projects'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Restore project'), findsNothing);
    expect(storage.pending, {'project-ref'});

    service.listStatus = ProjectStatus.activeHealthy;
    await tester.tap(find.byTooltip('Refresh projects'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(storage.pending, isEmpty);
  });

  testWidgets('offers token change for a 403 project permission error', (
    tester,
  ) async {
    final service = _FakeManagementService(failList: true);
    var resetCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: ProjectListScreen(
          service: service,
          onResetToken: () async => resetCalled = true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Token lacks permission'), findsOneWidget);
    expect(find.text('Change token'), findsOneWidget);
    await tester.tap(find.text('Change token'));
    await tester.pump();

    expect(resetCalled, isTrue);
  });
}
