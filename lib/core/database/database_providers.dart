import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'rafiq_database.dart';

final databaseProvider = FutureProvider<RafiqDatabase>((ref) async {
  final RafiqDatabase db = RafiqDatabase();
  await db.open();
  ref.onDispose(() {
    db.close();
  });
  return db;
});

final surahOverviewsProvider = FutureProvider.autoDispose<List<SurahOverview>>((ref) async {
  final RafiqDatabase db = await ref.watch(databaseProvider.future);
  return db.getSurahOverviews();
});

final statsProvider = FutureProvider.autoDispose<StatsSnapshot>((ref) async {
  final RafiqDatabase db = await ref.watch(databaseProvider.future);
  return db.getStats();
});

final surahAyahsProvider = FutureProvider.autoDispose.family<List<Ayah>, int>((ref, int surahId) async {
  final RafiqDatabase db = await ref.watch(databaseProvider.future);
  return db.getAyahsWithWords(surahId);
});

final surahMasteryProvider = FutureProvider.autoDispose.family<Map<int, int>, int>((ref, int surahId) async {
  final RafiqDatabase db = await ref.watch(databaseProvider.future);
  return db.getMasteryByAyah(surahId);
});
