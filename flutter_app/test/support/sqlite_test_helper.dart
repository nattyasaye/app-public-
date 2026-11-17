import 'dart:ffi';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:sqlite3/open.dart';

bool _sqliteConfigured = false;

/// Ensures Linux host `flutter test` runs can resolve `libsqlite3.so` even
/// when only versioned `libsqlite3.so.0` (standard `libsqlite3-0` runtime
/// without `-dev` symlink) is present in the environment.
void configureSqliteForHostTests() {
  if (_sqliteConfigured) return;
  _sqliteConfigured = true;
  if (!Platform.isLinux) return;

  open.overrideFor(OperatingSystem.linux, _openLinuxSqlite);
}

DynamicLibrary _openLinuxSqlite() {
  for (final candidate in const <String>[
    'libsqlite3.so',
    'libsqlite3.so.0',
    '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/usr/lib/aarch64-linux-gnu/libsqlite3.so.0',
  ]) {
    try {
      return DynamicLibrary.open(candidate);
      // ignore: avoid_catching_errors
    } on ArgumentError {
      continue;
    }
  }
  return DynamicLibrary.open('libsqlite3.so');
}
