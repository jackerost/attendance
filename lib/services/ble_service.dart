import 'dart:async';

import 'package:dchs_flutter_beacon/dchs_flutter_beacon.dart' as flutter_beacon hide BeaconBroadcast;
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
  StreamSubscription<flutter_beacon.RangingResult>? _rangingSubscription;
  Timer? _detectionTimer;
  Timer? _proximityLostTimer;
  bool _isBeaconDetected = false;
  bool _hasMetDetectionThreshold = false;
  DateTime? _firstDetectionTime;
  DateTime? _lastDetectionTime;
  
  // Constants
  final double _detectionThresholdInSeconds = 1.0;  // Changed from 1.5 to 1.0 second
  final double _scanGracePeriodInSeconds = 10.0;
  final double _proximityWindowInSeconds = 10.0; // Proximity tracking window
  
  /// Start broadcasting a BLE beacon for a specific session and mode
  Future<bool> startBroadcasting(String sessionId, String mode) async {
    if (_isTransmitting) {
      return false; // Already transmitting
    }

    try {
      // Check for Bluetooth permissions
      if (await Permission.bluetooth.isDenied ||
          await Permission.bluetoothAdvertise.isDenied || 
          await Permission.bluetoothConnect.isDenied ||
          await Permission.locationWhenInUse.isDenied) {
        
        // Request all required Bluetooth permissions
        Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetooth,
          Permission.bluetoothAdvertise,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
        
        // Check if any permission was denied
        if (statuses.values.any((status) => !status.isGranted)) {
          _logger.w('Bluetooth or location permissions not granted: $statuses');
          return false;
        }
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

      // Get the fixed app beacon UUID
      final beaconId = _generateBeaconId(sessionId, mode);
      
      // Calculate lecturer-specific major ID
      final lecturerMajor = _getLecturerMajor();
      
      // Calculate session-specific minor ID
      final sessionMinor = _getSessionMinor(sessionId, mode);

      // Update Firestore with the beacon ID and identifiers
      await _firestore.collection('sessions').doc(sessionId).update({
        'beaconId': beaconId,
        'beaconMajor': lecturerMajor,
        'beaconMinor': sessionMinor,
        'beaconMode': mode,
        'beaconUpdatedAt': FieldValue.serverTimestamp(),
      });

      // Configure beacon broadcast
      await _beaconBroadcast.setUUID(beaconId);
      await _beaconBroadcast.setMajorId(lecturerMajor);
      await _beaconBroadcast.setMinorId(sessionMinor);
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

  // Timer for delaying Firestore updates when stopping broadcast
  Timer? _broadcastGracePeriodTimer;
  
  /// Stop broadcasting the BLE beacon
  Future<bool> stopBroadcasting() async {
    if (!_isTransmitting || _currentSessionId == null) {
      return false; // Not transmitting
    }

    try {
      // Stop broadcasting
      await _beaconBroadcast.stop();
      
      // Keep session ID before setting it to null
      final sessionId = _currentSessionId;
      
      _isTransmitting = false;
      _currentSessionId = null;
      
      // Cancel any existing grace period timer
      _broadcastGracePeriodTimer?.cancel();
      
      // Add a grace period before removing beacon fields from Firestore
      _broadcastGracePeriodTimer = Timer(Duration(seconds: _scanGracePeriodInSeconds.toInt()), () async {
        try {
          // Remove beacon ID from Firestore after grace period
          if (sessionId != null) {
            await _firestore.collection('sessions').doc(sessionId).update({
              'beaconId': FieldValue.delete(),
              'beaconMode': FieldValue.delete(),
              'beaconUpdatedAt': FieldValue.serverTimestamp(),
            });
            _logger.i('Removed beacon fields from Firestore after grace period');
          }
        } catch (e) {
          _logger.e('Error updating Firestore after grace period: $e');
        }
      });
      
      _logger.i('Stopped broadcasting beacon (Firestore update delayed)');
      return true;
    } catch (e) {
      _logger.e('Error stopping beacon broadcast: $e');
      return false;
    }
  }

  /// Fixed app UUID for all beacons
  static const String _APP_BEACON_UUID = '74278BDA-B644-4520-8F0C-720EAF059935';
  
  /// Generate a beacon ID based on session ID and mode
  String _generateBeaconId(String sessionId, String mode) {
    // Always return the fixed app UUID - unchanged and valid format
    return _APP_BEACON_UUID;
  }
  
  /// Generate major ID based on lecturer UID
  int _getLecturerMajor() {
    final currentUserUid = _auth.currentUser?.uid;
    // Generate a stable 16-bit hash from the lecturer's UID
    return (currentUserUid?.hashCode ?? 0) & 0xFFFF;
  }
  
  /// Generate minor ID based on session and mode
  int _getSessionMinor(String sessionId, String mode) {
    // Use 15 bits for session hash, highest bit for mode
    final sessionBits = sessionId.hashCode & 0x7FFF;  // Lower 15 bits
    final modeBit = (mode.toLowerCase() == 'exit') ? 0x8000 : 0;  // Highest bit
    return sessionBits | modeBit;
  }

  /// Start scanning for BLE beacons for nearby sessions
  Future<bool> startScanning({
    required Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconDetected,
    required Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconThresholdMet,
    required Function() onBeaconLost,
  }) async {
    try {
      // Initialize beacon scanning
      await flutter_beacon.flutterBeacon.initializeScanning;
      
      // Check for Bluetooth scanning permissions
      if (await Permission.bluetooth.isDenied ||
          await Permission.bluetoothScan.isDenied || 
          await Permission.bluetoothConnect.isDenied ||
          await Permission.locationWhenInUse.isDenied) {
        
        // Request all required Bluetooth permissions
        Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetooth,
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();
        
        // Check if any permission was denied
        if (statuses.values.any((status) => !status.isGranted)) {
          _logger.w('Bluetooth or location permissions not granted: $statuses');
          return false;
        }
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
      
      // Create a map of sessions data for lookup during scanning
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
        _logger.e('No active sessions with beacons found');
        return false;
      }

      // Reset detection state
      _isBeaconDetected = false;
      _hasMetDetectionThreshold = false;
      _firstDetectionTime = null;
      _lastDetectionTime = null;
      
      // Cancel any existing timers
      _proximityLostTimer?.cancel();
      _proximityLostTimer = null;
      
      // Create a region for our app UUID - we only need one region since we use the same UUID
      final regions = [flutter_beacon.Region(
        identifier: 'attendance.student.scanner',
        proximityUUID: _APP_BEACON_UUID,
      )];

      // Variables to track which session we've detected
      String? detectedSessionId;
      String? detectedMode;
      Map<String, dynamic>? detectedSessionData;

      // Start ranging
      _rangingSubscription = flutter_beacon.flutterBeacon.ranging(regions).listen(
        (flutter_beacon.RangingResult result) {
          // Check if any beacons detected
          final beacons = result.beacons;
          final wasDetected = _isBeaconDetected;
          _isBeaconDetected = beacons.isNotEmpty;
          
          // Record the current time whenever we detect beacons
          if (_isBeaconDetected) {
            _lastDetectionTime = DateTime.now();
            
            // Cancel any pending proximity lost timer as we're getting a signal
            _proximityLostTimer?.cancel();
            _proximityLostTimer = null;
          }
          
          // Handle detection logic
          if (_isBeaconDetected) {
            // Get the nearest beacon
            final nearestBeacon = beacons.first;
            
            // Find the session data based on major and minor
            final foundSession = activeSessions.firstWhere(
              (session) => 
                session['beaconMajor'] == nearestBeacon.major && 
                session['beaconMinor'] == nearestBeacon.minor,
              orElse: () => <String, dynamic>{},
            );
            
            if (foundSession.isNotEmpty) {
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
                  
                  // Notify that threshold is met
                  onBeaconThresholdMet(detectedSessionId!, detectedMode!, detectedSessionData!);
                }
              }
            }
          } else {
            // If beacon is not detected, start a proximity lost timer
            // only if we previously had detected a beacon AND met the threshold
            if (wasDetected && _hasMetDetectionThreshold && _proximityLostTimer == null) {
              _logger.i('📡 Signal temporarily lost, starting proximity window timer (${_proximityWindowInSeconds}s)');
              _proximityLostTimer = Timer(Duration(seconds: _proximityWindowInSeconds.toInt()), () {
                _logger.i('📡 Proximity window expired - no signal detected within ${_proximityWindowInSeconds} seconds');
                // Only reset if we haven't detected a new signal during this time
                if (!_isBeaconDetected) {
                  _hasMetDetectionThreshold = false;
                  _firstDetectionTime = null;
                  onBeaconLost();
                }
              });
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

  // Removed unused _startGracePeriod method

  /// Stop scanning for BLE beacons
  Future<void> stopScanning() async {
    // Cancel subscription
    await _rangingSubscription?.cancel();
    _rangingSubscription = null;
    
    // Cancel all timers
    _detectionTimer?.cancel();
    _detectionTimer = null;
    
    _proximityLostTimer?.cancel();
    _proximityLostTimer = null;
    
    // Reset state
    _isBeaconDetected = false;
    _hasMetDetectionThreshold = false;
    _firstDetectionTime = null;
    _lastDetectionTime = null;
    
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
    _broadcastGracePeriodTimer?.cancel();
    _detectionTimer?.cancel();
    _beaconDetectedController.close();
  }
}
