import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dchs_flutter_beacon/dchs_flutter_beacon.dart' as flutter_beacon;
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BeaconTestHarnessPage extends StatefulWidget {
  const BeaconTestHarnessPage({super.key});

  @override
  State<BeaconTestHarnessPage> createState() => _BeaconTestHarnessPageState();
}

class _BeaconTestHarnessPageState extends State<BeaconTestHarnessPage> {
  final Logger _logger = Logger();
  StreamSubscription<flutter_beacon.RangingResult>? _rangingSubscription;
  
  // Test results
  final List<BeaconDetectionEvent> _detectionEvents = [];
  DateTime? _scanStartTime;
  String _deviceInfo = 'Loading...';
  bool _isScanning = false;
  String _scanStatus = 'Ready to scan';
  
  // Last detected beacon info
  String? _lastDetectedUUID;
  int? _lastDetectedMajor;
  int? _lastDetectedMinor;
  int? _lastDetectedRSSI;
  DateTime? _lastDetectionTime;
  
  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _startScanningAutomatically();
  }

  @override
  void dispose() {
    _stopScanning();
    super.dispose();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String info;
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        info = 'Android ${androidInfo.version.release} - ${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        info = 'iOS ${iosInfo.systemVersion} - ${iosInfo.model}';
      } else {
        info = 'Unknown Platform';
      }
      
      setState(() {
        _deviceInfo = info;
      });
    } catch (e) {
      setState(() {
        _deviceInfo = 'Error loading device info: $e';
      });
    }
  }

  Future<void> _startScanningAutomatically() async {
    // Auto-start scanning on page load for immediate testing
    await Future.delayed(const Duration(milliseconds: 500));
    _startScanning();
  }

  Future<void> _startScanning() async {
    if (_isScanning) return;
    
    try {
      setState(() {
        _scanStatus = 'Checking permissions...';
      });

      // Check for Bluetooth scanning permissions
      if (await Permission.bluetooth.isDenied ||
          await Permission.bluetoothScan.isDenied || 
          await Permission.bluetoothConnect.isDenied ||
          await Permission.locationWhenInUse.isDenied) {
        
        setState(() {
          _scanStatus = 'Requesting permissions...';
        });
        
        // Request all required Bluetooth permissions
        Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetooth,
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
        
        // Check if any permission was denied
        if (statuses.values.any((status) => !status.isGranted)) {
          setState(() {
            _scanStatus = 'Permissions denied: $statuses';
          });
          return;
        }
      }

      setState(() {
        _scanStatus = 'Initializing beacon scanning...';
      });

      // Initialize beacon scanning
      await flutter_beacon.flutterBeacon.initializeScanning;
      
      setState(() {
        _scanStatus = 'Starting scan...';
        _isScanning = true;
        _detectionEvents.clear();
        _scanStartTime = DateTime.now();
      });

      // Get all active sessions with beacon IDs (same as real self-scan)
      final now = Timestamp.now();
      final sessionsSnapshot = await FirebaseFirestore.instance
          .collection('sessions')
          .where('startTime', isLessThanOrEqualTo: now)
          .where('endTime', isGreaterThanOrEqualTo: now)
          .where('beaconId', isNull: false)
          .get();
      
      if (sessionsSnapshot.docs.isEmpty) {
        setState(() {
          _scanStatus = 'No active sessions with beacons found';
        });
        return;
      }
      
      // Store active sessions for lookup during scanning
      final activeSessions = <Map<String, dynamic>>[];
      for (final doc in sessionsSnapshot.docs) {
        final data = doc.data();
        final beaconId = data['beaconId'] as String?;
        final beaconMajor = data['beaconMajor'] as int?;
        final beaconMinor = data['beaconMinor'] as int?;
        
        if (beaconId != null && beaconMajor != null && beaconMinor != null) {
          activeSessions.add({
            ...data,
            'sessionId': doc.id,
          });
        }
      }
      
      if (activeSessions.isEmpty) {
        setState(() {
          _scanStatus = 'No active sessions with valid beacon data found';
        });
        return;
      }

      // Create a region for your app's beacon UUID (same as real attendance)
      const appBeaconUUID = '74278BDA-B644-4520-8F0C-720EAF059935';
      final regions = [
        flutter_beacon.Region(
          identifier: 'test-harness-app-beacons',
          proximityUUID: appBeaconUUID,
        )
      ];

      _logger.i('🔍 Beacon test harness started scanning at ${_scanStartTime!.toIso8601String()}');
      print('🔍 Beacon test harness started scanning at ${_scanStartTime!.toIso8601String()}');

      // Start ranging with lightweight callback
      _rangingSubscription = flutter_beacon.flutterBeacon.ranging(regions).listen(
        (flutter_beacon.RangingResult result) {
          // Defer processing to microtask to keep callback lightweight
          scheduleMicrotask(() => _processRangingResult(result));
        },
        onError: (error) {
          _logger.e('Error ranging beacons: $error');
          print('❌ Error ranging beacons: $error');
          setState(() {
            _scanStatus = 'Error: $error';
          });
        },
      );
      
      setState(() {
        _scanStatus = 'Scanning for beacons... (${regions.length} regions)';
      });
      
    } catch (e) {
      _logger.e('Error starting beacon scanning: $e');
      print('❌ Error starting beacon scanning: $e');
      setState(() {
        _scanStatus = 'Error starting scan: $e';
        _isScanning = false;
      });
    }
  }

  void _processRangingResult(flutter_beacon.RangingResult result) {
    final now = DateTime.now();
    final beacons = result.beacons;
    
    if (beacons.isNotEmpty && _scanStartTime != null) {
      final nearestBeacon = beacons.first;
      final timeToDetection = now.difference(_scanStartTime!);
      
      // Check if this is a new beacon detection (different identity or significant time gap)
      final isNewDetection = _lastDetectedUUID != nearestBeacon.proximityUUID ||
                            _lastDetectedMajor != nearestBeacon.major ||
                            _lastDetectedMinor != nearestBeacon.minor ||
                            (_lastDetectionTime != null && 
                             now.difference(_lastDetectionTime!).inSeconds > 2);
      
      if (isNewDetection) {
        final event = BeaconDetectionEvent(
          detectionTime: now,
          timeToDetection: timeToDetection,
          uuid: nearestBeacon.proximityUUID,
          major: nearestBeacon.major,
          minor: nearestBeacon.minor,
          rssi: nearestBeacon.rssi,
          accuracy: nearestBeacon.accuracy,
        );
        
        _logger.i('📍 Beacon detected: ${event.toString()}');
        print('📍 Beacon detected: ${event.toString()}');
        
        setState(() {
          _detectionEvents.add(event);
          _lastDetectedUUID = nearestBeacon.proximityUUID;
          _lastDetectedMajor = nearestBeacon.major;
          _lastDetectedMinor = nearestBeacon.minor;
          _lastDetectedRSSI = nearestBeacon.rssi;
          _lastDetectionTime = now;
          
          // Update status with latest detection
          _scanStatus = 'Scanning... (${_detectionEvents.length} detections)';
        });
      } else {
        // Update RSSI for existing beacon without creating new event
        if (_lastDetectedRSSI != nearestBeacon.rssi) {
          setState(() {
            _lastDetectedRSSI = nearestBeacon.rssi;
            _lastDetectionTime = now;
          });
        }
      }
    }
  }

  Future<void> _stopScanning() async {
    await _rangingSubscription?.cancel();
    _rangingSubscription = null;
    
    setState(() {
      _isScanning = false;
      _scanStatus = 'Stopped';
    });
    
    _logger.i('🛑 Beacon scanning stopped');
    print('🛑 Beacon scanning stopped');
  }

  void _clearResults() {
    setState(() {
      _detectionEvents.clear();
      _lastDetectedUUID = null;
      _lastDetectedMajor = null;
      _lastDetectedMinor = null;
      _lastDetectedRSSI = null;
      _lastDetectionTime = null;
      _scanStartTime = DateTime.now(); // Reset start time
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beacon Test Harness'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _clearResults,
            icon: const Icon(Icons.clear_all),
            tooltip: 'Clear Results',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Device Information',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(_deviceInfo),
                    const SizedBox(height: 8),
                    Text('Scan Status: $_scanStatus'),
                  ],
                ),
              ),
            ),
            
            // Current Detection Card (if any)
            if (_lastDetectedUUID != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Beacon',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('UUID: $_lastDetectedUUID'),
                      Text('Major: $_lastDetectedMajor'),
                      Text('Minor: $_lastDetectedMinor'),
                      Text('RSSI: $_lastDetectedRSSI dBm'),
                      if (_lastDetectionTime != null)
                        Text('Last Seen: ${_formatTime(_lastDetectionTime!)}'),
                    ],
                  ),
                ),
              ),
            ],
            
            // Control Buttons
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _isScanning ? null : _startScanning,
                  child: const Text('Start Scanning'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isScanning ? _stopScanning : null,
                  child: const Text('Stop Scanning'),
                ),
              ],
            ),
            
            // Detection Events List
            const SizedBox(height: 16),
            Text(
              'Detection Events (${_detectionEvents.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            
            Expanded(
              child: _detectionEvents.isEmpty
                  ? const Center(
                      child: Text(
                        'No beacons detected yet.\nMake sure a beacon is broadcasting nearby.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _detectionEvents.length,
                      itemBuilder: (context, index) {
                        final event = _detectionEvents[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Text('${index + 1}'),
                            ),
                            title: Text('${event.timeToDetection.inMilliseconds}ms'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('UUID: ${event.uuid}'),
                                Text('Major: ${event.major}, Minor: ${event.minor}'),
                                Text('RSSI: ${event.rssi} dBm, Accuracy: ${event.accuracy?.toStringAsFixed(1)}m'),
                                Text('Time: ${_formatTime(event.detectionTime)}'),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}.'
           '${(time.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }
}

class BeaconDetectionEvent {
  final DateTime detectionTime;
  final Duration timeToDetection;
  final String uuid;
  final int major;
  final int minor;
  final int rssi;
  final double? accuracy;

  BeaconDetectionEvent({
    required this.detectionTime,
    required this.timeToDetection,
    required this.uuid,
    required this.major,
    required this.minor,
    required this.rssi,
    this.accuracy,
  });

  @override
  String toString() {
    return 'BeaconDetectionEvent{'
           'timeToDetection: ${timeToDetection.inMilliseconds}ms, '
           'uuid: $uuid, '
           'major: $major, '
           'minor: $minor, '
           'rssi: $rssi dBm, '
           'accuracy: ${accuracy?.toStringAsFixed(1)}m, '
           'time: ${detectionTime.toIso8601String()}'
           '}';
  }
}
