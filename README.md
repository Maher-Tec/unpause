# Unpause

<p align="center"><img src="assets/brand/unpause-logo.svg" alt="Unpause — Supabase project control" width="640"></p>

A Flutter app for monitoring your Supabase projects and requesting a restore for paused projects. It connects directly to the Supabase Management API using a personal access token (PAT).

> **Status:** early-stage, community project. Review the limitations and security notes before connecting an account.

## Features

- Lists the Supabase projects accessible to your PAT.
- Shows project state, region, and basic account totals.
- Requests restore for a paused project and polls its status.
- Stores the PAT and pending restore references in platform secure storage.
- Keeps uncertain restore requests pending across app restarts until a fresh API status check resolves them.

## Requirements

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml`.
- A Supabase account and a scoped PAT with **Projects (account-wide) Read** to list projects, plus **Project Settings Read-write** on each project you want to restore.
- Android or iOS device/emulator for the intended mobile experience.

## Run locally

Clone this repository from its GitHub URL, then run:

```sh
cd unpause
flutter pub get
flutter run
```

To run the checks:

```sh
flutter analyze
flutter test
```

## Connect Supabase

1. Create a scoped Supabase personal access token. This app uses `GET /v1/projects`, which requires **Projects (account-wide) Read**. Restoring additionally requires **Project Settings Read-write** on each intended project.
2. Enter the PAT in the app. The app checks that it can list projects before saving it.
3. Select a paused project and confirm the restore request.
4. Keep the app connected to the network while it checks project status. If polling times out, refresh to reconcile the current status before retrying.

A restore request acts on your Supabase project and may take several minutes. Check Supabase's current pricing, restore behavior, and project state before using it. This app cannot guarantee that Supabase will complete a restore.

## Security and privacy

- The PAT is sent from the device directly to `https://api.supabase.com` as a bearer token.
- The PAT is stored using `flutter_secure_storage`; do not paste a PAT into an issue, screenshot, log, or source file.
- Use a scoped token and grant only the required permissions. Project listing reads project metadata account-wide; restore permission should be limited to the projects you intend to manage. Revoke the token in Supabase when it is no longer needed.
- The app does not include a backend proxy or OAuth flow. You are responsible for protecting the device and token.
- Project data and pending restore references are held on the device; pending references are not Supabase credentials.

## Contributing

Issues and pull requests are welcome. Please include steps to reproduce bugs and avoid sharing tokens or private project data. Run `flutter analyze` and `flutter test` before submitting a pull request.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).

## Disclaimer

Unpause is an independent community project and is not affiliated with or endorsed by Supabase. Supabase and its product names are trademarks of their respective owners.
