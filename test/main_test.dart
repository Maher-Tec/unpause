import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unpause/main.dart';
import 'package:unpause/storage/token_storage.dart';

class _FailingTokenStorage extends TokenStorage {
  _FailingTokenStorage() : super();

  bool failRead = true;
  bool failClear = false;
  int clearCalls = 0;

  @override
  Future<String?> getToken() async {
    if (failRead) throw StateError('secure storage unavailable');
    return null;
  }

  @override
  Future<void> clearToken() async {
    clearCalls++;
    if (failClear) throw StateError('secure storage unavailable');
  }
}

void main() {
  testWidgets('offers retry when secure storage cannot load the saved token', (
    tester,
  ) async {
    final storage = _FailingTokenStorage();
    await tester.pumpWidget(
      MaterialApp(home: AppEntryScreen(tokenStorage: storage)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Unpause could not read saved credentials from secure storage.',
      ),
      findsOneWidget,
    );

    storage.failRead = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Personal Access Token'), findsOneWidget);
  });

  testWidgets('shows a recoverable message if clearing secure storage fails', (
    tester,
  ) async {
    final storage = _FailingTokenStorage()..failClear = true;
    await tester.pumpWidget(
      MaterialApp(home: AppEntryScreen(tokenStorage: storage)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear saved token and reconnect'));
    await tester.pumpAndSettle();

    expect(storage.clearCalls, 1);
    expect(
      find.text(
        'Unpause could not clear the saved credential. Check device storage and retry.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('can clear a saved token after a secure storage read failure', (
    tester,
  ) async {
    final storage = _FailingTokenStorage();
    await tester.pumpWidget(
      MaterialApp(home: AppEntryScreen(tokenStorage: storage)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear saved token and reconnect'));
    await tester.pumpAndSettle();

    expect(storage.clearCalls, 1);
    expect(find.text('Personal Access Token'), findsOneWidget);
  });
}
