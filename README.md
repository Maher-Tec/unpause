<div align="center">

<img src="assets/brand/unpause-logo.svg" alt="Unpause" width="560">

### Supabase project control, from your phone

Unpause is an open-source Flutter app for viewing your Supabase projects and requesting a restore for paused projects. It connects directly to the Supabase Management API with your personal access token.

<p>
  <img src="https://img.shields.io/badge/Flutter-mobile-42A5F5?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/License-MIT-32A878" alt="MIT License">
  <img src="https://img.shields.io/badge/Status-community%20project-8B7CFF" alt="Community project">
</p>

[Getting started](#-getting-started) · [Token permissions](#-token-permissions) · [Security](#-security--privacy) · [Contributing](#-contributing)

</div>

<hr>

> [!NOTE]
> Unpause is an early-stage community project. It can request a restore, but Supabase controls whether and when the project becomes available. Review the risks and your current Supabase plan before using it.

## ✨ What it does

| Capability | Details |
| --- | --- |
| **Browse projects** | Lists Supabase projects your personal access token can access. |
| **Check status** | Displays project state, region, and basic account totals. |
| **Request restore** | Sends a restore request for a paused project and checks its status. |
| **Remember safely** | Saves the token and pending restore references in platform secure storage. |

## 🚀 Getting started

### Requirements

- Flutter SDK compatible with the Dart constraint in [`pubspec.yaml`](pubspec.yaml).
- A Supabase account and a scoped personal access token (PAT). See [Token permissions](#-token-permissions).
- An Android or iOS device or emulator for the intended mobile experience.

### Run from source

```sh
git clone https://github.com/Maher-Tec/unpause.git
cd unpause
flutter pub get
flutter run
```

### Connect your Supabase account

1. Create a scoped Supabase PAT with the permissions described below.
2. Open Unpause and paste the PAT into the connection screen. The app checks that it can list projects before saving the token.
3. Choose a paused project and confirm the restore request.
4. Keep the device online while Unpause checks the project status. If checking times out, refresh the project status before trying again.

To run the project checks:

```sh
flutter analyze
flutter test
```

## 🔐 Token permissions

Unpause needs a **Supabase Personal Access Token (PAT)**. It does not use a service-role key, anon/publishable key, database password, or project API key.

| Action | Management API request | Required access |
| --- | --- | --- |
| List projects | `GET /v1/projects` | **Projects — Read** at the account level |
| Restore a paused project | `POST /v1/projects/{ref}/restore` | **Project Settings — Read-write** for the project |

Grant only the access needed for the projects you intend to manage. In Supabase, create a scoped PAT and review its permissions before entering it in the app. Supabase may change its dashboard labels or restore behavior over time.

## 🛡️ Security & privacy

> **Your PAT can manage Supabase resources within the permissions you grant. Treat it as a secret.**

- The app sends the PAT directly from your device to `https://api.supabase.com` as a bearer token. There is no Unpause backend or OAuth proxy.
- The PAT is stored with [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage), using platform-provided secure storage.
- Do not share your PAT in screenshots, issues, logs, source files, or support requests.
- Project data and pending restore references are kept on the device. Pending references are not credentials.
- Revoke the PAT in Supabase when it is no longer needed.

## 🧰 Built with

- [Flutter](https://flutter.dev/) and Dart
- [`dio`](https://pub.dev/packages/dio) for HTTP requests
- [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) for local credential storage

## 🤝 Contributing

Issues and pull requests are welcome. Include steps to reproduce a problem, and remove tokens and private project information from reports. Please run `flutter analyze` and `flutter test` before submitting a pull request.

## 📄 License

Unpause is available under the [MIT License](LICENSE).

<hr>

<div align="center">
  <sub>Unpause is an independent community project. It is not affiliated with or endorsed by Supabase. Supabase and its product names are trademarks of their respective owners.</sub>
</div>
