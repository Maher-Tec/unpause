# Unpause developer walkthrough

Unpause is an open-source Flutter app for viewing Supabase projects and requesting restoration of paused projects. It talks directly to the Supabase Management API; there is no app backend.

## Current behavior

- The user enters a Supabase personal access token (PAT). Unpause checks project-list access before saving it in platform secure storage.
- Project listing uses `GET /v1/projects` and displays the project name, region, and status.
- Project status `INACTIVE` is represented as `PAUSED`; unknown API statuses remain `UNKNOWN`.
- A restore action requires explicit confirmation and calls `POST /v1/projects/{ref}/restore`.
- Unpause polls `GET /v1/projects/{ref}` while restoration is underway, with a five-minute timeout and transient-error backoff.
- Pending restore references are stored locally so a relaunch can reconcile them against current Supabase status.
- Numeric and HTTP-date `Retry-After` values are handled by the API service.

## Supabase permissions

The app's `GET /v1/projects` call requires **Projects (account-wide) Read** for scoped PATs. Restoring a project requires **Project Settings Read-write** for that project. A user's Supabase role still limits what their PAT can access. See the [Supabase PAT guide](https://supabase.com/docs/guides/platform/personal-access-tokens) and [list projects API](https://supabase.com/docs/reference/api/v1-list-all-projects).

Because project listing uses the account-wide endpoint, this app's current design requests read access to project metadata across the account. Restore access remains a write permission and should be granted only for projects the user intends to manage.

## Main source files

- `lib/main.dart`: app root, secure-storage startup recovery, token entry, and app transitions.
- `lib/models/project_status.dart`: status enum and API status mapping.
- `lib/models/supabase_project.dart`: project response parsing.
- `lib/services/supabase_management_service.dart`: authenticated Supabase Management API requests and error mapping.
- `lib/storage/token_storage.dart`: secure PAT and pending-restore persistence.
- `lib/screens/project_list_screen.dart`: project dashboard, restore confirmation, and restore polling.

## Local development

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

Android and iOS are the intended mobile targets. Web and Windows runner files are included by the Flutter project scaffold; verify secure-storage behavior and app configuration before treating those as supported targets.

## Security

The PAT is sent directly from the device to `https://api.supabase.com`. Use a scoped PAT, grant only the permissions needed, never commit or share the token, and revoke it when it is no longer needed. Unpause is an independent community project and is not affiliated with Supabase.
