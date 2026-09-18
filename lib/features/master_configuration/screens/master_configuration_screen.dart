import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/supabase_service.dart';

class MasterConfigurationScreen extends StatefulWidget {
  const MasterConfigurationScreen({super.key});

  @override
  State<MasterConfigurationScreen> createState() =>
      _MasterConfigurationScreenState();
}

class _MasterConfigurationScreenState extends State<MasterConfigurationScreen> {
  int _tab = 0;
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _locations = const [];
  List<Map<String, dynamic>> _machines = const [];
  List<Map<String, dynamic>> _lines = const [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = SupabaseService.client;
      final results = await Future.wait([
        db.from('app_locations').select().order('name'),
        db.from('app_machines').select().order('code'),
        db
            .from('app_lines')
            .select('id,code,name,location_id,active')
            .order('name'),
      ]);

      if (!mounted) return;
      setState(() {
        _locations = List<Map<String, dynamic>>.from(results[0]);
        _machines = List<Map<String, dynamic>>.from(results[1]);
        _lines = List<Map<String, dynamic>>.from(results[2]);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Master data load failed: $error';
      });
    }
  }

  Future<void> _addLocation() async {
    await _showCreateOrEditDialog(
      title: 'Add Location',
      codeLabel: 'Location Code',
      nameLabel: 'Location Name',
      extraLabel: 'Type',
      extraHint: 'area / storage / process',
      onSave: (code, name, extra) async {
        await SupabaseService.client.from('app_locations').insert({
          'code': code,
          'name': name,
          'location_type': extra.isEmpty ? 'area' : extra,
          'active': true,
        });
      },
    );
  }

  Future<void> _addMachine() async {
    await _showCreateOrEditDialog(
      title: 'Add Machine',
      codeLabel: 'Machine Code',
      nameLabel: 'Machine Name',
      onSave: (code, name, extra) async {
        await SupabaseService.client.from('app_machines').insert({
          'code': code,
          'name': name,
          'active': true,
        });
      },
    );
  }

  Future<void> _addLine() async {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    String? locationId;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('Add Line'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: codeController,
                        decoration: const InputDecoration(
                          labelText: 'Line Code',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Line Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: locationId,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                        ),
                        items: [
                          for (final location in _locations)
                            if (location['active'] == true)
                              DropdownMenuItem<String>(
                                value: location['id'] as String,
                                child: Text('${location['name']}'),
                              ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => locationId = value),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final code = codeController.text.trim();
                      final name = nameController.text.trim();
                      if (code.isEmpty || name.isEmpty) return;

                      try {
                        await SupabaseService.client.from('app_lines').insert({
                          'code': code,
                          'name': name,
                          'location_id': locationId,
                          'active': true,
                        });
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text('Could not create line: $error'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      codeController.dispose();
      nameController.dispose();
    }
    await _loadAll();
  }

  Future<void> _editLocation(Map<String, dynamic> item) async {
    await _showCreateOrEditDialog(
      title: 'Edit Location',
      codeLabel: 'Location Code',
      nameLabel: 'Location Name',
      extraLabel: 'Type',
      extraHint: 'area / storage / process',
      initialCode: '${item['code'] ?? ''}',
      initialName: '${item['name'] ?? ''}',
      initialExtra: '${item['location_type'] ?? 'area'}',
      onSave: (code, name, extra) async {
        await SupabaseService.client
            .from('app_locations')
            .update({
              'code': code,
              'name': name,
              'location_type': extra.isEmpty ? 'area' : extra,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', item['id']);
      },
    );
  }

  Future<void> _editMachine(Map<String, dynamic> item) async {
    await _showCreateOrEditDialog(
      title: 'Edit Machine',
      codeLabel: 'Machine Code',
      nameLabel: 'Machine Name',
      initialCode: '${item['code'] ?? ''}',
      initialName: '${item['name'] ?? ''}',
      onSave: (code, name, extra) async {
        await SupabaseService.client
            .from('app_machines')
            .update({
              'code': code,
              'name': name,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', item['id']);
      },
    );
  }

  Future<void> _editLine(Map<String, dynamic> item) async {
    final codeController = TextEditingController(text: '${item['code'] ?? ''}');
    final nameController = TextEditingController(text: '${item['name'] ?? ''}');
    String? locationId = item['location_id'] as String?;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: const Text('Edit Line'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: codeController,
                        decoration: const InputDecoration(
                          labelText: 'Line Code',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Line Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: locationId,
                        decoration: const InputDecoration(
                          labelText: 'Location',
                        ),
                        items: [
                          for (final location in _locations)
                            if (location['active'] == true)
                              DropdownMenuItem<String>(
                                value: location['id'] as String,
                                child: Text('${location['name']}'),
                              ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => locationId = value),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final code = codeController.text.trim();
                      final name = nameController.text.trim();
                      if (code.isEmpty || name.isEmpty) return;

                      try {
                        await SupabaseService.client
                            .from('app_lines')
                            .update({
                              'code': code,
                              'name': name,
                              'location_id': locationId,
                              'updated_at': DateTime.now()
                                  .toUtc()
                                  .toIso8601String(),
                            })
                            .eq('id', item['id']);
                        if (!dialogContext.mounted) return;
                        Navigator.of(dialogContext).pop();
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text('Could not update line: $error'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      codeController.dispose();
      nameController.dispose();
    }
    await _loadAll();
  }

  Future<void> _deleteItem({
    required String table,
    required String id,
    required String label,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete "$label"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await SupabaseService.client.from(table).delete().eq('id', id);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"$label" deleted')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Delete failed. Maybe this item is used in scans.\n$error',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _toggle(String table, String id, bool active) async {
    try {
      await SupabaseService.client
          .from(table)
          .update({'active': !active})
          .eq('id', id);
      await _loadAll();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $error'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showCreateOrEditDialog({
    required String title,
    required String codeLabel,
    required String nameLabel,
    String? extraLabel,
    String? extraHint,
    String initialCode = '',
    String initialName = '',
    String initialExtra = '',
    required Future<void> Function(String code, String name, String extra)
    onSave,
  }) async {
    final codeController = TextEditingController(text: initialCode);
    final nameController = TextEditingController(text: initialName);
    final extraController = TextEditingController(text: initialExtra);

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(labelText: codeLabel),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: nameLabel),
                  ),
                  if (extraLabel != null) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: extraController,
                      decoration: InputDecoration(
                        labelText: extraLabel,
                        hintText: extraHint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final code = codeController.text.trim();
                  final name = nameController.text.trim();
                  final extra = extraController.text.trim();
                  if (code.isEmpty || name.isEmpty) return;

                  try {
                    await onSave(code, name, extra);
                    if (!dialogContext.mounted) return;
                    Navigator.of(dialogContext).pop();
                  } catch (error) {
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('Could not save: $error'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    } finally {
      codeController.dispose();
      nameController.dispose();
      extraController.dispose();
    }
    await _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 700 ? 28.0 : 16.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Master Configuration',
                    style: AppTextStyles.pageTitle,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Locations, machines and lines are database-configured. You can add, edit, activate/deactivate and delete.',
                    style: AppTextStyles.pageSubtitle,
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          for (final entry in [
                            ('Locations', 0),
                            ('Machines', 1),
                            ('Lines', 2),
                          ])
                            Expanded(
                              child: TextButton(
                                onPressed: () =>
                                    setState(() => _tab = entry.$2),
                                child: Text(
                                  entry.$1,
                                  style: TextStyle(
                                    fontWeight: _tab == entry.$2
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: _tab == entry.$2
                                        ? AppColors.navy
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Refresh',
                            onPressed: _loading ? null : _loadAll,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  if (_loading)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    )
                  else
                    _buildTab(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTab() {
    switch (_tab) {
      case 0:
        return _masterList(
          title: 'Locations',
          addLabel: 'Add Location',
          icon: Icons.location_on_rounded,
          items: _locations,
          onAdd: _addLocation,
          onEdit: _editLocation,
          onDelete: (item) => _deleteItem(
            table: 'app_locations',
            id: item['id'] as String,
            label: '${item['name']}',
          ),
          onToggle: (item) => _toggle(
            'app_locations',
            item['id'] as String,
            item['active'] == true,
          ),
          columns: (item) => [
            '${item['code']}',
            '${item['name']}',
            '${item['location_type'] ?? 'area'}',
          ],
        );
      case 1:
        return _masterList(
          title: 'Machines',
          addLabel: 'Add Machine',
          icon: Icons.precision_manufacturing_rounded,
          items: _machines,
          onAdd: _addMachine,
          onEdit: _editMachine,
          onDelete: (item) => _deleteItem(
            table: 'app_machines',
            id: item['id'] as String,
            label: '${item['name']}',
          ),
          onToggle: (item) => _toggle(
            'app_machines',
            item['id'] as String,
            item['active'] == true,
          ),
          columns: (item) => ['${item['code']}', '${item['name']}'],
        );
      case 2:
      default:
        return _masterList(
          title: 'Lines',
          addLabel: 'Add Line',
          icon: Icons.route_rounded,
          items: _lines,
          onAdd: _addLine,
          onEdit: _editLine,
          onDelete: (item) => _deleteItem(
            table: 'app_lines',
            id: item['id'] as String,
            label: '${item['name']}',
          ),
          onToggle: (item) => _toggle(
            'app_lines',
            item['id'] as String,
            item['active'] == true,
          ),
          columns: (item) {
            final locationId = item['location_id'] as String?;
            final location = _locations.where((row) => row['id'] == locationId);
            final locationName = location.isEmpty
                ? '-'
                : '${location.first['name']}';
            return ['${item['code']}', '${item['name']}', locationName];
          },
        );
    }
  }

  Widget _masterList({
    required String title,
    required String addLabel,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    required Future<void> Function() onAdd,
    required Future<void> Function(Map<String, dynamic> item) onEdit,
    required Future<void> Function(Map<String, dynamic> item) onDelete,
    required Future<void> Function(Map<String, dynamic> item) onToggle,
    required List<String> Function(Map<String, dynamic> item) columns,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppColors.navy),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: AppTextStyles.sectionTitle)),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(addLabel),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Text(
                'No records configured yet.',
                style: AppTextStyles.pageSubtitle,
              )
            else
              ...items.map((item) {
                final values = columns(item);
                final active = item['active'] == true;

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 18,
                          runSpacing: 4,
                          children: [
                            for (final value in values)
                              Text(
                                value,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => onEdit(item),
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        color: AppColors.danger,
                        onPressed: () => onDelete(item),
                      ),
                      Switch.adaptive(
                        value: active,
                        onChanged: (_) => onToggle(item),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
