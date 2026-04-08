## 1.0.1

- Enable automated publishing from GitHub Actions via OIDC
- Verify CI → pub.dev pipeline

## 1.0.0

- Bidirectional file sync between device storage and Google Drive
- SHA256-based change detection (only transfers modified files)
- Conflict resolution: newerWins, localWins, remoteWins, askUser
- `GoogleDriveAdapter` with nested folder path support (`apps/myapp/data`)
- Pluggable `DriveAdapter` interface for custom cloud providers
- `GoogleAuthClient` helper for wrapping `google_sign_in` auth headers
- `DriveSyncClient` high-level API: sync, push, pull, status
- 30 tests covering unit, integration, and cross-component flows
