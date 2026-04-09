/// Bidirectional file sync between device storage and Google Drive.
///
/// Provides SHA256-based change detection, pluggable conflict resolution,
/// and sandboxed folder access scoped to `.app/{appName}/`.
///
/// ```dart
/// import 'package:drive_sync_flutter/drive_sync_flutter.dart';
///
/// final adapter = GoogleDriveAdapter.sandboxed(
///   httpClient: authClient,
///   appName: 'my_app',
///   subPath: 'Backups',
/// );
/// final client = DriveSyncClient(adapter: adapter);
/// final result = await client.sync(localPath: '/path/to/data');
/// ```
library;

export 'src/models.dart';
export 'src/drive_adapter.dart';
export 'src/google_drive_adapter.dart';
export 'src/google_auth_client.dart';
export 'src/sandbox_validator.dart';
export 'src/manifest_differ.dart';
export 'src/conflict_resolver.dart';
export 'src/sync_engine.dart';
export 'src/drive_sync_client.dart';
