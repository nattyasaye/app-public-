import 'package:flutter/material.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/notes/note_links.dart';
import '../../../domain/notes/note_markdown.dart';
import '../../../domain/notes/note_models.dart';

/// Safe, selectable, theme-aligned lightweight Markdown preview widget for Notes.
///
/// Consumes [NoteMarkdownParser.parse] without mutating the underlying Markdown
/// source string and without trusting or executing embedded HTML or unsafe links.
/// Dynamically resolves `[[Note Title]]` internal links against active notes.
class NoteMarkdownPreview extends StatelessWidget {
  final String content;
  final String emptyMessage;
  final EdgeInsetsGeometry padding;
  final ValueChanged<int>? onToggleChecklistItem;
  final List<NoteEntity>? notes;
  final ValueChanged<NoteEntity>? onOpenInternalNote;
  final void Function(String targetTitle, List<NoteEntity> matches)?
      onOpenAmbiguousInternalLink;

  const NoteMarkdownPreview({
    super.key,
    required this.content,
    this.emptyMessage =
        'Nothing to preview yet. Switch to Write to add note content.',
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.onToggleChecklistItem,
    this.notes,
    this.onOpenInternalNote,
    this.onOpenAmbiguousInternalLink,
  });

  @override
  Widget build(BuildContext context) {
    final doc = NoteMarkdownParser.parse(content);
    final semantic = context.daywellColors;
    final colorScheme = Theme.of(context).colorScheme;

    if (doc.blocks.isEmpty) {
      return Padding(
        padding: padding,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingMd,
            vertical: SharedDesignTokens.spacingLg,
          ),
          decoration: BoxDecoration(
            color: semantic.surfaceSubtle,
            borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
            border: Border.all(color: semantic.border),
          ),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: DaywellTypography.fromToken(
              SharedDesignTokens.typeBodyCompact,
              color: semantic.textMuted,
            ),
          ),
        ),
      );
    }

    final baseBodyStyle = DaywellTypography.fromToken(
      SharedDesignTokens.typeBody,
      color: semantic.textPrimary,
    ).copyWith(height: 1.5);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 320.0;
        final maxInlineChipWidth =
            (availableWidth - 40).clamp(120.0, availableWidth).toDouble();

        return SelectionArea(
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < doc.blocks.length; i++) ...[
                  if (i > 0)
                    SizedBox(
                      height: doc.blocks[i].type ==
                                  NoteMarkdownBlockType.heading &&
                              doc.blocks[i].level <= 2
                          ? SharedDesignTokens.spacingMd
                          : SharedDesignTokens.spacingCompact,
                    ),
                  _buildBlock(
                    context: context,
                    block: doc.blocks[i],
                    baseBodyStyle: baseBodyStyle,
                    semantic: semantic,
                    colorScheme: colorScheme,
                    maxInlineChipWidth: maxInlineChipWidth,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBlock({
    required BuildContext context,
    required NoteMarkdownBlock block,
    required TextStyle baseBodyStyle,
    required DaywellSemanticColors semantic,
    required ColorScheme colorScheme,
    required double maxInlineChipWidth,
  }) {
    switch (block.type) {
      case NoteMarkdownBlockType.heading:
        final token = switch (block.level) {
          1 => SharedDesignTokens.typeDisplay,
          2 => SharedDesignTokens.typeHeading,
          _ => SharedDesignTokens.typeTitle,
        };
        final headingStyle = DaywellTypography.fromToken(
          token,
          color: semantic.textPrimary,
        );
        return Text.rich(
          TextSpan(
            children: _buildInlineSpans(
              block.inlines,
              baseStyle: headingStyle,
              semantic: semantic,
              colorScheme: colorScheme,
              maxInlineChipWidth: maxInlineChipWidth,
            ),
          ),
        );

      case NoteMarkdownBlockType.paragraph:
        return Text.rich(
          TextSpan(
            children: _buildInlineSpans(
              block.inlines,
              baseStyle: baseBodyStyle,
              semantic: semantic,
              colorScheme: colorScheme,
              maxInlineChipWidth: maxInlineChipWidth,
            ),
          ),
        );

      case NoteMarkdownBlockType.bulletList:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var idx = 0; idx < block.listItems.length; idx++) ...[
              if (idx > 0)
                const SizedBox(height: SharedDesignTokens.spacingXs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '•',
                      style: baseBodyStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: _buildInlineSpans(
                          block.listItems[idx],
                          baseStyle: baseBodyStyle,
                          semantic: semantic,
                          colorScheme: colorScheme,
                          maxInlineChipWidth: maxInlineChipWidth,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );

      case NoteMarkdownBlockType.orderedList:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var idx = 0; idx < block.orderedItems.length; idx++) ...[
              if (idx > 0)
                const SizedBox(height: SharedDesignTokens.spacingXs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 20),
                      child: Text(
                        '${block.orderedItems[idx].number}.',
                        textAlign: TextAlign.right,
                        style: baseBodyStyle.copyWith(
                          fontWeight: FontWeight.w600,
                          color: semantic.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: _buildInlineSpans(
                          block.orderedItems[idx].inlines,
                          baseStyle: baseBodyStyle,
                          semantic: semantic,
                          colorScheme: colorScheme,
                          maxInlineChipWidth: maxInlineChipWidth,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );

      case NoteMarkdownBlockType.checklist:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var idx = 0; idx < block.checklistItems.length; idx++) ...[
              if (idx > 0)
                const SizedBox(height: SharedDesignTokens.spacingXs),
              _buildChecklistRow(
                item: block.checklistItems[idx],
                baseBodyStyle: baseBodyStyle,
                semantic: semantic,
                colorScheme: colorScheme,
                maxInlineChipWidth: maxInlineChipWidth,
              ),
            ],
          ],
        );

      case NoteMarkdownBlockType.blockquote:
        final quoteStyle = baseBodyStyle.copyWith(
          color: semantic.textSecondary,
          fontStyle: FontStyle.italic,
        );
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: SharedDesignTokens.spacingCompact,
            vertical: SharedDesignTokens.spacingSm,
          ),
          decoration: BoxDecoration(
            color: semantic.surfaceSubtle,
            border: Border(
              left: BorderSide(color: colorScheme.primary, width: 3),
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(SharedDesignTokens.radiusSm),
              bottomRight: Radius.circular(SharedDesignTokens.radiusSm),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var idx = 0; idx < block.quoteLines.length; idx++) ...[
                if (idx > 0)
                  const SizedBox(height: SharedDesignTokens.spacingXs),
                Text.rich(
                  TextSpan(
                    children: _buildInlineSpans(
                      block.quoteLines[idx],
                      baseStyle: quoteStyle,
                      semantic: semantic,
                      colorScheme: colorScheme,
                      maxInlineChipWidth: maxInlineChipWidth,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );

      case NoteMarkdownBlockType.codeBlock:
        final monoStyle = DaywellTypography.mono(
          color: semantic.textPrimary,
        ).copyWith(height: 1.45);
        return Container(
          decoration: BoxDecoration(
            color: semantic.surfaceSubtle,
            borderRadius: BorderRadius.circular(SharedDesignTokens.radiusMd),
            border: Border.all(color: semantic.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (block.language.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SharedDesignTokens.spacingCompact,
                    vertical: SharedDesignTokens.spacingXs,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: semantic.divider),
                    ),
                  ),
                  child: Text(
                    block.language.toUpperCase(),
                    style: DaywellTypography.caption(color: semantic.textMuted),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(SharedDesignTokens.spacingCompact),
                child: Text(
                  block.code,
                  style: monoStyle,
                ),
              ),
            ],
          ),
        );

      case NoteMarkdownBlockType.horizontalRule:
        return Divider(
          height: SharedDesignTokens.spacingMd,
          thickness: 1,
          color: semantic.divider,
        );
    }
  }

  Widget _buildChecklistRow({
    required NoteMarkdownChecklistItem item,
    required TextStyle baseBodyStyle,
    required DaywellSemanticColors semantic,
    required ColorScheme colorScheme,
    required double maxInlineChipWidth,
  }) {
    final itemStyle = item.checked
        ? baseBodyStyle.copyWith(
            color: semantic.textMuted,
            decoration: TextDecoration.lineThrough,
          )
        : baseBodyStyle;
    final canToggle = onToggleChecklistItem != null && item.lineIndex >= 0;
    final plainText = NoteMarkdownParser.inlinesToPlainText(item.inlines).trim();
    final actionLabel = item.checked
        ? (plainText.isNotEmpty
            ? 'Mark item incomplete: $plainText'
            : 'Mark item incomplete')
        : (plainText.isNotEmpty
            ? 'Mark item complete: $plainText'
            : 'Mark item complete');

    final leadingControl = canToggle
        ? Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Semantics(
              button: true,
              checked: item.checked,
              label: actionLabel,
              child: IconButton(
                onPressed: () => onToggleChecklistItem!(item.lineIndex),
                tooltip:
                    item.checked ? 'Mark item incomplete' : 'Mark item complete',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.padded,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                iconSize: 20,
                color: item.checked ? colorScheme.primary : semantic.textMuted,
                icon: Icon(
                  item.checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                ),
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(
              item.checked
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 18,
              color: item.checked ? colorScheme.primary : semantic.textMuted,
              semanticLabel:
                  item.checked ? 'Completed checklist item' : 'Open checklist item',
            ),
          );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leadingControl,
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: canToggle ? 3 : 0),
            child: Text.rich(
              TextSpan(
                children: _buildInlineSpans(
                  item.inlines,
                  baseStyle: itemStyle,
                  semantic: semantic,
                  colorScheme: colorScheme,
                  maxInlineChipWidth: maxInlineChipWidth,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  InlineSpan _buildInternalLinkSpan({
    required String targetTitle,
    required TextStyle baseStyle,
    required DaywellSemanticColors semantic,
    required ColorScheme colorScheme,
    required double maxInlineChipWidth,
  }) {
    final resolution = NoteLinksDomain.resolveInternalLink(
      targetTitle,
      notes ?? const <NoteEntity>[],
    );

    if (resolution.status == NoteInternalLinkResolutionStatus.resolved &&
        resolution.note != null) {
      final targetNote = resolution.note!;
      final chip = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxInlineChipWidth),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
            onTap: onOpenInternalNote != null
                ? () => onOpenInternalNote!(targetNote)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 13,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      targetTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: baseStyle.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: onOpenInternalNote != null
              ? Semantics(
                  button: true,
                  label: 'Open note: ${targetNote.displayTitle}',
                  child: Tooltip(
                    message: 'Open "${targetNote.displayTitle}"',
                    child: chip,
                  ),
                )
              : chip,
        ),
      );
    }

    if (resolution.status == NoteInternalLinkResolutionStatus.ambiguous) {
      final count = resolution.matches.length;
      final chip = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxInlineChipWidth),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
            onTap: onOpenAmbiguousInternalLink != null
                ? () =>
                    onOpenAmbiguousInternalLink!(targetTitle, resolution.matches)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: semantic.warningContainer,
                borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
                border: Border.all(
                  color: semantic.warning.withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 13,
                    color: semantic.onWarningContainer,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '$targetTitle ($count)',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: baseStyle.copyWith(
                        color: semantic.onWarningContainer,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                        decorationColor: semantic.onWarningContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: onOpenAmbiguousInternalLink != null
              ? Semantics(
                  button: true,
                  label:
                      'Multiple notes match "$targetTitle" ($count matches). Choose a note.',
                  child: Tooltip(
                    message:
                        'Multiple notes match "$targetTitle". Tap to choose.',
                    child: chip,
                  ),
                )
              : chip,
        ),
      );
    }

    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Tooltip(
          message: 'Note not found: $targetTitle',
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxInlineChipWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: semantic.surfaceSubtle,
                borderRadius: BorderRadius.circular(SharedDesignTokens.radiusSm),
                border: Border.all(color: semantic.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.link_off_rounded,
                    size: 13,
                    color: semantic.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      targetTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: baseStyle.copyWith(
                        color: semantic.textMuted,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dashed,
                        decorationColor: semantic.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _buildInlineSpans(
    List<NoteMarkdownInline> nodes, {
    required TextStyle baseStyle,
    required DaywellSemanticColors semantic,
    required ColorScheme colorScheme,
    required double maxInlineChipWidth,
  }) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      switch (node.type) {
        case NoteMarkdownInlineType.text:
          spans.add(TextSpan(text: node.text, style: baseStyle));
          break;
        case NoteMarkdownInlineType.bold:
          final boldStyle = baseStyle.copyWith(fontWeight: FontWeight.w700);
          spans.add(
            TextSpan(
              children: _buildInlineSpans(
                node.children,
                baseStyle: boldStyle,
                semantic: semantic,
                colorScheme: colorScheme,
                maxInlineChipWidth: maxInlineChipWidth,
              ),
            ),
          );
          break;
        case NoteMarkdownInlineType.italic:
          final italicStyle = baseStyle.copyWith(fontStyle: FontStyle.italic);
          spans.add(
            TextSpan(
              children: _buildInlineSpans(
                node.children,
                baseStyle: italicStyle,
                semantic: semantic,
                colorScheme: colorScheme,
                maxInlineChipWidth: maxInlineChipWidth,
              ),
            ),
          );
          break;
        case NoteMarkdownInlineType.strikethrough:
          final strikeStyle = baseStyle.copyWith(
            color: semantic.textMuted,
            decoration: TextDecoration.lineThrough,
          );
          spans.add(
            TextSpan(
              children: _buildInlineSpans(
                node.children,
                baseStyle: strikeStyle,
                semantic: semantic,
                colorScheme: colorScheme,
                maxInlineChipWidth: maxInlineChipWidth,
              ),
            ),
          );
          break;
        case NoteMarkdownInlineType.code:
          final codeStyle = DaywellTypography.mono(
            color: colorScheme.primary,
          ).copyWith(
            fontSize: baseStyle.fontSize != null
                ? (baseStyle.fontSize! * 0.9)
                : null,
            backgroundColor: semantic.surfaceSubtle,
          );
          spans.add(TextSpan(text: node.text, style: codeStyle));
          break;
        case NoteMarkdownInlineType.link:
          final linkStyle = baseStyle.copyWith(
            color: colorScheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: colorScheme.primary,
          );
          spans.add(TextSpan(text: node.text, style: linkStyle));
          break;
        case NoteMarkdownInlineType.internalLink:
          spans.add(
            _buildInternalLinkSpan(
              targetTitle: node.text,
              baseStyle: baseStyle,
              semantic: semantic,
              colorScheme: colorScheme,
              maxInlineChipWidth: maxInlineChipWidth,
            ),
          );
          break;
      }
    }
    return spans;
  }
}
