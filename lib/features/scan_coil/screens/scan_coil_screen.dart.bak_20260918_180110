import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/services/qr_parser_service.dart';
import '../../../core/services/supabase_service.dart';

class ScanCoilScreen extends StatefulWidget {
  const ScanCoilScreen({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<ScanCoilScreen> createState() => _ScanCoilScreenState();
}

class _ScanViewItem {
  _ScanViewItem({
    required this.coilNo,
    required this.thickness,
    required this.width,
    required this.localSequence,
  });

  final String coilNo;
  final double thickness;
  final double width;
  final int localSequence;

  int? serverSequence;
  bool saved = false;
  String? error;
}

class _ScanCoilScreenState extends State<ScanCoilScreen>
    with WidgetsBindingObserver {
  late final MobileScannerController _camera;
  late final TextEditingController _operatorController;

  final _parser = const QrParserService();
  final Set<String> _sessionCoils = <String>{};
  final List<Map<String, dynamic>> _queue = <Map<String, dynamic>>[];
  final List<_ScanViewItem> _recent = <_ScanViewItem>[];

  List<Map<String, dynamic>> _locations = const [];
  List<Map<String, dynamic>> _lines = const [];

  String? _locationId;
  String? _lineId;
  String? _sessionId;
  String? _lastCoil;
  String? _error;

  bool _workerRunning = false;
  OverlayEntry? _scanPopupEntry;
  Timer? _scanPopupTimer;
  Future<void>? _drainFuture;
  int _localSequence = 0;

  bool get _canScan =>
      _locationId != null &&
      _lineId != null &&
      _operatorController.text.trim().isNotEmpty;

  bool get _isRunning => _camera.value.isRunning;

  // Serialize camera start/stop operations. MobileScannerController
  // throws if start() is called while another start/stop transition
  // is still in progress.
  Future<void> _cameraOperation = Future<void>.value();
  bool _cameraDisposed = false;

  Future<void> _enqueueCameraOperation(Future<void> Function() operation) {
    final next = _cameraOperation.then((_) => operation());

    // Keep the queue alive even if one platform camera operation fails.
    _cameraOperation = next.catchError((Object error, StackTrace stack) {
      debugPrint('Camera operation failed: $error');
      debugPrint('$stack');
    });

    return next;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _camera = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );

    _operatorController = TextEditingController(text: 'Operator');

    _loadMasters();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_stopCamera(updateUi: true));
    }

    if (state == AppLifecycleState.resumed && widget.isActive && _canScan) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startCamera());
      });
    }
  }

  Future<void> _loadMasters() async {
    try {
      final db = SupabaseService.client;

      final results = await Future.wait([
        db
            .from('app_locations')
            .select('id,code,name,location_type')
            .eq('active', true)
            .order('name'),
        db
            .from('app_lines')
            .select('id,code,name,location_id')
            .eq('active', true)
            .order('name'),
      ]);

      if (!mounted) return;

      final locations = List<Map<String, dynamic>>.from(results[0] as List);
      final lines = List<Map<String, dynamic>>.from(results[1] as List);

      setState(() {
        _locations = locations;
        _lines = lines;

        if (_locationId == null && locations.isNotEmpty) {
          _locationId = locations.first['id'] as String;
        }

        if (_lineId != null &&
            !_visibleLines.any((line) => line['id'] == _lineId)) {
          _lineId = null;
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _canScan) {
          unawaited(_startCamera());
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Master data load failed: $error';
      });
    }
  }

  List<Map<String, dynamic>> get _visibleLines {
    if (_locationId == null) return _lines;

    return _lines.where((line) {
      final locationId = line['location_id'] as String?;
      return locationId == null || locationId == _locationId;
    }).toList();
  }

  Future<void> _startCamera() {
    if (_cameraDisposed) return Future<void>.value();

    return _enqueueCameraOperation(() async {
      if (_cameraDisposed ||
          !mounted ||
          !widget.isActive ||
          !_canScan ||
          _isRunning) {
        return;
      }

      try {
        await _camera.start();

        if (!mounted || _cameraDisposed) return;

        setState(() {
          _error = null;
        });
      } catch (e, st) {
        debugPrint('========================================');
        debugPrint('CAMERA START FAILED');
        debugPrint('ERROR TYPE: ${e.runtimeType}');
        debugPrint('ERROR: $e');
        debugPrint('STACK TRACE:');
        debugPrint('$st');
        debugPrint('========================================');

        if (!mounted || _cameraDisposed) return;

        setState(() {
          _error = 'Camera could not be started. Please try again.';
        });
      }
    });
  }

  Future<void> _stopCamera({bool updateUi = false}) {
    if (_cameraDisposed) return Future<void>.value();

    return _enqueueCameraOperation(() async {
      if (_cameraDisposed) return;

      if (!_isRunning) {
        if (updateUi && mounted) {
          setState(() {});
        }
        return;
      }

      try {
        await _camera.stop();
      } catch (e, st) {
        debugPrint('========================================');
        debugPrint('CAMERA STOP FAILED');
        debugPrint('ERROR TYPE: ${e.runtimeType}');
        debugPrint('ERROR: $e');
        debugPrint('STACK TRACE:');
        debugPrint('$st');
        debugPrint('========================================');
      }

      if (updateUi && mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _closeSession() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;

    try {
      await SupabaseService.client
          .from('scan_sessions')
          .update({'ended_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', sessionId);
    } catch (error, stack) {
      debugPrint('CLOSE SESSION FAILED: $error');
      debugPrint('$stack');
    } finally {
      _sessionId = null;
    }
  }

  Future<void> _ensureSession() async {
    if (_sessionId != null) return;

    final response = await SupabaseService.client
        .from('scan_sessions')
        .insert({
          'location_id': _locationId,
          'line_id': _lineId,
          'operator_label': _operatorController.text.trim(),
        })
        .select('id')
        .single();

    _sessionId = response['id'] as String;
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isRunning || !_canScan) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();

      if (raw == null || raw.isEmpty) continue;

      _handleRawQr(raw);
      break;
    }
  }

  void _handleRawQr(String raw) {
    CoilQrData parsed;

    try {
      parsed = _parser.parse(raw);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Invalid QR: $error';
        });
      }
      HapticFeedback.heavyImpact();
      return;
    }

    final coilKey = parsed.coilNo.trim().toUpperCase();

    if (coilKey.isEmpty || _sessionCoils.contains(coilKey)) {
      return;
    }

    _sessionCoils.add(coilKey);

    final localSequence = ++_localSequence;
    final item = _ScanViewItem(
      coilNo: parsed.coilNo,
      thickness: parsed.thickness,
      width: parsed.width,
      localSequence: localSequence,
    );

    _queue.add({'coil': parsed, 'sequence': localSequence, 'item': item});

    if (mounted) {
      setState(() {
        _lastCoil = parsed.coilNo;
        _error = null;
        _recent.insert(0, item);
        if (_recent.length > 15) {
          _recent.removeLast();
        }
      });
    }

    HapticFeedback.selectionClick();
    unawaited(_drainQueue());
  }

  Future<void> _drainQueue() {
    final active = _drainFuture;
    if (active != null) return active;

    final future = _drainQueueInternal();
    _drainFuture = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_drainFuture, future)) {
          _drainFuture = null;
        }
      }),
    );
    return future;
  }

  Future<void> _drainQueueInternal() async {
    if (_workerRunning) return;
    _workerRunning = true;

    try {
      while (_queue.isNotEmpty) {
        final pending = _queue.removeAt(0);
        final parsed = pending['coil'] as CoilQrData;
        final item = pending['item'] as _ScanViewItem;

        try {
          await _ensureSession();

          final sessionId = _sessionId;
          final locationId = _locationId;
          final lineId = _lineId;
          if (sessionId == null || locationId == null || lineId == null) {
            throw const FormatException('Scan session details are missing.');
          }

          Map<String, dynamic>? previousLocation;
          try {
            final previousRows = await SupabaseService.client
                .from('v_current_coil_locations')
                .select(
                  'coil_no,location_id,line_id,location_name,line_name,scanned_at',
                )
                .eq('coil_no', parsed.coilNo)
                .limit(1);
            if (previousRows.isNotEmpty) {
              previousLocation = Map<String, dynamic>.from(
                previousRows.first as Map,
              );
            }
          } catch (_) {
            // A history lookup must never block saving a scan.
          }

          final result = await SupabaseService.client.rpc(
            'record_coil_scan',
            params: {
              'p_session_id': sessionId,
              'p_coil_no': parsed.coilNo,
              'p_material_code': parsed.materialCode,
              'p_thickness': parsed.thickness,
              'p_width': parsed.width,
              'p_location_id': locationId,
              'p_line_id': lineId,
              'p_operator_label': _operatorController.text.trim(),
            },
          );

          final rows = result as List;
          if (rows.isEmpty) {
            throw const FormatException(
              'Database did not return a scan result.',
            );
          }

          final row = Map<String, dynamic>.from(rows.first as Map);
          final duplicate = row['is_duplicate'] == true;
          final sequence = (row['sequence_no'] as num?)?.toInt();

          if (!mounted) continue;

          setState(() {
            item.serverSequence = sequence;
            item.saved = true;
            item.error = duplicate ? 'Duplicate in current session' : null;
          });

          HapticFeedback.mediumImpact();

          List<String> machines = const [];
          try {
            machines = await _plannedMachinesForCoil(parsed.coilNo);
          } catch (_) {
            // Keep camera UX clean. The scan is already persisted.
          }

          if (mounted) {
            // Non-blocking result banner: the camera/scan queue continues
            // immediately while the result remains visible for 2 seconds.
            _showScanResultPopup(
              coilNo: parsed.coilNo,
              thickness: parsed.thickness,
              width: parsed.width,
              machines: machines,
              previousLocation: previousLocation,
            );
          }
        } catch (error) {
          if (!mounted) continue;
          setState(() {
            item.error = _friendlyDatabaseError(error);
          });
        }
      }
    } finally {
      _workerRunning = false;
    }
  }

  Future<List<String>> _plannedMachinesForCoil(String coilNo) async {
    final normalized = coilNo.trim().toUpperCase();

    if (normalized.isEmpty) return const [];

    // IMPORTANT:
    // Scan result must use the exact same canonical PPC view
    // as Check Location.
    //
    // This fixes:
    // Mother = 26T120470A
    // Slit   = C
    // Physical Coil = 26T120470C
    //
    // and returns exact machine code:
    // CRS00005
    final rows = await SupabaseService.client
        .from('v_active_ppc_coils')
        .select('physical_coil_no,planned_machine_code');

    final codes = <String>{};

    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final physical = '${row['physical_coil_no'] ?? ''}'.trim().toUpperCase();

      if (physical != normalized) continue;

      final code = '${row['planned_machine_code'] ?? ''}'.trim();

      if (code.isNotEmpty) {
        codes.add(code);
      }
    }

    final result = codes.toList()..sort();

    return result;
  }

  void _showScanResultPopup({
    required String coilNo,
    required double thickness,
    required double width,
    required List<String> machines,
    Map<String, dynamic>? previousLocation,
  }) {
    if (!mounted) return;

    String locationName = '-';
    String lineName = '-';

    for (final row in _locations) {
      if (row['id'] == _locationId) {
        locationName = '${row['name'] ?? row['code'] ?? '-'}';
        break;
      }
    }
    for (final row in _lines) {
      if (row['id'] == _lineId) {
        lineName = '${row['name'] ?? row['code'] ?? '-'}';
        break;
      }
    }

    _scanPopupTimer?.cancel();
    _scanPopupEntry?.remove();

    final planned = machines.isNotEmpty;
    final locationUpdated =
        previousLocation != null &&
        (previousLocation['location_id'] != _locationId ||
            previousLocation['line_id'] != _lineId);
    final locationStatus = locationUpdated
        ? 'LOCATION UPDATED'
        : 'LOCATION AVAILABLE';
    final entry = OverlayEntry(
      builder: (overlayContext) {
        final width = MediaQuery.sizeOf(overlayContext).width;
        return Positioned(
          top: MediaQuery.paddingOf(overlayContext).top + 14,
          left: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: width >= 700 ? 560 : 520),
                child: Material(
                  elevation: 12,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: planned ? AppColors.success : AppColors.warning,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          planned
                              ? Icons.check_circle_rounded
                              : Icons.info_rounded,
                          color: planned
                              ? AppColors.success
                              : AppColors.warning,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                planned ? 'PLANNED' : 'NOT PLANNED',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                coilNo,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.sectionTitle,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                planned
                                    ? 'Machine: ${machines.join(', ')}'
                                    : 'Machine: Not planned',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                locationStatus,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: locationUpdated
                                      ? AppColors.success
                                      : AppColors.textSecondary,
                                ),
                              ),
                              if (locationUpdated)
                                Text(
                                  'Previous: ${previousLocation['location_name'] ?? '-'} • ${previousLocation['line_name'] ?? '-'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Text(
                                'Actual Location: $locationName • Line: $lineName',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text('Size: $thickness × $width'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _scanPopupEntry = entry;
    overlay.insert(entry);
    _scanPopupTimer = Timer(const Duration(seconds: 2), () {
      if (identical(_scanPopupEntry, entry)) {
        entry.remove();
        _scanPopupEntry = null;
      }
    });
  }

  String _friendlyDatabaseError(Object error) {
    final message = error.toString().toLowerCase();

    if (message.contains('socket') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('timeout')) {
      return 'Network unavailable. Please check your connection.';
    }

    if (message.contains('permission') ||
        message.contains('rls') ||
        message.contains('row-level security')) {
      return 'Scan could not be saved because database permission was denied.';
    }

    if (message.contains('record_coil_scan') ||
        message.contains('function') ||
        message.contains('postgrest')) {
      return 'Scan could not be saved. Please try again.';
    }

    return 'Scan could not be saved. Please try again.';
  }

  Future<void> _newSession() async {
    await _drainQueue();
    await _stopCamera();
    await _closeSession();

    if (!mounted) return;

    setState(() {
      _sessionCoils.clear();
      _queue.clear();
      _recent.clear();
      _localSequence = 0;
      _lastCoil = null;
      _error = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive) unawaited(_startCamera());
    });
  }

  @override
  void dispose() {
    _cameraDisposed = true;

    WidgetsBinding.instance.removeObserver(this);
    _scanPopupTimer?.cancel();
    _scanPopupEntry?.remove();
    _scanPopupEntry = null;
    _operatorController.dispose();

    unawaited(_camera.dispose());

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final padding = constraints.maxWidth >= 700 ? 28.0 : 16.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding, 20, padding, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: _scannerCard()),
                        const SizedBox(width: 18),
                        Expanded(flex: 4, child: _controlPanel()),
                      ],
                    )
                  : Column(
                      children: [
                        _scannerCard(),
                        const SizedBox(height: 16),
                        _controlPanel(),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _scannerCard() {
    final running = _isRunning;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continuous QR Scanner',
                        style: AppTextStyles.sectionTitle,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Scan coil after coil. No confirmation between scans.',
                        style: AppTextStyles.pageSubtitle,
                      ),
                    ],
                  ),
                ),
                _StatusChip(active: running),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The scanner widget stays mounted even while paused.
                // This prevents controllerNotAttached start races.
                MobileScanner(controller: _camera, onDetect: _onDetect),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 250,
                      height: 175,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 430;
                      final buttonWidth = compact
                          ? (constraints.maxWidth - 10) / 2
                          : (constraints.maxWidth - 20) / 3;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: buttonWidth,
                            child: _CameraButton(
                              icon: running
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              label: running ? 'Pause' : 'Start',
                              onTap: running
                                  ? () => _stopCamera(updateUi: true)
                                  : _startCamera,
                            ),
                          ),
                          SizedBox(
                            width: buttonWidth,
                            child: _CameraButton(
                              icon: Icons.flash_on_rounded,
                              label: 'Torch',
                              onTap: () async {
                                if (_isRunning) {
                                  await _camera.toggleTorch();
                                }
                              },
                            ),
                          ),
                          SizedBox(
                            width: buttonWidth,
                            child: _CameraButton(
                              icon: Icons.flip_camera_android_rounded,
                              label: 'Camera',
                              onTap: () async {
                                if (_isRunning) {
                                  await _camera.switchCamera();
                                }
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  running
                      ? Icons.speed_rounded
                      : Icons.pause_circle_outline_rounded,
                  size: 18,
                  color: running ? AppColors.success : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _canScan
                        ? running
                              ? 'Scanner is ready. Move directly to the next coil.'
                              : 'Scanner paused. Press Start to continue.'
                        : 'Choose Location and Line before scanning.',
                    style: AppTextStyles.cardLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeLocation(String? value) async {
    if (value == null || value == _locationId) return;

    await _drainQueue();
    await _stopCamera();
    await _closeSession();

    if (!mounted) return;

    setState(() {
      _locationId = value;
      _lineId = null;
      _sessionCoils.clear();
      _queue.clear();
      _recent.clear();
      _localSequence = 0;
      _lastCoil = null;
      _error = null;
    });
  }

  Future<void> _changeLine(String? value) async {
    if (value == null || value == _lineId) return;

    await _drainQueue();
    await _stopCamera();
    await _closeSession();

    if (!mounted) return;

    setState(() {
      _lineId = value;
      _sessionCoils.clear();
      _queue.clear();
      _recent.clear();
      _localSequence = 0;
      _lastCoil = null;
      _error = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive && _canScan) {
        unawaited(_startCamera());
      }
    });
  }

  Widget _controlPanel() {
    final visibleLines = _visibleLines;

    return Column(
      children: [
        _selector(
          title: 'Actual Location',
          icon: Icons.location_on_rounded,
          value: _locationId,
          items: _locations,
          labelBuilder: (item) => '${item['name']}',
          onChanged: _changeLocation,
        ),
        const SizedBox(height: 12),
        _selector(
          title: 'Actual Line',
          icon: Icons.route_rounded,
          value: _lineId,
          items: visibleLines,
          labelBuilder: (item) => '${item['name']}',
          onChanged: _changeLine,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: TextField(
              controller: _operatorController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Operator / Incharge',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              onChanged: (_) {
                if (mounted) setState(() {});
              },
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: _error!),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Session Scans',
                        style: AppTextStyles.cardLabel,
                      ),
                    ),
                    Text(
                      '${_sessionCoils.length}',
                      style: AppTextStyles.cardValue.copyWith(fontSize: 22),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Row(
                  children: [
                    const Icon(Icons.qr_code_rounded, color: AppColors.navy),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _lastCoil ?? 'No coil scanned yet',
                        style: AppTextStyles.sectionTitle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent Scans', style: AppTextStyles.sectionTitle),
                const SizedBox(height: 12),
                if (_recent.isEmpty)
                  const Text(
                    'No scans in this session.',
                    style: AppTextStyles.pageSubtitle,
                  )
                else
                  ..._recent.map(_recentTile),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _sessionCoils.isEmpty ? null : _newSession,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Start New Scan Session'),
          ),
        ),
      ],
    );
  }

  Widget _selector({
    required String title,
    required IconData icon,
    required String? value,
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) labelBuilder,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.any((item) => item['id'] == value) ? value : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: DropdownButtonFormField<String>(
          initialValue: safeValue,
          decoration: InputDecoration(labelText: title, prefixIcon: Icon(icon)),
          items: [
            for (final item in items)
              DropdownMenuItem<String>(
                value: item['id'] as String,
                child: Text(
                  labelBuilder(item),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _recentTile(_ScanViewItem item) {
    final color = item.error != null
        ? AppColors.danger
        : item.saved
        ? AppColors.success
        : AppColors.warning;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Text(
              item.serverSequence?.toString() ?? item.localSequence.toString(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.coilNo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.thickness} × ${item.width}',
                  style: AppTextStyles.cardLabel,
                ),
                if (item.error != null)
                  Text(
                    item.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.danger,
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            item.error != null
                ? Icons.error_outline_rounded
                : item.saved
                ? Icons.check_circle_rounded
                : Icons.sync_rounded,
            color: color,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            active ? 'Scanning' : 'Paused',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.danger.withValues(alpha: .06),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraButton extends StatelessWidget {
  const _CameraButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 19),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
