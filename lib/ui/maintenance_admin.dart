// Building manager: edit or delete any maintenance request, whoever sent it.
//
// A waiting or declined request is edited in the request form. An approved
// one has become an expense, so it is edited in the expense form; deleting
// it removes the expense with its invoice, share payments and photos.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/attachments.dart';
import '../data/community.dart';
import '../data/maintenance_invoice.dart';
import '../data/models.dart';
import '../data/providers.dart';
import '../data/share_payments.dart';
import '../l10n/strings.dart';
import 'common.dart';
import 'expenses_screen.dart' show ExpenseForm;
import 'resident_screens.dart' show MaintenanceRequestScreen;

/// Opens the right form for the manager to edit [p].
void managerEditRequest(BuildContext context, WidgetRef ref, ExpenseProposal p) {
  if (p.status == RequestStatus.approved && p.expenseId.isNotEmpty) {
    final expenses = ref.read(expensesProvider).value ?? const <Expense>[];
    for (final e in expenses) {
      if (e.id == p.expenseId) {
        pushForm(context, ExpenseForm(existing: e));
        return;
      }
    }
  }
  pushForm(context, MaintenanceRequestScreen(existing: p, byManager: true));
}

/// Manager deletes [p] (any status). Returns true when deleted.
Future<bool> managerDeleteRequest(BuildContext context, WidgetRef ref, ExpenseProposal p) async {
  final t = context.t;
  final approved = p.status == RequestStatus.approved && p.expenseId.isNotEmpty;
  if (!await confirmDialog(context, approved ? t.deleteApprovedRequestConfirm : t.deleteRequestConfirm,
      confirmLabel: t.delete)) {
    return false;
  }
  final attachments = ref.read(attachmentServiceProvider);
  final service = ref.read(proposalServiceProvider);
  try {
    final photos = <String>{...p.attachmentIds};
    if (approved) {
      final expenses = ref.read(expensesProvider).value ?? const <Expense>[];
      Expense? expense;
      for (final e in expenses) {
        if (e.id == p.expenseId) expense = e;
      }
      if (expense != null) photos.addAll(expense.attachmentIds);
      await deleteExpenseLinks(ref, p.expenseId, keepRequests: true);
    }
    await service.withdraw(p.id);
    _deletePhotos(attachments, p.managerUid, photos);
    if (context.mounted) toast(context, t.requestDeleted);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '${t.somethingWrong}: $e');
    return false;
  }
}

/// Deletes an expense and what hangs off it: its maintenance invoice, share
/// payments (with their photos) and, unless [keepRequests], the resident
/// requests that were approved into it.
Future<void> deleteExpenseLinks(WidgetRef ref, String expenseId, {bool keepRequests = false}) async {
  final uid = ref.read(uidProvider);
  if (uid == null) return;
  // Everything is read up front: the caller's screen may close meanwhile.
  final db = ref.read(firestoreProvider);
  final attachments = ref.read(attachmentServiceProvider);
  final service = ref.read(proposalServiceProvider);
  ref.read(expenseRepo).delete(expenseId);
  ref.read(invoiceRepo).delete(maintenanceInvoiceId(expenseId)); // no-op if none
  try {
    final shares = await sharePaymentsOf(db, uid).where('expenseId', isEqualTo: expenseId).get();
    final photos = <String>{};
    for (final d in shares.docs) {
      photos.addAll(SharePayment.fromMap(d.id, d.data()).attachmentIds);
      await d.reference.delete();
    }
    _deletePhotos(attachments, uid, photos);
  } catch (e) {
    debugPrint('Share payment cleanup skipped: $e');
  }
  if (keepRequests) return;
  try {
    for (final p in await service.forExpense(uid, expenseId)) {
      await service.withdraw(p.id);
      _deletePhotos(attachments, uid, p.attachmentIds);
    }
  } catch (e) {
    debugPrint('Request cleanup skipped: $e');
  }
}

void _deletePhotos(AttachmentService attachments, String managerUid, Iterable<String> ids) {
  for (final id in ids) {
    attachments.delete(managerUid, id).catchError((Object e) => debugPrint('$e'));
  }
}
