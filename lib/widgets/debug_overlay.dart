import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/config_service.dart';
import '../services/offline_cache_service.dart';
import '../services/gps_service.dart';
import '../services/ai_service.dart';
import '../services/localization_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class DebugOverlay extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const DebugOverlay({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> with WidgetsBindingObserver {
  final ConfigService _configService = ConfigService();
  final OfflineCacheService _cacheService = OfflineCacheService();
  final GPSService _gpsService = GPSService();
  final AIService _aiService = AIService();
  final LocalizationService _localization = LocalizationService();
  
  bool _showOverlay = false;
  int _frameCount = 0;
  DateTime _lastFpsTime = DateTime.now();
  double _fps = 0;
  Map<String, dynamic>? _cacheStats;
  ConnectivityResult _connectivity = ConnectivityResult.none;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      WidgetsBinding.instance.addObserver(this);
      _startFpsCounter();
      _loadCacheStats();
      _listenConnectivity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Detect shake gesture for toggling debug overlay
    // In real implementation, use accelerometer
  }

  void _startFpsCounter() {
    WidgetsBinding.instance.addPersistentFrameCallback((timeStamp) {
      _frameCount++;
      final now = DateTime.now();
      if (now.difference(_lastFpsTime).inSeconds >= 1) {
        setState(() {
          _fps = _frameCount / now.difference(_lastFpsTime).inSeconds;
          _frameCount = 0;
          _lastFpsTime = now;
        });
      }
    });
  }

  Future<void> _loadCacheStats() async {
    try {
      final stats = await _cacheService.getCacheStats();
      if (mounted) setState(() => _cacheStats = stats);
    } catch (e) {
      debugPrint('DebugOverlay cache stats failed: $e'); // never crash a frame
    }
  }

  void _listenConnectivity() {
    Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) setState(() => _connectivity = result);
    });
    Connectivity().checkConnectivity().then((r) {
      if (mounted) setState(() => _connectivity = r);
    });
  }

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    // No full-screen gesture here: a stray double-tap must not raise the debug
    // panel over the live UI, and it must not compete with the viewfinder's
    // own gestures. Open it only via the small corner chip (_buildIndicator).
    return Stack(
      children: [
        widget.child,
        if (_showOverlay) _buildOverlay(),
        if (widget.enabled && !_showOverlay) _buildIndicator(),
      ],
    );
  }

  Widget _buildIndicator() {
    return Positioned(
      top: 10,
      left: 10,
      child: GestureDetector(
        onTap: _toggleOverlay,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'DEBUG ${_fps.toStringAsFixed(0)}fps',
            style: const TextStyle(color: Colors.green, fontSize: 10, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    final gpsPos = _gpsService.getLastKnownPosition();
    final gpsAddr = _gpsService.getLastKnownAddress();
    final isOnline = _connectivity != ConnectivityResult.none;

    return Container(
      color: Colors.black.withOpacity(0.85),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'DEBUG OVERLAY',
                    style: TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: _toggleOverlay,
                  ),
                ],
              ),
              const Divider(color: Colors.green),
              _buildSection('PERFORMANCE', [
                _buildRow('FPS', _fps.toStringAsFixed(1)),
                _buildRow('Model', _aiService.useOnDevice ? 'ON-DEVICE (Gemma)' : 'CLOUD (Gemini)'),
                _buildRow('On-Device Ready', _aiService.initialized ? (_aiService.useOnDevice ? 'YES' : 'NO (fallback)') : 'INIT...'),
              ]),
              _buildSection('GPS', [
                _buildRow('Status', _gpsService.getLastKnownPosition() != null ? 'ACTIVE' : 'NO FIX'),
                _buildRow('Accuracy', gpsPos != null ? '${gpsPos.accuracy.toStringAsFixed(1)}m' : 'N/A'),
                _buildRow('Lat/Lon', gpsPos != null ? '${gpsPos.latitude.toStringAsFixed(6)}, ${gpsPos.longitude.toStringAsFixed(6)}' : 'N/A'),
                _buildRow('Address', gpsAddr ?? 'Resolving...'),
              ]),
              _buildSection('NETWORK', [
                _buildRow('Status', isOnline ? 'ONLINE' : 'OFFLINE'),
                _buildRow('Type', _connectivity.name),
              ]),
              _buildSection('CACHE', [
                _buildRow('Entries', _cacheStats?['entries'].toString() ?? '0'),
                _buildRow('Max Entries', _cacheStats?['maxEntries'].toString() ?? '50'),
                _buildRow('Size', '${_cacheStats?['sizeKB'] ?? '0'} KB'),
              ]),
              _buildSection('CONFIG', [
                _buildRow('On-Device LLM', _configService.appConfig.features.onDeviceLLM ? 'ON' : 'OFF'),
                _buildRow('Offline Mode', _configService.appConfig.features.offlineMode ? 'ON' : 'OFF'),
                _buildRow('Tamil Support', _configService.appConfig.features.tamilSupport ? 'ON' : 'OFF'),
                _buildRow('GPS Enabled', _configService.appConfig.features.gpsEnabled ? 'ON' : 'OFF'),
                _buildRow('TTS Enabled', _configService.appConfig.features.ttsEnabled ? 'ON' : 'OFF'),
              ]),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Stats'),
                      onPressed: _loadCacheStats,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.delete),
                      label: const Text('Clear Cache'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () async {
                        await _cacheService.clearCache();
                        await _loadCacheStats();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Double-tap to toggle | Shake for debug (TODO)',
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(color: Colors.yellow, fontSize: 13, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        ...children,
      ],
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}