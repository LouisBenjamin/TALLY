import 'dart:typed_data';

import 'package:tally/core/icons.dart';
import 'package:tally/core/supabase_client.dart';
import 'package:tally/core/widgets/page_body.dart';
import 'package:tally/features/groups/data/groups_repository.dart';
import 'package:tally/features/groups/providers/groups_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  bool _uploading = false;

  Future<void> _changePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() => _uploading = true);
    try {
      final Uint8List bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.')
          ? picked.name.split('.').last.toLowerCase()
          : 'jpg';
      await GroupsRepository().uploadGroupPhoto(
        groupId: widget.groupId,
        bytes: bytes,
        fileExt: ext,
      );
      ref.invalidate(groupProvider(widget.groupId));
      ref.invalidate(groupSummariesProvider);
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteGroup(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
            'Every expense, payment and member goes with it, for everyone. '
            "This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogCtx).colorScheme.error),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete group'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await GroupsRepository().deleteGroup(groupId: widget.groupId);
      ref.invalidate(groupSummariesProvider);
      if (mounted) context.go('/groups');
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupAsync = ref.watch(groupProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(title: const Text('Group settings')),
      body: PageBody(
        child: groupAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (group) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _uploading ? null : _changePhoto,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          width: 160,
                          height: 160,
                          child: group.photoUrl != null
                              ? Image.network(
                                  group.photoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _Placeholder(name: group.name),
                                )
                              : _Placeholder(name: group.name),
                        ),
                      ),
                      if (_uploading)
                        const CircularProgressIndicator()
                      else
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: theme.colorScheme.primary,
                            child: Icon(AppIcons.camera,
                                size: 18, color: theme.colorScheme.onPrimary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Tap the photo to change it',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 32),
              Text('Group name', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(group.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 20),
              Text('Invite code', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                group.joinCode,
                style: theme.textTheme.titleMedium
                    ?.copyWith(letterSpacing: 2, fontWeight: FontWeight.bold),
              ),
              if (group.createdBy == supabase.auth.currentUser?.id) ...[
                const SizedBox(height: 40),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error),
                  onPressed: () => _deleteGroup(group.name),
                  icon: const Icon(AppIcons.delete),
                  label: const Text('Delete group'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.primaryContainer,
      child: Center(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
          style: theme.textTheme.displayMedium?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
