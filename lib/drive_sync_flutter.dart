/// Bidirectional file sync between device storage and Google Drive.
///
/// Provides SHA256-based change detection, pluggable conflict resolution,
/// and nested folder support for Google Drive.
///
/// ```dart
/// import 'package:drive_sync_flutter/drive_sync_flutter.dart';
///
/// final authClient = GoogleAuthClient(await account.authHeaders);
/// final adapter = GoogleDriveAdapter.withPath(
///   httpClient: authClient,
///   folderPath: 'apps/myapp/data',
/// );
/// final client = DriveSyncClient(adapter: adapter);
/// final result = await client.sync(localPath: '/path/to/data');
/// ```
library drive_sync_flutter;

export 'src/models.dart';
export 'src/drive_adapter.dart';
export 'src/google_drive_adapter.dart';
export 'src/google_auth_client.dart';
export 'src/manifest_differ.dart';
export 'src/conflict_resolver.dart';
export 'src/sync_engine.dart';
export 'src/drive_sync_client.dart';
