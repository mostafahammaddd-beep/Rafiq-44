import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'user_profile.dart';

/// Stores the user profile as a small JSON file in the app's private storage.
class ProfileRepository {
  Future<File> _file() async {
    final Directory dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'profile.json'));
  }

  Future<UserProfile?> load() async {
    try {
      final File file = await _file();
      if (!await file.exists()) {
        return null;
      }
      return UserProfile.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(UserProfile profile) async {
    final File file = await _file();
    await file.writeAsString(jsonEncode(profile.toJson()), flush: true);
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository();
});

/// Null means onboarding has not been completed yet.
final profileProvider = FutureProvider<UserProfile?>((ref) {
  return ref.read(profileRepositoryProvider).load();
});
