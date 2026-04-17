/// Bidirectional file sync between device storage and Google Drive.
///
/// Provides SHA256-based change detection, pluggable conflict resolution,
/// and three OAuth scope modes (full `drive`, `drive.file`, `drive.appdata`)
/// so consumers can choose their compliance posture.
///
/// ```dart
/// import 'package:drive_sync_flutter/drive_sync_flutter.dart';
///
/// // drive.file — non-sensitive scope, no CASA. App sees only files it created.
/// final adapter = GoogleDriveAdapter.appFiles(
///   httpClient: authClient,
///   folderName: 'MyApp',
///   subPath: 'Backups',
/// );
/// final client = DriveSyncClient(adapter: adapter);
/// final result = await client.sync(localPath: '/path/to/data');
/// ```
library;

export 'src/models.dart';
export 'src/drive_adapter.dart';
export 'src/drive_scope.dart';
export 'src/google_drive_adapter.dart';
export 'src/google_auth_client.dart';
export 'src/sandbox_validator.dart';
export 'src/manifest_differ.dart';
export 'src/conflict_resolver.dart';
export 'src/sync_engine.dart';
export 'src/drive_sync_client.dart';
