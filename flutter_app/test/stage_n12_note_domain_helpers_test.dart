import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_management_app/application/notes/notes_state.dart';
import 'package:personal_management_app/domain/notes/note_helpers.dart';
import 'package:personal_management_app/domain/notes/note_models.dart';

Map<String, dynamic> _loadVectors() {
  final candidates = [
    File('../shared_foundation/fixtures/note_domain_helpers_vectors.json'),
    File('shared_foundation/fixtures/note_domain_helpers_vectors.json'),
  ];
  for (final file in candidates) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError(
    'Unable to locate shared_foundation/fixtures/note_domain_helpers_vectors.json from ${Directory.current.path}',
  );
}

NoteLifecycleState _parseExpectedLifecycle(String value) {
  switch (value) {
    case 'trashed':
      return NoteLifecycleState.trashed;
    case 'archived':
      return NoteLifecycleState.archived;
    default:
      return NoteLifecycleState.active;
  }
}

void main() {
  final vectors = _loadVectors();

  group('Stage N1.2 — Pure Notes Domain Helpers Parity', () {
    test(
        '1. Title validation and normalization enforce 250-char limit and fallbacks across shared vectors',
        () {
      expect(NoteDomainHelpers.defaultTitle, 'Untitled Note');
      expect(NoteDomainHelpers.maxTitleLength, 250);

      final titleCases =
          (vectors['titleCases'] as List).cast<Map<String, dynamic>>();
      for (final tc in titleCases) {
        final name = tc['name'] as String;
        final raw = tc['repeatChar'] != null
            ? (tc['repeatChar'] as String) * (tc['repeatCount'] as int)
            : tc['raw'] as String?;
        final fallback = tc['fallback'] as String;
        final expectedValid = tc['expectedValid'] as bool;

        expect(
          NoteDomainHelpers.isValidTitle(raw),
          expectedValid,
          reason: name,
        );

        final normalized =
            NoteDomainHelpers.normalizeTitle(raw, fallbackTitle: fallback);
        final validated =
            NoteDomainHelpers.validateTitle(raw, fallbackTitle: fallback);
        expect(validated.valid, expectedValid, reason: name);
        expect(validated.normalized, normalized, reason: name);

        if (tc['expectedNormalized'] != null) {
          expect(normalized, tc['expectedNormalized'], reason: name);
        }
        if (tc['expectedLength'] != null) {
          expect(normalized.length, tc['expectedLength'], reason: name);
        }
        if (!expectedValid) {
          expect(validated.error, isNotEmpty, reason: name);
        }
      }

      expect(NoteDomainHelpers.isValidTitle(null), isFalse);
      expect(NoteDomainHelpers.normalizeTitle(null), 'Untitled Note');
      expect(NoteEntity.clampTitle('   '), 'Untitled Note');
    });

    test(
        '2. Tag normalization trims whitespace, drops empty entries, and deduplicates case-insensitively preserving first casing',
        () {
      final tagCases =
          (vectors['tagCases'] as List).cast<Map<String, dynamic>>();
      for (final tc in tagCases) {
        final input = (tc['input'] as List).cast<String>();
        final expected = (tc['expected'] as List).cast<String>();
        expect(
          NoteDomainHelpers.normalizeTags(input),
          expected,
          reason: tc['name'] as String,
        );
      }
      expect(NoteDomainHelpers.normalizeTags(null), isEmpty);
    });

    test(
        '3. Folder/category normalization preserves existing custom values and platform-specific defaults',
        () {
      final folderCases =
          (vectors['folderCases'] as List).cast<Map<String, dynamic>>();
      for (final tc in folderCases) {
        expect(
          NoteDomainHelpers.normalizeFolder(
            tc['raw'] as String?,
            defaultFolder: tc['defaultFolder'] as String,
            lowercase: tc['lowercase'] as bool,
          ),
          tc['expected'],
          reason: tc['name'] as String,
        );
      }

      expect(
        NoteDomainHelpers.normalizeFlutterCategory('  Reflection '),
        'reflection',
      );
      expect(NoteDomainHelpers.normalizeFlutterCategory(' '), 'general');
      expect(NoteEntity.normalizeCategory('  Reflection '), 'reflection');
      expect(NoteDomainHelpers.normalizeWebNotebook('  Finances '), 'Finances');
      expect(NoteDomainHelpers.normalizeWebNotebook(''), 'Personal');
      expect(
        NoteDomainHelpers.normalizeExchangeFolder('  Custom Folder '),
        'Custom Folder',
      );
      expect(NoteDomainHelpers.normalizeExchangeFolder(null), 'General');
    });

    test(
        '4. Lifecycle predicates evaluate active, archived, trashed, pinned-active, and favorite-active consistently',
        () {
      final lifecycleCases =
          (vectors['lifecycleCases'] as List).cast<Map<String, dynamic>>();
      for (final tc in lifecycleCases) {
        final name = tc['name'] as String;
        final note = NoteEntity(
          id: 'life-$name',
          title: 'Lifecycle',
          content: '',
          isPinned: tc['isPinned'] as bool,
          isFavorite: tc['isFavorite'] as bool,
          isArchived: tc['isArchived'] as bool,
          isTrashed: tc['isTrashed'] as bool,
        );
        expect(
          NoteDomainHelpers.getLifecycleState(note),
          _parseExpectedLifecycle(tc['expectedState'] as String),
          reason: name,
        );
        expect(NoteDomainHelpers.isActive(note), tc['expectedActive'],
            reason: name);
        expect(NoteDomainHelpers.isArchived(note), tc['expectedArchived'],
            reason: name);
        expect(NoteDomainHelpers.isTrashed(note), tc['expectedTrashed'],
            reason: name);
        expect(
          NoteDomainHelpers.isPinnedActive(note),
          tc['expectedPinnedActive'],
          reason: name,
        );
        expect(
          NoteDomainHelpers.isFavoriteActive(note),
          tc['expectedFavoriteActive'],
          reason: name,
        );
      }
    });

    test(
        '5. Polymorphic link helpers validate supported modules and reject half-links or unsupported targets',
        () {
      final linkCases =
          (vectors['linkCases'] as List).cast<Map<String, dynamic>>();
      for (final tc in linkCases) {
        final name = tc['name'] as String;
        final rawModule = tc['rawModule'] as String?;
        final rawId = tc['rawId'] as String?;
        expect(
          NoteDomainHelpers.isSupportedLinkModule(rawModule),
          tc['expectedSupportedModule'],
          reason: name,
        );
        final pair = NoteDomainHelpers.normalizeLinkPair(rawModule, rawId);
        expect(pair.$1, tc['expectedModule'], reason: name);
        expect(pair.$2, tc['expectedId'], reason: name);
        expect(
          NoteEntity.normalizeLinkPair(rawModule, rawId),
          pair,
          reason: name,
        );
      }
    });

    test(
        '6. Deterministic sorting matches recent, alpha, oldest, and pinFirst expectations and delegates cleanly from NotesModuleState',
        () {
      final rawFixtureNotes =
          (vectors['sortFixtureNotes'] as List).cast<Map<String, dynamic>>();
      final fixtureNotes = rawFixtureNotes
          .map(
            (n) => NoteEntity(
              id: n['id'] as String,
              title: n['title'] as String,
              content: '',
              isPinned: n['isPinned'] as bool,
              createdAt: DateTime.parse(n['createdAt'] as String),
              updatedAt: DateTime.parse(n['updatedAt'] as String),
            ),
          )
          .toList(growable: false);
      final originalIds = fixtureNotes.map((n) => n.id).toList();
      final expectations = vectors['sortExpectations'] as Map<String, dynamic>;

      expect(
        NoteDomainHelpers.sortNotes(
          fixtureNotes,
          sortBy: NoteSortMode.recent,
          pinFirst: true,
        ).map((n) => n.id).toList(),
        expectations['recentPinFirst'],
      );
      expect(
        NoteDomainHelpers.sortNotes(
          fixtureNotes,
          sortBy: NoteSortMode.recent,
          pinFirst: false,
        ).map((n) => n.id).toList(),
        expectations['recentNoPin'],
      );
      expect(
        NoteDomainHelpers.sortNotes(
          fixtureNotes,
          sortBy: NoteSortMode.alpha,
          pinFirst: true,
        ).map((n) => n.id).toList(),
        expectations['alphaPinFirst'],
      );
      expect(
        NoteDomainHelpers.sortNotes(
          fixtureNotes,
          sortBy: NoteSortMode.oldest,
          pinFirst: true,
        ).map((n) => n.id).toList(),
        expectations['oldestPinFirst'],
      );
      expect(fixtureNotes.map((n) => n.id).toList(), originalIds);

      // Verify NotesModuleState filteredNotes delegates to the same sorting rules
      final state = NotesModuleState(
        notes: fixtureNotes,
        sortBy: 'alpha',
        sectionFilter: 'active',
      );
      expect(
        state.filteredNotes.map((n) => n.id).toList(),
        expectations['alphaPinFirst'],
      );
    });
  });
}
