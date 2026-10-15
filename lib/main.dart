import 'package:flutter/material.dart';

import 'screens/project_list_screen.dart';
import 'services/supabase_management_service.dart';
import 'storage/token_storage.dart';

void main() {
  runApp(const UnpauseApp());
}

class UnpauseApp extends StatelessWidget {
  const UnpauseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unpause',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B5CE2),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(24)),
          ),
        ),
      ),
      home: const AppEntryScreen(),
    );
  }
}

class AppEntryScreen extends StatefulWidget {
  const AppEntryScreen({this.tokenStorage, super.key});

  final TokenStorage? tokenStorage;

  @override
  State<AppEntryScreen> createState() => _AppEntryScreenState();
}

class _AppEntryScreenState extends State<AppEntryScreen> {
  late final TokenStorage _tokenStorage = widget.tokenStorage ?? TokenStorage();
  String? _token;
  bool _loading = true;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _storageError = null;
      });
    }
    try {
      final token = await _tokenStorage.getToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        _loading = false;
        _storageError = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _storageError =
            'Unpause could not read saved credentials from secure storage.';
      });
    }
  }

  Future<void> _saveToken(String token) async {
    await SupabaseManagementService(token).listProjects();
    await _tokenStorage.saveToken(token);
    if (!mounted) return;
    setState(() => _token = token);
  }

  Future<void> _resetToken() async {
    try {
      await _tokenStorage.clearToken();
      if (!mounted) return;
      setState(() {
        _token = null;
        _storageError = null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _storageError =
            'Unpause could not clear the saved credential. Check device storage and retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_storageError != null) {
      return _SecureStorageErrorScreen(
        message: _storageError!,
        onRetry: _loadToken,
        onReset: _resetToken,
      );
    }

    if (_token == null || _token!.isEmpty) {
      return TokenEntryScreen(onSaved: _saveToken);
    }

    return ProjectListScreen(
      service: SupabaseManagementService(_token!),
      onResetToken: _resetToken,
      tokenStorage: _tokenStorage,
    );
  }
}

class _SecureStorageErrorScreen extends StatelessWidget {
  const _SecureStorageErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onReset,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onReset;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_clock_rounded, size: 48),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
              TextButton(
                onPressed: onReset,
                child: const Text('Clear saved token and reconnect'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class TokenEntryScreen extends StatefulWidget {
  const TokenEntryScreen({required this.onSaved, super.key});

  final Future<void> Function(String token) onSaved;

  @override
  State<TokenEntryScreen> createState() => _TokenEntryScreenState();
}

class _TokenEntryScreenState extends State<TokenEntryScreen> {
  final _controller = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final token = _controller.text.trim();
    if (token.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.onSaved(token);
    } on SupabaseManagementException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not connect. Check the token and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF10143A), Color(0xFF28245B), Color(0xFFF6F7FB)],
            stops: [0, 0.42, 0.78],
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            children: [
              const _BrandMark(),
              const SizedBox(height: 28),
              const Text(
                'Your projects,\nback online faster.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.05,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Connect your Supabase account securely to monitor and restore projects from one quiet little dashboard.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 34),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect account',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Project listing needs Projects (account-wide) Read. Restoring needs '
                        'Project Settings Read-write on each project you want to restore. ',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.56),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _TokenSetupGuide(),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _controller,
                        obscureText: true,
                        enabled: !_saving,
                        decoration: InputDecoration(
                          labelText: 'Personal Access Token',
                          hintText: 'sbp_••••••••••••',
                          prefixIcon: const Icon(Icons.key_rounded),
                          filled: true,
                          fillColor: const Color(0xFFF4F5FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _save(),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            _saving ? 'Connecting…' : 'Enter Unpause',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Stored securely on this device',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TokenSetupGuide extends StatelessWidget {
  const _TokenSetupGuide();

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF4F3FF),
      border: Border.all(color: const Color(0xFFE6E3FF)),
      borderRadius: BorderRadius.circular(17),
    ),
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 13),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: const Icon(Icons.key_rounded, color: Color(0xFF6258D9)),
        title: const Text(
          'How to get a token',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: const Text(
          'Not in Project Settings — use account settings',
          style: TextStyle(fontSize: 11, height: 1.3),
        ),
        children: const [
          _TokenGuideStep(
            number: '1',
            title: 'Where to go',
            detail:
                'In the Supabase dashboard, click your profile avatar in the top-right, then choose Account Preferences → Access Tokens. This is account-level settings—not the Project Settings page shown in your screenshots. Direct page: supabase.com/dashboard/account/tokens.',
          ),
          _TokenGuideStep(
            number: '2',
            title: 'Create a scoped Personal Access Token',
            detail:
                'Choose to create a new token, select scoped permissions, name it (for example, Unpause), and set an expiry.',
          ),
          _TokenGuideStep(
            number: '3',
            title: 'Allow project listing',
            detail:
                'Add Projects (account-wide) → Read. This is required for Unpause to show your projects.',
          ),
          _TokenGuideStep(
            number: '4',
            title: 'Allow restore on selected projects',
            detail:
                'For each project you may restore, add Project Settings → Read-write. Keep this permission off projects you will not manage.',
          ),
          _TokenGuideStep(
            number: '5',
            title: 'Create, copy, and paste',
            detail:
                'Create the token, copy it while Supabase shows it, return here, and paste it into the Personal Access Token field below.',
          ),
          SizedBox(height: 8),
          Text(
            'Use a Personal Access Token (usually starts with sbp_). Never paste a service_role key, anon/publishable key, database password, or project API key here.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Color(0xFF555C70),
            ),
          ),
        ],
      ),
    ),
  );
}

class _TokenGuideStep extends StatelessWidget {
  const _TokenGuideStep({
    required this.number,
    required this.title,
    required this.detail,
  });
  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 23,
          height: 23,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFE5E2FF),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFF584FCA),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF252A3D),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: Color(0xFF747B8F),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Image.asset(
            'assets/brand/unpause-mark.png',
            width: 28,
            height: 28,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'UNPAUSE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
