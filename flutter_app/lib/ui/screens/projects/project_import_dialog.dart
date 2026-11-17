import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/projects/projects_controller.dart';
import '../../../core/shared_foundation.dart';
import '../../../core/theme/daywell_theme.dart';
import '../../../domain/projects/bim_outreach_template.dart';
import '../../../domain/projects/project_package_codec.dart';
import '../../../services/export/project_package_io_service.dart';
import '../../widgets/shared_ui_widgets.dart';

class ProjectImportDialog extends StatefulWidget {
  final ProjectsController projectsController;

  const ProjectImportDialog({
    super.key,
    required this.projectsController,
  });

  static Future<PreparedProjectPackageImport?> show(
    BuildContext context, {
    required ProjectsController projectsController,
  }) {
    return showDialog<PreparedProjectPackageImport>(
      context: context,
      builder: (_) => ProjectImportDialog(
        projectsController: projectsController,
      ),
    );
  }

  @override
  State<ProjectImportDialog> createState() => _ProjectImportDialogState();
}

class _ProjectImportDialogState extends State<ProjectImportDialog> {
  final TextEditingController _jsonController = TextEditingController();
  String? _selectedFilename;
  String? _errorMessage;
  String? _pickerNotice;
  bool _isPicking = false;
  bool _isImporting = false;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_isPicking || _isImporting) return;
    setState(() {
      _isPicking = true;
      _errorMessage = null;
      _pickerNotice = null;
    });
    try {
      final picked = await ProjectPackageIoService.pickProjectPackageFile();
      if (!mounted) return;
      if (picked != null) {
        setState(() {
          _selectedFilename = picked.filename;
          _jsonController.text = picked.content;
        });
      }
    } on ProjectPackageIoUnavailableException catch (e) {
      if (!mounted) return;
      setState(() => _pickerNotice = e.message);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage =
            e.message ?? 'Unable to read selected .daywellproject file.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
  }

  Future<void> _importRawJson(String raw) async {
    if (raw.trim().isEmpty || _isImporting) return;
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });
    final imported = await widget.projectsController.importProjectPackageJson(
      raw,
    );
    if (!mounted) return;
    if (imported != null) {
      Navigator.of(context).pop(imported);
      return;
    }
    final err = widget.projectsController.state.errorMessage ??
        'Unable to import project package.';
    widget.projectsController.clearError();
    setState(() {
      _isImporting = false;
      _errorMessage = err;
    });
  }

  Future<void> _submitImport() => _importRawJson(_jsonController.text);

  Future<void> _loadBimTemplate() =>
      _importRawJson(BimOutreachTemplate.buildPackageJson());

  @override
  Widget build(BuildContext context) {
    final semantic = context.daywellColors;
    final textTheme = Theme.of(context).textTheme;
    final hasInput = _jsonController.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('Import Project (.daywellproject)'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Imports a portable project package as a new local project without overwriting existing projects.',
                style: textTheme.bodySmall?.copyWith(
                  color: semantic.textSecondary,
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              if (_errorMessage != null) ...[
                DaywellStatusBanner(
                  message: _errorMessage!,
                  tone: DaywellStatusTone.error,
                  liveRegion: true,
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
              ],
              if (_pickerNotice != null) ...[
                DaywellStatusBanner(
                  message: _pickerNotice!,
                  tone: DaywellStatusTone.warning,
                ),
                const SizedBox(height: SharedDesignTokens.spacingCompact),
              ],
              DaywellCard(
                padding: const EdgeInsets.all(
                  SharedDesignTokens.spacingCompact,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'LOAD TEMPLATE',
                      style: textTheme.labelSmall?.copyWith(
                        color: semantic.textMuted,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      BimOutreachTemplate.projectTitle,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingXs),
                    Text(
                      '1,000 target emails across 100 US cities grouped by Census region · 22 days (46/day · Hidar 9–30, 2019 E.C.)',
                      style: textTheme.bodySmall?.copyWith(
                        color: semantic.textSecondary,
                      ),
                    ),
                    const SizedBox(height: SharedDesignTokens.spacingSm),
                    DaywellButton(
                      label: 'Load BIM Outreach Template',
                      variant: DaywellButtonVariant.secondary,
                      size: DaywellButtonSize.compact,
                      leadingIcon: Icons.auto_awesome_outlined,
                      fullWidth: true,
                      isLoading: _isImporting,
                      onPressed: _isPicking ? null : _loadBimTemplate,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              DaywellButton(
                label: 'Choose .daywellproject File',
                variant: DaywellButtonVariant.secondary,
                leadingIcon: Icons.folder_open_outlined,
                fullWidth: true,
                isLoading: _isPicking,
                onPressed: _isImporting ? null : _pickFile,
              ),
              if (_selectedFilename != null) ...[
                const SizedBox(height: SharedDesignTokens.spacingXs),
                Text(
                  'Loaded file: $_selectedFilename',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: semantic.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: SharedDesignTokens.spacingCompact),
              TextField(
                controller: _jsonController,
                minLines: 4,
                maxLines: 7,
                style: DaywellTypography.mono(color: semantic.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Or Paste Package JSON',
                  hintText:
                      '{"formatId": "daywell_project_package", "formatVersion": 1, ...}',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: (_) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  } else {
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        DaywellButton(
          label: 'Cancel',
          variant: DaywellButtonVariant.text,
          size: DaywellButtonSize.compact,
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
        ),
        DaywellButton(
          label: 'Import',
          variant: DaywellButtonVariant.primary,
          size: DaywellButtonSize.compact,
          isLoading: _isImporting,
          onPressed: hasInput && !_isPicking ? _submitImport : null,
        ),
      ],
    );
  }
}
