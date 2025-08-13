import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_beacon/flutter_beacon.dart' hide BeaconBroadcast;
import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Removed unused import
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';

class BLEService {
  // Singleton pattern
  static final BLEService _instance = BLEService._internal();
  factory BLEService() => _instance;
  BLEService._internal();

  final Logger _logger = Logger();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Beacon broadcast instance
  final BeaconBroadcast _beaconBroadcast = BeaconBroadcast();
  
  // Stream controller for BLE scanning results
  final StreamController<bool> _beaconDetectedController = StreamController<bool>.broadcast();
  Stream<bool> get beaconDetected => _beaconDetectedController.stream;
  
  // Lecturer beacon state
  bool _isTransmitting = false;
  String? _currentSessionId;
  
  // Student scanning state
  StreamSubscription<RangingResult>? _rangingSubscription;
  Timer? _detectionTimer;
  bool _isBeaconDetected = false;
  bool _hasMetDetectionThreshold = false;
  DateTime? _firstDetectionTime;
  
  // Constants
  final double _detectionThresholdInSeconds = 1.5;
  final double _scanGracePeriodInSeconds = 10.0;
  
  /// Start broadcasting a BLE beacon for a specific session and mode
  Future<bool> startBroadcasting(String sessionId, String mode) async {
    if (_isTransmitting) {
      return false; // Already transmitting
    }

    try {
      // Request permissions
      var status = await Permission.bluetoothAdvertise.request();
      if (!status.isGranted) {
        _logger.w('Bluetooth advertise permission not granted');
        return false;
      }

      // Also need location permission for some devices
      status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        _logger.w('Location permission not granted');
        return false;
      }

      // Check if user is authorized for this session
      final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
      if (!sessionDoc.exists) {
        _logger.e('Session does not exist: $sessionId');
        return false;
      }

      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      final currentUserUid = _auth.currentUser?.uid;
      if (currentUserUid != sessionData['lecturerEmail']) {
        _logger.e('User not authorized for this session');
        return false;
      }

      // Check if session is active
      final now = Timestamp.now();
      final startTime = sessionData['startTime'] as Timestamp?;
      final endTime = sessionData['endTime'] as Timestamp?;

      if (startTime == null || endTime == null ||
          now.compareTo(startTime) < 0 || now.compareTo(endTime) > 0) {
        _logger.e('Session not active');
        return false;
      }

      // Generate a UUID for the beacon
      final beaconId = _generateBeaconId(sessionId, mode);

      // Update Firestore with the beacon ID
      await _firestore.collection('sessions').doc(sessionId).update({
        'beaconId': beaconId,
        'beaconMode': mode, // This is optional if you want to track mode in Firestore
        'beaconUpdatedAt': FieldValue.serverTimestamp(),
      });

      // Configure beacon broadcast
      await _beaconBroadcast.setUUID(beaconId);
      await _beaconBroadcast.setMajorId(1);
      await _beaconBroadcast.setMinorId(100);
      await _beaconBroadcast.setIdentifier('attendance.lecturer.beacon');
      await _beaconBroadcast.setTransmissionPower(-59); // Default power
      await _beaconBroadcast.setManufacturerId(0x004C);
      await _beaconBroadcast.setLayout('m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24');

      // Start broadcasting
      await _beaconBroadcast.start();
      
      _isTransmitting = true;
      _currentSessionId = sessionId;
      
      _logger.i('Started broadcasting beacon for session $sessionId in $mode mode');
      return true;
    } catch (e) {
      _logger.e('Error starting beacon broadcast: $e');
      return false;
    }
  }

  /// Stop broadcasting the BLE beacon
  Future<bool> stopBroadcasting() async {
    if (!_isTransmitting || _currentSessionId == null) {
      return false; // Not transmitting
    }

    try {
      // Stop broadcasting
      await _beaconBroadcast.stop();
      
      // Remove beacon ID from Firestore
      if (_currentSessionId != null) {
        await _firestore.collection('sessions').doc(_currentSessionId).update({
          'beaconId': FieldValue.delete(),
          'beaconMode': FieldValue.delete(),
          'beaconUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
      
      _isTransmitting = false;
      _currentSessionId = null;
      
      _logger.i('Stopped broadcasting beacon');
      return true;
    } catch (e) {
      _logger.e('Error stopping beacon broadcast: $e');
      return false;
    }
  }

  /// Generate a beacon ID based on session ID and mode
  String _generateBeaconId(String sessionId, String mode) {
    // Use a deterministic UUID based on session and mode
    // This ensures the same UUID is generated for the same session+mode
    final baseUuid = '74278BDA-B644-4520-8F0C-720EAF059935'; // Base UUID
    
    // Simple deterministic transformation based on session ID and mode
    // In production, use a more sophisticated algorithm
    final modeDigit = mode.toLowerCase() == 'entry' ? '1' : '2';
    final truncatedSessionId = sessionId.substring(0, math.min(8, sessionId.length));
    final modifiedUuid = baseUuid.replaceRange(9, 13, '$modeDigit$truncatedSessionId');
    
    return modifiedUuid;
  }

  /// Start scanning for BLE beacons for nearby sessions
  Future<bool> startScanning({
    required Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconDetected,
    required Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconThresholdMet,
    required Function() onBeaconLost,
  }) async {
    try {
      // Initialize flutter_beacon
      await flutterBeacon.initializeScanning;
      
      // Request permissions
      var status = await Permission.bluetoothScan.request();
      if (!status.isGranted) {
        _logger.w('Bluetooth scan permission not granted');
        return false;
      }

      // Also need location permission
      status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        _logger.w('Location permission not granted');
        return false;
      }

      // Get all active sessions with beacon IDs
      final now = Timestamp.now();
      final sessionsSnapshot = await _firestore
          .collection('sessions')
          .where('startTime', isLessThanOrEqualTo: now)
          .where('endTime', isGreaterThanOrEqualTo: now)
          .where('beaconId', isNull: false)
          .get();
      
      if (sessionsSnapshot.docs.isEmpty) {
        _logger.e('No active sessions with beacons found');
        return false;
      }
      
      // Create a map of beacon IDs to session data for lookup during scanning
      final beaconSessions = <String, Map<String, dynamic>>{};
      for (final doc in sessionsSnapshot.docs) {
        final data = doc.data();
        final beaconId = data['beaconId'] as String?;
        if (beaconId != null) {
          beaconSessions[beaconId] = {
            ...data,
            'sessionId': doc.id,
          };
        }
      }
      
      if (beaconSessions.isEmpty) {
        _logger.e('No beacon IDs found in active sessions');
        return false;
      }

      // Reset detection state
      _isBeaconDetected = false;
      _hasMetDetectionThreshold = false;
      _firstDetectionTime = null;
      
      // Create regions to scan for - one for each beacon ID
      final regions = beaconSessions.keys.map((uuid) => Region(
        identifier: 'attendance.student.scanner.$uuid',
        proximityUUID: uuid,
      )).toList();

      // Variables to track which session we've detected
      String? detectedSessionId;
      String? detectedMode;
      Map<String, dynamic>? detectedSessionData;

      // Start ranging
      _rangingSubscription = flutterBeacon.ranging(regions).listen(
        (RangingResult result) {
          // Check if any beacons detected
          final beacons = result.beacons;
          final wasDetected = _isBeaconDetected;
          _isBeaconDetected = beacons.isNotEmpty;
          
          // Handle detection logic
          if (_isBeaconDetected) {
            // Get the nearest beacon
            final nearestBeacon = beacons.first;
            
            // Find the session data for this beacon
            final foundSession = beaconSessions[nearestBeacon.proximityUUID];
            
            if (foundSession != null) {
              detectedSessionId = foundSession['sessionId'];
              detectedMode = foundSession['beaconMode'] ?? 'entry';
              detectedSessionData = foundSession;
              
              if (!wasDetected) {
                _logger.i('Beacon detected for session: $detectedSessionId, mode: $detectedMode');
                _firstDetectionTime = DateTime.now();
                
                // Notify about beacon detection
                onBeaconDetected(detectedSessionId!, detectedMode!, detectedSessionData!);
              }
              
              // Check if detection threshold is met
              if (_firstDetectionTime != null) {
                final detectionDuration = DateTime.now().difference(_firstDetectionTime!).inMilliseconds / 1000.0;
                if (detectionDuration >= _detectionThresholdInSeconds && !_hasMetDetectionThreshold) {
                  _hasMetDetectionThreshold = true;
                  _logger.i('Beacon detection threshold met: $detectionDuration seconds');
                  
                  // Start grace period timer for NFC scanning
                  _startGracePeriod(detectedSessionId!, detectedMode!, detectedSessionData!, onBeaconLost);
                  
                  // Notify listeners that beacon threshold is met
                  onBeaconThresholdMet(detectedSessionId!, detectedMode!, detectedSessionData!);
                }
              }
            }
          } else {
            // Reset detection if beacon lost before threshold
            if (_firstDetectionTime != null && !_hasMetDetectionThreshold) {
              _firstDetectionTime = null;
            }
            
            // Reset detected session
            detectedSessionId = null;
            detectedMode = null;
            detectedSessionData = null;
            
            // Notify listeners that beacon is not detected
            if (wasDetected) {
              onBeaconLost();
            }
          }
        },
        onError: (error) {
          _logger.e('Error ranging beacons: $error');
          onBeaconLost();
        },
      );
      
      _logger.i('Started scanning for ${regions.length} beacons');
      return true;
    } catch (e) {
      _logger.e('Error starting beacon scanning: $e');
      return false;
    }
  }

  /// Start the grace period timer for NFC scanning
  void _startGracePeriod(String sessionId, String mode, Map<String, dynamic> sessionData, Function onBeaconLost) {
    // Cancel existing timer if any
    _detectionTimer?.cancel();
    
    // Start a new timer
    _detectionTimer = Timer(Duration(seconds: _scanGracePeriodInSeconds.toInt()), () {
      // If grace period expires, reset detection state
      _hasMetDetectionThreshold = false;
      _firstDetectionTime = null;
      _beaconDetectedController.add(false);
      onBeaconLost();
      _logger.i('Scan grace period expired');
    });
  }

  /// Stop scanning for BLE beacons
  Future<void> stopScanning() async {
    // Cancel subscription
    await _rangingSubscription?.cancel();
    _rangingSubscription = null;
    
    // Cancel timer
    _detectionTimer?.cancel();
    _detectionTimer = null;
    
    // Reset state
    _isBeaconDetected = false;
    _hasMetDetectionThreshold = false;
    _firstDetectionTime = null;
    
    _logger.i('Stopped scanning for beacons');
  }

  /// Check if beacon detection threshold has been met
  bool hasMetDetectionThreshold() {
    return _hasMetDetectionThreshold;
  }

  /// Dispose method to clean up resources
  void dispose() {
    stopBroadcasting();
    stopScanning();
    _beaconDetectedController.close();
  }
}
