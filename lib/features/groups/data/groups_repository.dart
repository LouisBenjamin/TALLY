import 'dart:typed_data';

import 'package:tally/core/supabase_client.dart';
import 'package:tally/models/group.dart';
import 'package:tally/models/group_member.dart';
import 'package:tally/models/group_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

class GroupsRepository {
  Future<List<Group>> fetchGroups() async {
    final data = await supabase
        .from('groups')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((e) => Group.fromJson(e as Map<String, dynamic>)).toList();
  }

  // Groups the caller belongs to, each with their own net balance attached —
  // used by the groups list so cards can show a "you owe / you're owed"
  // status line without fetching balances per group.
  Future<List<GroupSummary>> fetchGroupSummaries() async {
    final data = await supabase.from('my_group_summaries').select();
    return (data as List)
        .map((e) => GroupSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Uploads [bytes] as the group's photo and returns the new public URL.
  // Any member may set the group photo (storage RLS + update_group_photo
  // both check membership, not ownership).
  Future<String> uploadGroupPhoto({
    required String groupId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final path = '$groupId/photo.$fileExt';
    await supabase.storage.from('group-photos').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    // Cache-bust: same path every time, so the URL alone won't change after
    // a re-upload and a cached image would stick around.
    final baseUrl = supabase.storage.from('group-photos').getPublicUrl(path);
    final url = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    await supabase.rpc('update_group_photo', params: {
      'p_group_id': groupId,
      'p_photo_url': url,
    });
    return url;
  }

  Future<Group> fetchGroup({required String id}) async {
    final data = await supabase
        .from('groups')
        .select()
        .eq('id', id)
        .single();
    return Group.fromJson(data);
  }

  // Join the group matching [code] (adds the current user as a member).
  // Returns the joined group. Throws if the code is invalid.
  Future<Group> joinGroupByCode({required String code}) async {
    final data = await supabase.rpc(
      'join_group_by_code',
      params: {'p_code': code.trim()},
    );
    return Group.fromJson(data as Map<String, dynamic>);
  }

  // Add an account-less guest participant to a group the caller belongs to.
  Future<GroupMember> addGuest({
    required String groupId,
    required String name,
  }) async {
    final data = await supabase.rpc(
      'add_guest_member',
      params: {'p_group_id': groupId, 'p_name': name},
    );
    return GroupMember.fromJson(data as Map<String, dynamic>);
  }

  // Remove a member, or leave the group (pass your own member id). The
  // remove_member RPC refuses unless their balance is zero.
  Future<void> removeMember({required String memberId}) async {
    await supabase.rpc('remove_member', params: {'p_member_id': memberId});
  }

  // Owner only; deletes every expense, payment and member with it.
  Future<void> deleteGroup({required String groupId}) async {
    await supabase.rpc('delete_group', params: {'p_group_id': groupId});
  }

  Future<Group> createGroup({required String name}) async {
    final userId = supabase.auth.currentUser!.id;

    final groupData = await supabase
        .from('groups')
        .insert({'name': name, 'created_by': userId})
        .select()
        .single();

    final group = Group.fromJson(groupData);

    // Add the creator as the first member (RLS allows this for group owners).
    await supabase.from('group_members').insert({
      'group_id': group.id,
      'user_id': userId,
      'role': 'owner',
    });

    return group;
  }

  Future<List<GroupMember>> fetchMembers({required String groupId}) async {
    final data = await supabase
        .from('group_members')
        .select('*, profiles(display_name)')
        .eq('group_id', groupId)
        .isFilter('removed_at', null)
        .order('joined_at');
    return (data as List)
        .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<GroupMember?> fetchCurrentUserMember({required String groupId}) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final data = await supabase
        .from('group_members')
        .select('*, profiles(display_name)')
        .eq('group_id', groupId)
        .eq('user_id', userId)
        .maybeSingle();

    return data == null ? null : GroupMember.fromJson(data);
  }
}
