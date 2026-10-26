import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/attachments.dart';
import '../l10n/strings.dart';
import 'common.dart';

/// Photos being attached in a form. Photos added here are saved right away;
/// [discard] deletes them again if the form is cancelled, and photos removed
/// from an existing record are only deleted on [commit].
class AttachmentController extends ChangeNotifier {
  AttachmentController({
    required this.managerUid,
    required this.propertyId,
    this.unitId = '',
    required this.scope,
    required this.uploaderUid,
    List<String> initial = const [],
  }) : ids = [...initial];

  final String managerUid;
  String propertyId;
  String unitId;
  final AttachmentScope scope;
  final String uploaderUid;

  final List<String> ids;
  final Set<String> _added = {};
  final Set<String> _removed = {};
  bool busy = false;
  bool _done = false;

  bool get isFull => ids.length >= kMaxAttachmentsPerItem;

  void _add(AttachmentService s, Uint8List jpeg) {
    final id = s.add(
      managerUid: managerUid,
      propertyId: propertyId,
      unitId: unitId,
      scope: scope,
      uploaderUid: uploaderUid,
      jpeg: jpeg,
    );
    ids.add(id);
    _added.add(id);
    notifyListeners();
  }

  void remove(AttachmentService s, String id) {
    ids.remove(id);
    if (_added.remove(id)) {
      s.delete(managerUid, id).catchError((Object e) => debugPrint('Attachment delete failed: $e'));
    } else {
      _removed.add(id);
    }
    notifyListeners();
  }

  void _setBusy(bool v) {
    busy = v;
    notifyListeners();
  }

  /// Call when the record is saved. Returns the ids to store on it.
  /// [retag] (manager only) moves the photos to the record's current
  /// building / flat, in case it was changed after a photo was added.
  List<String> commit(AttachmentService s, {bool retag = false}) {
    _done = true;
    for (final id in _removed) {
      s.delete(managerUid, id).catchError((Object e) => debugPrint('Attachment delete failed: $e'));
    }
    if (retag) {
      for (final id in ids) {
        attachmentsOf(s.db, managerUid)
            .doc(id)
            .update({'propertyId': propertyId, 'unitId': unitId})
            .catchError((Object e) => debugPrint('Attachment retag failed: $e'));
      }
    }
    return List.unmodifiable(ids);
  }

  /// Call when the form is closed without saving.
  void discard(AttachmentService s) {
    if (_done) return;
    _done = true;
    for (final id in _added) {
      s.delete(managerUid, id).catchError((Object e) => debugPrint('Attachment delete failed: $e'));
    }
  }
}

/// "Add photo" button with thumbnails of the attached photos.
class AttachmentPicker extends ConsumerWidget {
  const AttachmentPicker({super.key, required this.controller, this.label});
  final AttachmentController controller;
  final String? label;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final t = context.t;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(t.takePhoto),
            onTap: () => Navigator.pop(c, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(t.chooseFromGallery),
            onTap: () => Navigator.pop(c, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return;
    final service = ref.read(attachmentServiceProvider);
    controller._setBusy(true);
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 75);
      if (file == null) return;
      final raw = await file.readAsBytes();
      // Shrinking can take a moment on big photos: do it off the UI thread.
      final jpeg = await compute(compressForUpload, raw);
      if (jpeg == null) {
        if (context.mounted) toast(context, t.photoUnreadable);
        return;
      }
      controller._add(service, jpeg);
    } catch (e) {
      if (context.mounted) toast(context, '${t.somethingWrong}: $e');
    } finally {
      controller._setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label ?? t.photos, style: Theme.of(context).textTheme.labelLarge),
        gap8,
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, id) in controller.ids.indexed)
            Stack(clipBehavior: Clip.none, children: [
              AttachmentThumb(
                managerUid: controller.managerUid,
                id: id,
                size: 76,
                onTap: () => openAttachmentViewer(context, controller.managerUid, controller.ids, i),
              ),
              PositionedDirectional(
                top: -8,
                end: -8,
                child: Material(
                  color: cs.errorContainer,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => controller.remove(ref.read(attachmentServiceProvider), id),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 14, color: cs.onErrorContainer),
                    ),
                  ),
                ),
              ),
            ]),
          if (!controller.isFull)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: controller.busy ? null : () => _pick(context, ref),
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                  color: cs.surfaceContainerLow,
                ),
                child: controller.busy
                    ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_a_photo_outlined, color: cs.primary),
                        const SizedBox(height: 4),
                        Text(t.addPhoto, style: TextStyle(fontSize: 11, color: cs.primary)),
                      ]),
              ),
            ),
        ]),
      ]),
    );
  }
}

/// One photo thumbnail (loads on demand).
class AttachmentThumb extends ConsumerWidget {
  const AttachmentThumb({super.key, required this.managerUid, required this.id, this.size = 56, this.onTap});
  final String managerUid;
  final String id;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final bytes = ref.watch(attachmentBytesProvider((managerUid: managerUid, id: id)));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: size,
          height: size,
          color: cs.surfaceContainerHigh,
          child: bytes.when(
            data: (b) => b == null
                ? Icon(Icons.broken_image_outlined, color: cs.outline)
                : Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: (size * 3).round()),
            loading: () => const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            error: (_, _) => Icon(Icons.lock_outline, color: cs.outline),
          ),
        ),
      ),
    );
  }
}

/// Read-only row of thumbnails; tapping one opens the viewer.
class AttachmentStrip extends StatelessWidget {
  const AttachmentStrip({super.key, required this.managerUid, required this.ids, this.size = 56});
  final String managerUid;
  final List<String> ids;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (i, id) in ids.indexed)
        AttachmentThumb(
          managerUid: managerUid,
          id: id,
          size: size,
          onTap: () => openAttachmentViewer(context, managerUid, ids, i),
        ),
    ]);
  }
}

/// Small paperclip + count, for list rows.
class AttachmentBadge extends StatelessWidget {
  const AttachmentBadge({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.attach_file, size: 14, color: cs.primary),
      Text('$count', style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600)),
    ]);
  }
}

void openAttachmentViewer(BuildContext context, String managerUid, List<String> ids, [int initial = 0]) {
  if (ids.isEmpty) return;
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _AttachmentViewer(managerUid: managerUid, ids: List.of(ids), initial: initial),
  ));
}

class _AttachmentViewer extends ConsumerStatefulWidget {
  const _AttachmentViewer({required this.managerUid, required this.ids, required this.initial});
  final String managerUid;
  final List<String> ids;
  final int initial;

  @override
  ConsumerState<_AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends ConsumerState<_AttachmentViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${widget.ids.length}'),
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.ids.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final bytes = ref.watch(attachmentBytesProvider((managerUid: widget.managerUid, id: widget.ids[i])));
          return bytes.when(
            data: (b) => b == null
                ? const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64))
                : InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(b, fit: BoxFit.contain))),
            loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('${context.t.somethingWrong}: $e',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              ),
            ),
          );
        },
      ),
    );
  }
}
