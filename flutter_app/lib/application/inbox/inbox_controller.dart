import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/inbox/inbox_models.dart';
import '../../domain/inbox/inbox_contracts.dart';
import 'inbox_state.dart';

/// Application coordinator for Daywell 1-tap Quick Capture and Inbox triage.
///
/// Independent cross-cutting ingress point for ideas, tasks, and notes.
/// Decoupled from AppStateManager, TasksController, NotesController, and Drift.
/// Cross-module capture triage is dispatched via an injected [onTriageCapture]
/// callback configured at the application composition boundary.
class InboxController extends ChangeNotifier {
  final IInboxRepository _repository;
  final void Function(InboxItemEntity item)? onTriageCapture;
  InboxModuleState _state;
  StreamSubscription<List<InboxItemEntity>>? _unprocessedSubscription;
  Future<void>? _disposeFuture;
  bool _isDisposed = false;

  InboxController({
    required IInboxRepository repository,
    this.onTriageCapture,
    InboxModuleState? initialState,
    List<InboxItemEntity>? initialItems,
  })  : _repository = repository,
        _state =
            initialState ?? InboxModuleState(items: initialItems ?? const []);

  InboxModuleState get state => _state;
  List<InboxItemEntity> get items => _state.items;
  List<InboxItemEntity> get unprocessedItems => _state.unprocessedItems;
  int get unprocessedCount => _state.unprocessedCount;
  bool get isLoading => _state.isLoading;
  String? get errorMessage => _state.errorMessage;

  // --- Presentation / Filter Controls ---

  void setCategoryFilter(String category) {
    _state = _state.copyWith(categoryFilter: category);
    notifyListeners();
  }

  void setShowProcessed(bool show) {
    _state = _state.copyWith(showProcessed: show);
    notifyListeners();
  }

  // --- Loading, Stream Subscription & Lifecycle ---

  Future<void> loadItems({bool includeProcessed = false}) async {
    if (_isDisposed) return;
    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    try {
      final loaded = await _repository.getAllInboxItems(
        includeProcessed: includeProcessed,
      );
      if (_isDisposed) return;
      _state = _state.copyWith(
        items: loaded,
        isLoading: false,
        clearError: true,
      );
    } catch (e) {
      if (_isDisposed) return;
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
    notifyListeners();
  }

  void startWatchingUnprocessed() {
    if (_isDisposed) return;
    unawaited(_unprocessedSubscription?.cancel());
    _unprocessedSubscription = _repository.watchUnprocessedItems().listen(
      (unprocessed) {
        if (_isDisposed) return;
        final unprocessedIds = unprocessed.map((i) => i.id).toSet();
        final processed = _state.items
            .where((i) => i.isProcessed && !unprocessedIds.contains(i.id))
            .toList();
        _state = _state.copyWith(
          items: [...unprocessed, ...processed],
          clearError: true,
        );
        notifyListeners();
      },
      onError: (Object error) {
        if (_isDisposed) return;
        _state = _state.copyWith(errorMessage: error.toString());
        notifyListeners();
      },
    );
  }

  /// Replaces the controller's in-memory list during single-shot seed,
  /// backup restore, or seed purge initialization.
  void replaceItems(List<InboxItemEntity> items) {
    _state = _state.copyWith(
      items: List<InboxItemEntity>.unmodifiable(items),
      clearError: true,
    );
    notifyListeners();
  }

  // --- Capture & Triage Workflows ---

  Future<InboxItemEntity?> captureQuickThought(
    String rawText, {
    String category = 'general',
    bool autoTriage = true,
  }) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return null;

    try {
      final captured = await _repository.captureQuickThought(
        trimmed,
        category: category,
      );
      final existingWithoutCaptured =
          _state.items.where((i) => i.id != captured.id);
      _state = _state.copyWith(
        items: [captured, ...existingWithoutCaptured],
        clearError: true,
      );
      notifyListeners();

      if (autoTriage) {
        onTriageCapture?.call(captured);
      }
      return captured;
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
      notifyListeners();
      return null;
    }
  }

  Future<void> markProcessed(String id) async {
    final targetIndex = _state.items.indexWhere((i) => i.id == id);
    final targetItem = targetIndex == -1 ? null : _state.items[targetIndex];
    try {
      await _repository.markProcessed(id);
      final baseItems =
          targetItem != null && !_state.items.any((i) => i.id == id)
              ? [..._state.items, targetItem]
              : _state.items;
      final updated = baseItems
          .map((i) => i.id == id ? i.copyWith(isProcessed: true) : i)
          .toList();
      _state = _state.copyWith(items: updated, clearError: true);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> deleteItem(String id) async {
    try {
      await _repository.deleteItem(id);
      final remaining = _state.items.where((i) => i.id != id).toList();
      _state = _state.copyWith(items: remaining, clearError: true);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  Future<void> updateItemText(
    String id,
    String newText, {
    String? category,
  }) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;

    try {
      await _repository.updateItemText(id, trimmed, category: category);
      final updated = _state.items.map((i) {
        if (i.id == id) {
          return i.copyWith(
            rawText: trimmed,
            category: category ?? i.category,
          );
        }
        return i;
      }).toList();
      _state = _state.copyWith(items: updated, clearError: true);
    } catch (e) {
      _state = _state.copyWith(errorMessage: e.toString());
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    final sub = _unprocessedSubscription;
    _unprocessedSubscription = null;
    if (sub != null) {
      _disposeFuture ??= sub.cancel();
      unawaited(_disposeFuture!);
    }
    super.dispose();
  }

  /// Cancels any active stream subscription cleanly before closing the database.
  /// Safe and idempotent alongside synchronous [dispose].
  Future<void> disposeAsync() async {
    dispose();
    await _disposeFuture;
  }
}
