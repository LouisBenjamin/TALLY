import 'package:tally/core/supabase_client.dart';
import 'package:tally/models/activity_entry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// The latest 100 activity entries for a group, newest first.
final activityProvider = FutureProvider.family<List<ActivityEntry>, String>(
  (ref, groupId) async {
    final data = await supabase
        .from('activity')
        .select()
        .eq('group_id', groupId)
        .order('created_at', ascending: false)
        .limit(100);
    return (data as List)
        .map((e) => ActivityEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  },
);
