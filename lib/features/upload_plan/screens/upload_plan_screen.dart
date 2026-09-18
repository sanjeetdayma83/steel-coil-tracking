import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/ppc_import_service.dart';

class UploadPlanScreen extends StatefulWidget {
  const UploadPlanScreen({super.key});

  @override
  State<UploadPlanScreen> createState() => _UploadPlanScreenState();
}

class _UploadPlanScreenState extends State<UploadPlanScreen> {
  final _importer = const PpcImportService();

  bool _busy = false;
  String? _fileName;
  PpcImportResult? _result;
  String? _error;

  Future<void> _pickAndImport() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        throw const FormatException('Could not read the selected Excel file.');
      }

      final imported = await _importer.importXlsx(
        bytes: bytes,
        fileName: file.name,
      );

      if (!mounted) return;

      setState(() {
        _fileName = file.name;
        _result = imported;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = _cleanError(error);
        _result = null;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _cleanError(Object error) {
    final message = error.toString();

    if (message.contains('numFmtId') || message.contains('number format')) {
      return 'This Excel workbook uses a number-format definition that '
          'the importer cannot read. Please save the workbook once in '
          'Microsoft Excel and upload the saved .xlsx file.';
    }

    return message
        .replaceFirst('FormatException: ', '')
        .replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 700 ? 28.0 : 16.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Upload PPC Plan', style: AppTextStyles.pageTitle),
                  const SizedBox(height: 8),
                  const Text(
                    'Import the planning data required for coil location verification.',
                    style: AppTextStyles.pageSubtitle,
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(
                        constraints.maxWidth < 500 ? 18 : 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: AppColors.info.withValues(alpha: .10),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(
                                  Icons.table_view_rounded,
                                  color: AppColors.info,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'PPC Excel / XLSX',
                                      style: AppTextStyles.sectionTitle,
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Only required planning fields are imported.',
                                      style: AppTextStyles.pageSubtitle,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _pickAndImport,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.upload_file_rounded),
                              label: Text(
                                _busy ? 'Importing...' : 'Select PPC Excel',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _MessageCard(
                      icon: Icons.error_outline_rounded,
                      text: _error!,
                      danger: true,
                    ),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 16),
                    _MessageCard(
                      icon: Icons.check_circle_outline_rounded,
                      text: '${_fileName ?? 'PPC plan'} imported successfully.',
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, box) {
                        final cards = [
                          ('Rows Imported', '${_result!.rowsImported}'),
                          ('Rows Skipped', '${_result!.rowsSkipped}'),
                          (
                            'Machines in Plan',
                            '${_result!.machineCodes.length}',
                          ),
                        ];

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final card in cards)
                              SizedBox(
                                width: box.maxWidth < 650 ? box.maxWidth : 200,
                                child: _MetricCard(
                                  title: card.$1,
                                  value: card.$2,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 54,
                            color: AppColors.textSecondary,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Current PPC plan',
                            style: AppTextStyles.sectionTitle,
                          ),
                          SizedBox(height: 6),
                          Text(
                            'The latest successful upload becomes the current plan used by Check Location.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.pageSubtitle,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.text,
    this.danger = false,
  });

  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.success;

    return Card(
      color: color.withValues(alpha: .06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.cardLabel),
            const SizedBox(height: 6),
            Text(value, style: AppTextStyles.cardValue),
          ],
        ),
      ),
    );
  }
}
