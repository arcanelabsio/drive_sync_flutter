/// OAuth scope modes supported by [GoogleDriveAdapter].
///
/// Each mode maps to a Google OAuth scope and dictates what files the
/// adapter can see and where they live. Choose based on your app's
/// architecture and compliance posture — see the README for a full
/// comparison.
library;

/// The OAuth scope the adapter operates under.
///
/// This is a declaration, not a check: the library cannot verify at
/// construction time that the supplied [http.Client] actually has the
/// declared scope. If the declared scope and the token's real scope
/// disagree, the first Drive API call will fail with [DriveScopeError].
enum DriveScope {
  /// Full `https://www.googleapis.com/auth/drive` scope.
  ///
  /// The app can see and manage every file in the user's Drive. Required
  /// if files are written by anything other than this OAuth client — for
  /// example, Google Drive Desktop uploads, CLI tools, or companion apps
  /// with a different client ID.
  ///
  /// **Compliance cost:** Google classifies this as a *restricted* scope.
  /// Public distribution requires OAuth verification **and** annual CASA
  /// (Cloud Application Security Assessment) — a third-party security
  /// audit costing ~$5K–$20K/year.
  ///
  /// In test mode, refresh tokens expire every 7 days.
  fullDrive,

  /// `https://www.googleapis.com/auth/drive.file` scope.
  ///
  /// The app can only see files **it created**. Files created by other
  /// OAuth clients, by the user manually, or via Google Drive Desktop
  /// are invisible — even if they live in the same folder.
  ///
  /// **Compliance cost:** *Non-sensitive* scope. Standard OAuth
  /// verification only (brand + privacy policy). No CASA.
  ///
  /// Good for: single-writer app sync where this app owns all the data.
  /// Bad for: any pattern where multiple writers produce files the app
  /// needs to read.
  driveFile,

  /// `https://www.googleapis.com/auth/drive.appdata` scope.
  ///
  /// The app reads and writes to a hidden `appDataFolder` — a per-OAuth-
  /// client folder that is invisible to the user in Drive UI and can
  /// only be accessed by this exact client ID. Paths are scoped within
  /// `appDataFolder`, not rooted at the user's Drive root.
  ///
  /// **Compliance cost:** *Non-sensitive* scope. No CASA.
  ///
  /// Good for: internal app state, preferences, caches. Data the user
  /// should never see or manage directly.
  /// Bad for: anything the user needs to inspect, share, or carry
  /// between installations with different OAuth client IDs.
  appData,
}

/// Thrown when a Drive API call fails because the adapter's declared
/// [DriveScope] does not match the actual scope on the supplied
/// `http.Client`.
///
/// Typical cause: an adapter was constructed with
/// [GoogleDriveAdapter.userDrive] (which needs full `drive` scope) but
/// the auth client was obtained with `drive.file` only. The first Drive
/// API call — usually [GoogleDriveAdapter.ensureFolder] — returns a 403
/// and is re-raised as this error with a clear remediation message.
class DriveScopeError extends Error {
  final DriveScope declaredScope;
  final String message;
  final Object? cause;

  DriveScopeError({
    required this.declaredScope,
    required this.message,
    this.cause,
  });

  @override
  String toString() =>
      'DriveScopeError(declared=$declaredScope): $message'
      '${cause != null ? '\nCaused by: $cause' : ''}';
}
