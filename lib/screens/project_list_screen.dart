import 'package:flutter/material.dart';

import '../models/project_status.dart';
import '../models/supabase_project.dart';
import '../services/supabase_management_service.dart';
import '../storage/token_storage.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({
    required this.service,
    required this.onResetToken,
    this.tokenStorage,
    this.restorePollInterval = const Duration(seconds: 5),
    this.restoreTimeout = const Duration(minutes: 5),
    this.clock = DateTime.now,
    super.key,
  });

  final SupabaseManagementService service;
  final Future<void> Function() onResetToken;
  final TokenStorage? tokenStorage;
  final Duration restorePollInterval;
  final Duration restoreTimeout;
  final DateTime Function() clock;

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<SupabaseProject> _projects = [];
  final Set<String> _restoring = {};
  final Set<String> _restorePending = {};
  bool _loading = true;
  String? _error;
  int? _errorStatusCode;
  bool _pendingRestoresLoaded = false;
  Future<void>? _pendingRestoresWrite;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final projects = await widget.service.listProjects();
      var storedPending = Set<String>.of(_restorePending);
      if (!_pendingRestoresLoaded) {
        try {
          storedPending =
              await widget.tokenStorage?.getPendingRestores() ?? <String>{};
        } on Object {
          storedPending = <String>{};
          if (mounted) {
            _showError(
              'Could not load saved restore tracking. Refresh project status before retrying a restore.',
            );
          }
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        final refreshedIds = projects.map((project) => project.id).toSet();
        _restorePending
          ..clear()
          ..addAll(storedPending.where(refreshedIds.contains));
        for (final project in projects) {
          if (project.status == ProjectStatus.activeHealthy ||
              project.status == ProjectStatus.paused) {
            _restorePending.remove(project.id);
          }
        }
        _projects = projects;
        _error = null;
        _errorStatusCode = null;
        _loading = false;
        _pendingRestoresLoaded = true;
      });
      await _persistPendingRestores();
    } on SupabaseManagementException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _errorStatusCode = error.statusCode;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load projects. Please try again.';
        _errorStatusCode = null;
        _loading = false;
      });
    }
  }

  Future<void> _persistPendingRestores() async {
    final storage = widget.tokenStorage;
    if (storage == null) return;
    final previous = _pendingRestoresWrite;
    final next = () async {
      if (previous != null) {
        try {
          await previous;
        } on Object {
          // A failed write must not prevent future attempts from saving state.
        }
      }
      await storage.savePendingRestores(Set<String>.of(_restorePending));
    }();
    _pendingRestoresWrite = next;
    try {
      await next;
    } on Object {
      if (mounted) {
        _showError(
          'Could not save restore tracking. Refresh project status before retrying.',
        );
      }
    }
  }

  Future<void> _restoreProject(SupabaseProject project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Restore ${project.name}?'),
        content: const Text(
          'Supabase may need a few minutes to bring all services back online.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore project'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _restoring.add(project.id));
    try {
      await widget.service.restoreProject(project.id);
      if (mounted) {
        setState(() => _restorePending.add(project.id));
        await _persistPendingRestores();
      }
    } on SupabaseManagementException catch (error) {
      if (mounted) {
        final requestMayHaveStarted =
            error.statusCode == null || error.statusCode! >= 500;
        _showError(
          error.message,
          allowTokenReset: error.statusCode == 401 || error.statusCode == 403,
        );
        setState(() {
          if (requestMayHaveStarted) _restorePending.add(project.id);
          _restoring.remove(project.id);
        });
        if (requestMayHaveStarted) await _persistPendingRestores();
      }
      return;
    } catch (_) {
      if (mounted) {
        _showError(
          'Could not start the restore. Please check status before retrying.',
        );
        setState(() {
          _restorePending.add(project.id);
          _restoring.remove(project.id);
        });
        await _persistPendingRestores();
      }
      return;
    }

    try {
      final deadline = widget.clock().add(widget.restoreTimeout);
      SupabaseProject latest = project;
      var restoreComplete = false;
      var transientAttempt = 0;
      SupabaseManagementException? lastTransientError;
      var delay = widget.restorePollInterval;
      while (widget.clock().isBefore(deadline)) {
        final remaining = deadline.difference(widget.clock());
        await Future<void>.delayed(
          delay.compareTo(remaining) > 0 ? remaining : delay,
        );
        if (!widget.clock().isBefore(deadline)) break;
        try {
          latest = await widget.service.getProject(project.id);
          lastTransientError = null;
          transientAttempt = 0;
          delay = widget.restorePollInterval;
          if (latest.status == ProjectStatus.activeHealthy) {
            restoreComplete = true;
            break;
          }
        } on SupabaseManagementException catch (error) {
          final code = error.statusCode;
          final transient = code == null || code == 429 || code >= 500;
          if (!transient) rethrow;
          lastTransientError = error;
          final exponent = transientAttempt < 4 ? transientAttempt : 4;
          transientAttempt++;
          delay =
              error.retryAfter ??
              Duration(
                seconds:
                    (widget.restorePollInterval.inSeconds * (1 << exponent))
                        .clamp(1, 30)
                        .toInt(),
              );
        }
      }
      if (!mounted) return;
      setState(() {
        final index = _projects.indexWhere((item) => item.id == project.id);
        if (index >= 0) _projects[index] = latest;
        if (latest.status == ProjectStatus.activeHealthy) {
          _restorePending.remove(project.id);
        }
      });
      await _persistPendingRestores();
      if (!restoreComplete && mounted) {
        final message = lastTransientError == null
            ? 'Restore request sent. Refresh status before trying again.'
            : 'Restore is pending; status check failed: ${lastTransientError.message}';
        _showError(message);
      }
    } on SupabaseManagementException catch (error) {
      if (mounted) {
        _showError(
          error.message,
          allowTokenReset: error.statusCode == 401 || error.statusCode == 403,
        );
      }
    } catch (_) {
      if (mounted) {
        _showError('Could not check the restore status. Refresh to try again.');
      }
    } finally {
      if (mounted) setState(() => _restoring.remove(project.id));
    }
  }

  void _showError(String message, {bool allowTokenReset = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: allowTokenReset
            ? SnackBarAction(
                label: 'Change token',
                onPressed: () {
                  widget.onResetToken();
                },
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: _buildBody()));
  }

  Widget _buildBody() {
    if (_loading) return const _DashboardLoadingState();
    if (_error != null) {
      return _ErrorState(
        message: _error!,
        credentialsRejected: _errorStatusCode == 401 || _errorStatusCode == 403,
        onRetry: _loadProjects,
        onReset: widget.onResetToken,
      );
    }
    if (_projects.isEmpty) return _EmptyState(onRefresh: _loadProjects);

    final visibleProjects = _projects.where((project) {
      final query = _searchQuery.trim().toLowerCase();
      return query.isEmpty ||
          project.name.toLowerCase().contains(query) ||
          project.region.toLowerCase().contains(query) ||
          project.id.toLowerCase().contains(query);
    }).toList();

    final pausedCount = _projects
        .where((project) => project.status == ProjectStatus.paused)
        .length;
    final activeCount = _projects
        .where((project) => project.status == ProjectStatus.activeHealthy)
        .length;

    return RefreshIndicator(
      color: const Color(0xFF5B5CE2),
      onRefresh: () => _loadProjects(showLoading: false),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _DashboardHeader(onRefresh: _loadProjects)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: _SummaryCard(
                total: _projects.length,
                active: activeCount,
                paused: pausedCount,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your projects',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Text(
                    '${_projects.length} total',
                    style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.45),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Search projects or regions',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: const BorderSide(color: Color(0xFFE8EAF1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: const BorderSide(color: Color(0xFFE8EAF1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(17),
                    borderSide: const BorderSide(
                      color: Color(0xFF645CF2),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
            sliver: SliverList.builder(
              itemCount: visibleProjects.length,
              itemBuilder: (context, index) {
                final project = visibleProjects[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProjectCard(
                    project: project,
                    restoring: _restoring.contains(project.id),
                    restorePending: _restorePending.contains(project.id),
                    onRestore: () => _restoreProject(project),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(14, 12, 14, 22),
    padding: const EdgeInsets.fromLTRB(22, 20, 20, 23),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF101728), Color(0xFF292C5B), Color(0xFF5147A8)],
      ),
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF302D73).withValues(alpha: .22),
          blurRadius: 28,
          offset: const Offset(0, 13),
        ),
      ],
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          right: -12,
          top: 10,
          child: Icon(
            Icons.blur_on_rounded,
            size: 140,
            color: Colors.white.withValues(alpha: .045),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .13),
                    ),
                  ),
                  child: Image.asset(
                    'assets/brand/unpause-mark.png',
                    width: 28,
                    height: 28,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UNPAUSE  /  SUPABASE',
                        style: TextStyle(
                          color: Color(0xFFB8B9E8),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Project control',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh projects',
                  onPressed: onRefresh,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: .11),
                    foregroundColor: Colors.white,
                    fixedSize: const Size(42, 42),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 25),
            const Text(
              'Everything in\none calm place.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 29,
                height: 1.04,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.1,
              ),
            ),
            const SizedBox(height: 11),
            const Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 15,
                  color: Color(0xFFC5C2FF),
                ),
                SizedBox(width: 7),
                Text(
                  'Your Supabase projects, at a glance',
                  style: TextStyle(
                    color: Color(0xFFD3D4EC),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.total,
    required this.active,
    required this.paused,
  });

  final int total;
  final int active;
  final int paused;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -1),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              _Metric(
                value: '$total',
                label: 'Projects',
                color: const Color(0xFF5B5CE2),
              ),
              _MetricDivider(),
              _Metric(
                value: '$active',
                label: 'Healthy',
                color: const Color(0xFF168A61),
              ),
              _MetricDivider(),
              _Metric(
                value: '$paused',
                label: 'Paused',
                color: const Color(0xFFCF4C5A),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 25,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.48),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height: 34,
    width: 1,
    color: Colors.black.withValues(alpha: 0.08),
  );
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.restoring,
    required this.restorePending,
    required this.onRestore,
  });

  final SupabaseProject project;
  final bool restoring;
  final bool restorePending;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 17, 14, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.public_rounded,
                            size: 14,
                            color: Color(0xFF85899B),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            project.region,
                            style: const TextStyle(
                              color: Color(0xFF85899B),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (restoring || restorePending)
                  const _RestoreLoader()
                else
                  _StatusPill(status: project.status),
              ],
            ),
            if (!restoring &&
                !restorePending &&
                project.status == ProjectStatus.paused) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: const Text('Restore project'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5B5CE2),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
            if (restoring || restorePending) ...[
              const SizedBox(height: 14),
              Text(
                restoring
                    ? 'Restoring services… this can take a few minutes.'
                    : 'Restore request sent. Refresh status before trying again.',
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.52),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RestoreLoader extends StatelessWidget {
  const _RestoreLoader();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 24,
    width: 24,
    child: CircularProgressIndicator(
      strokeWidth: 2.5,
      color: Color(0xFF5B5CE2),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final ProjectStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      ProjectStatus.activeHealthy => (
        'ACTIVE',
        const Color(0xFF168A61),
        Icons.check_circle_rounded,
      ),
      ProjectStatus.paused => (
        'PAUSED',
        const Color(0xFFCF4C5A),
        Icons.pause_circle_filled_rounded,
      ),
      ProjectStatus.goingDown => (
        'GOING DOWN',
        const Color(0xFFD9822B),
        Icons.warning_rounded,
      ),
      ProjectStatus.restoring => (
        'RESTORING',
        const Color(0xFFD9822B),
        Icons.autorenew_rounded,
      ),
      ProjectStatus.unknown => (
        'UNKNOWN',
        const Color(0xFF7A7F91),
        Icons.help_rounded,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardLoadingState extends StatelessWidget {
  const _DashboardLoadingState();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F7FB),
    body: SafeArea(
      child: Column(
        children: [
          Container(
            height: 168,
            margin: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF101728), Color(0xFF5147A8)],
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Center(
              child: SizedBox(
                height: 28,
                width: 28,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: List.generate(
                2,
                (_) => Expanded(
                  child: Container(
                    height: 64,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          ...List.generate(
            2,
            (_) => Container(
              height: 64,
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.credentialsRejected,
    required this.onRetry,
    required this.onReset,
  });

  final String message;
  final bool credentialsRejected;
  final Future<void> Function() onRetry;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: 46,
            color: Color(0xFF777C91),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
          if (credentialsRejected)
            TextButton(onPressed: onReset, child: const Text('Change token')),
        ],
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.layers_clear_rounded,
            size: 48,
            color: Color(0xFF777C91),
          ),
          const SizedBox(height: 16),
          const Text(
            'No projects found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Your Supabase projects will appear here.',
            style: TextStyle(color: Colors.black.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 18),
          OutlinedButton(onPressed: onRefresh, child: const Text('Refresh')),
        ],
      ),
    ),
  );
}
