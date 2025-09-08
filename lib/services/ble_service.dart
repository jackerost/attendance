import 'dart:async';
import 'dart:io';
import 'dart:math';

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
  
  // SECURITY MODEL: Heartbeat-Only Approach with Optimized Student Scanning
  // - No beaconId cleanup queries needed (saves Firestore reads)
  // - Stale beacons expire naturally when heartbeat gets old (>30s)
  // - Students reject beacons with stale heartbeats in real-time
  // - Rolling minor + heartbeat provide full security without cleanup costs
  // - OPTIMIZATION: Students scan only for their enrolled session (1 Firestore read vs many)
  // - Context-aware scanning: Student knows which session they should attend

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
  StreamSubscription<DocumentSnapshot>? _sessionListenerSubscription;
  Timer? _detectionTimer;
  Timer? _proximityLostTimer;
  Timer? _scanTimeoutTimer;
  Timer? _backupLostTimer;
  bool _isBeaconDetected = false;
  bool _hasMetDetectionThreshold = false;
  DateTime? _firstDetectionTime;
  
  // Real-time beacon minor tracking
  Map<String, dynamic>? _realtimeSessionData;
  
  // Rolling identifier state
  Timer? _rollingIdTimer;
  // Removed _heartbeatTimer - now combined with rotation timer
  
  // Constants - Optimized for lowest latency
  final double _detectionThresholdInSeconds = 0.1;  // Reduced to 100ms for faster detection
  final double _scanGracePeriodInSeconds = 10.0;
  final double _proximityWindowInSeconds = 5.0; // Reduced window for faster lost detection
  final Duration _scanTimeoutDuration = Duration(seconds: 5); // Auto-restart scan after timeout
  final Duration _minorValidationGracePeriod = Duration(seconds: 2); // Grace period for minor validation
  /// Generates random minor ID pool for centralized beacon rotation
  List<int> _generateRandomMinorPool(int poolSize) {
    final random = Random.secure();
    final pool = <int>[];
    
    // Generate unique random minors (avoiding duplicates)
    while (pool.length < poolSize) {
      final minor = random.nextInt(65535); // 16-bit range
      if (!pool.contains(minor)) {
        pool.add(minor);
      }
    }
    
    return pool;
  }
  
  /// Initializes centralized beacon rotation system in Firestore
  Future<void> _initializeCentralizedBeaconRotation(String sessionId) async {
    try {
      // Generate random minor pool
      final minorPool = _generateRandomMinorPool(10); // 10 random minors for security
      
      // Initialize beacon state in Firestore
      await _firestore.collection('sessions').doc(sessionId).update({
        'beaconMinorCurrent': minorPool[0],
        'beaconMinorPool': minorPool,
        'beaconPoolIndex': 0,
        'beaconIsRotating': true,
        'beaconLastRotated': FieldValue.serverTimestamp(),
        'beaconRotationInterval': 10000, // 10 seconds
      });
      
      _logger.i('🔧 Initialized centralized beacon rotation with ${minorPool.length} random minors');
      _logger.i('🎯 Starting minor: ${minorPool[0]}');
    } catch (e) {
      _logger.e('Error initializing centralized beacon rotation: $e');
    }
  }
  
  /// Rotates to next random minor in pool (lecturer's phone handles this)
  Future<void> _rotateCentralizedBeaconMinor(String sessionId) async {
    if (!_isTransmitting) return;
    
    try {
      final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
      if (!sessionDoc.exists) return;
      
      final data = sessionDoc.data()!;
      final minorPool = List<int>.from(data['beaconMinorPool'] ?? []);
      final currentIndex = data['beaconPoolIndex'] as int? ?? 0;
      
      if (minorPool.isEmpty) return;
      
      // Move to next minor in pool (circular)
      final nextIndex = (currentIndex + 1) % minorPool.length;
      final nextMinor = minorPool[nextIndex];
      
      // Update the actual beacon broadcast FIRST (before Firestore)
      _logger.i('🔧 Updating beacon minor ID to: $nextMinor');
      _beaconBroadcast.setMinorId(nextMinor);
      
      // Then update Firestore with new minor AND heartbeat timestamp
      await _firestore.collection('sessions').doc(sessionId).update({
        'beaconMinorCurrent': nextMinor,
        'beaconPoolIndex': nextIndex,
        'beaconLastRotated': FieldValue.serverTimestamp(),
        'beaconUpdatedAt': FieldValue.serverTimestamp(), // Combined heartbeat update
      });
      
      _logger.i('🔄 Rotated beacon minor to: $nextMinor (index: $nextIndex/${minorPool.length})');
    } catch (e) {
      _logger.e('Error rotating centralized beacon minor: $e');
    }
  }
  
  /// Validates beacon minor against current real-time state (with grace period for rotations)
  Future<bool> _isValidCentralizedBeaconMinor(int detectedMinor, String sessionId) async {
    try {
      // First try to use real-time data to avoid timing issues
      final currentMinor = _realtimeSessionData?['beaconMinorCurrent'] as int?;
      
      if (currentMinor != null) {
        final isValid = detectedMinor == currentMinor;
        if (isValid) {
          _logger.d('✅ Centralized beacon minor validation passed: $detectedMinor (real-time data)');
          return true;
        } else {
          _logger.w('❌ Current minor mismatch: detected=$detectedMinor, expected=$currentMinor (real-time data)');
          
          // GRACE PERIOD: Check if detected minor was recently valid
          final isRecentlyValid = await _isMinorRecentlyValid(detectedMinor, sessionId);
          if (isRecentlyValid) {
            _logger.i('✅ Grace period validation passed: $detectedMinor was recently valid');
            return true;
          }
          
          // CRITICAL: If grace period fails, immediately fetch fresh data to check if real-time is stale
          _logger.i('🔄 Grace period failed, fetching absolute latest beacon data for verification...');
          
          try {
            final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
            if (sessionDoc.exists) {
              final freshData = sessionDoc.data()!;
              final freshMinor = freshData['beaconMinorCurrent'] as int?;
              
              _logger.i('🔍 Fresh Firestore beaconMinorCurrent: $freshMinor');
              _logger.i('🔍 Real-time data had: $currentMinor');
              _logger.i('🔍 Detected beacon minor: $detectedMinor');
              
              if (freshMinor != null) {
                // Update real-time data with fresh data
                _realtimeSessionData = freshData;
                
                final freshIsValid = detectedMinor == freshMinor;
                if (freshIsValid) {
                  _logger.i('✅ Centralized beacon minor validation passed after refresh: $detectedMinor (fresh Firestore data)');
                } else {
                  // Check grace period again with fresh data
                  final freshGraceValid = await _isMinorRecentlyValid(detectedMinor, sessionId);
                  if (freshGraceValid) {
                    _logger.i('✅ Grace period validation passed after refresh: $detectedMinor was recently valid');
                    return true;
                  } else {
                    _logger.w('❌ Centralized beacon minor validation failed after refresh and grace period: detected=$detectedMinor, expected=$freshMinor');
                  }
                }
                return freshIsValid;
              }
            }
          } catch (e) {
            _logger.e('Error fetching fresh beacon data for validation: $e');
          }
          
          return false;
        }
      } else {
        // Fallback to direct Firestore query if real-time data not available
        _logger.w('⚠️ Real-time session data not available, falling back to direct Firestore query');
        
        final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
        if (!sessionDoc.exists) {
          _logger.w('❌ Session document not found during fallback validation');
          return false;
        }
        
        final sessionData = sessionDoc.data()!;
        final fallbackCurrentMinor = sessionData['beaconMinorCurrent'] as int?;
        
        if (fallbackCurrentMinor == null) {
          _logger.w('❌ No beaconMinorCurrent found in session data');
          return false;
        }
        
        // Update real-time data with fetched data to avoid future fallbacks
        _realtimeSessionData = sessionData;
        
        final isValid = detectedMinor == fallbackCurrentMinor;
        if (isValid) {
          _logger.d('✅ Centralized beacon minor validation passed: $detectedMinor (fallback Firestore data)');
        } else {
          // Check grace period with fallback data
          final graceValid = await _isMinorRecentlyValid(detectedMinor, sessionId);
          if (graceValid) {
            _logger.i('✅ Grace period validation passed: $detectedMinor was recently valid (fallback)');
            return true;
          } else {
            _logger.w('❌ Centralized beacon minor validation failed: detected=$detectedMinor, expected=$fallbackCurrentMinor (fallback Firestore data)');
          }
        }
        
        return isValid;
      }
    } catch (e) {
      _logger.e('Error validating centralized beacon minor: $e');
      return false;
    }
  }
  
  /// Check if a minor ID was recently valid (within grace period)
  Future<bool> _isMinorRecentlyValid(int detectedMinor, String sessionId) async {
    try {
      // Get the current session data to check beacon pool and rotation history
      final sessionData = _realtimeSessionData ?? 
          (await _firestore.collection('sessions').doc(sessionId).get()).data();
      
      if (sessionData == null) return false;
      
      // Check if detected minor is in the current pool (could be a previous minor)
      final minorPool = List<int>.from(sessionData['beaconMinorPool'] ?? []);
      if (!minorPool.contains(detectedMinor)) {
        _logger.d('🔍 Grace period check: $detectedMinor not in current pool $minorPool');
        return false;
      }
      
      // Check if the last rotation was recent (within grace period)
      final lastRotated = sessionData['beaconLastRotated'] as Timestamp?;
      if (lastRotated == null) {
        _logger.d('🔍 Grace period check: No rotation timestamp found');
        return false;
      }
      
      final timeSinceRotation = DateTime.now().difference(lastRotated.toDate());
      final isWithinGracePeriod = timeSinceRotation <= _minorValidationGracePeriod;
      
      _logger.d('🔍 Grace period check: time since rotation=${timeSinceRotation.inMilliseconds}ms, grace period=${_minorValidationGracePeriod.inMilliseconds}ms, valid=$isWithinGracePeriod');
      
      return isWithinGracePeriod;
    } catch (e) {
      _logger.e('Error checking minor grace period: $e');
      return false;
    }
  }
  
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
      
      // Initialize centralized beacon rotation system
      await _initializeCentralizedBeaconRotation(sessionId);
      
      // Get the initial minor from the pool
      final updatedSessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
      final updatedSessionData = updatedSessionDoc.data()!;
      final initialMinor = updatedSessionData['beaconMinorCurrent'] as int;

      // Update Firestore with the beacon ID and identifiers
      await _firestore.collection('sessions').doc(sessionId).update({
        'beaconId': beaconId,
        'beaconMajor': lecturerMajor,
        // Removed beaconMinor - using centralized beaconMinorCurrent instead
        'beaconMode': mode,
        'beaconUpdatedAt': FieldValue.serverTimestamp(),
      });

      // Configure beacon broadcast with optimized settings for lowest latency
      _beaconBroadcast.setUUID(beaconId);
      _beaconBroadcast.setMajorId(lecturerMajor);
      _beaconBroadcast.setMinorId(initialMinor);
      _beaconBroadcast.setIdentifier('attendance.lecturer.beacon');
      _beaconBroadcast.setTransmissionPower(-59); // Default power
      _beaconBroadcast.setManufacturerId(0x004C);
      _beaconBroadcast.setLayout('m:2-3=0215,i:4-19,i:20-21,i:22-23,p:24-24');
      
      // Platform-specific optimizations for lowest latency
      if (Platform.isAndroid) {
        // Use low latency mode on Android for fastest advertising
        _beaconBroadcast.setAdvertiseMode(AdvertiseMode.lowLatency);
      }
      // iOS automatically uses optimal settings through CoreBluetooth/CoreLocation

      // Start broadcasting
      await _beaconBroadcast.start();
      
      // Start centralized rotation timer (lecturer's phone updates Firestore every 10 seconds)
      // This now includes heartbeat updates to reduce Firestore writes
      _rollingIdTimer?.cancel();
      _rollingIdTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        await _rotateCentralizedBeaconMinor(sessionId);
      });
      
      // Removed separate heartbeat timer - now combined with rotation updates
      
      _isTransmitting = true;
      _currentSessionId = sessionId;
      
      _logger.i('Started broadcasting beacon for session $sessionId in $mode mode with rolling identifiers');
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
      
      // Cancel rotation timer
      _rollingIdTimer?.cancel();
      // Removed heartbeat timer - now combined with rotation
      _rollingIdTimer = null;
      
      // Keep session ID before setting it to null
      final sessionId = _currentSessionId;
      
      _isTransmitting = false;
      _currentSessionId = null;
      
      // Stop centralized rotation immediately
      if (sessionId != null) {
        try {
          await _firestore.collection('sessions').doc(sessionId).update({
            'beaconIsRotating': false,
          });
          _logger.i('🛑 Stopped centralized beacon rotation for session: $sessionId');
        } catch (e) {
          _logger.w('Error stopping beacon rotation: $e');
        }
      }
      
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
  
  /// Start scanning for BLE beacons for the student's current active session
  Future<bool> startScanning({
    required Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconDetected,
    required Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconThresholdMet,
    required Function() onBeaconLost,
  }) async {
    try {
      // Initialize beacon scanning with optimized settings
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

      // OPTIMIZED: Get student's enrolled sections first
      final currentUserEmail = _auth.currentUser?.email;
      if (currentUserEmail == null) {
        _logger.e('❌ User not authenticated or email not found');
        return false;
      }
      
      _logger.i('🔍 Looking up student enrollment for email: $currentUserEmail');
      
      // Query student by email (same approach as student_self_scan_page)
      final studentSnapshot = await _firestore
          .collection('students')
          .where('email', isEqualTo: currentUserEmail)
          .limit(1)
          .get();
          
      if (studentSnapshot.docs.isEmpty) {
        _logger.e('❌ Student document not found for email: $currentUserEmail');
        return false;
      }
      
      final studentDoc = studentSnapshot.docs.first;
      final studentData = studentDoc.data();
      final enrolledSections = List<String>.from(studentData['enrolledSections'] ?? []);
      
      _logger.i('📚 Student document found: ${studentDoc.id}');
      _logger.i('📚 Student name: ${studentData['name'] ?? 'Unknown'}');
      _logger.i('📚 Enrolled sections (${enrolledSections.length}): $enrolledSections');
      
      if (enrolledSections.isEmpty) {
        _logger.e('❌ Student not enrolled in any sections');
        return false;
      }

      // OPTIMIZED: Find the ONE active session from student's enrolled sections
      final now = Timestamp.now();
      _logger.i('🕐 Current time: ${now.toDate()}');
      _logger.i('🔍 Searching for active sessions in enrolled sections...');
      
      late QuerySnapshot<Map<String, dynamic>> activeSessionSnapshot;
      try {
        // Use single != filter for beaconId and filter beaconMinorCurrent client-side
        activeSessionSnapshot = await _firestore
            .collection('sessions')
            .where('sectionId', whereIn: enrolledSections)
            .where('startTime', isLessThanOrEqualTo: now)
            .where('endTime', isGreaterThanOrEqualTo: now)
            .where('beaconId', isNull: false) // Only one != filter allowed
            .get();
        
        // Client-side filter for beaconMinorCurrent not null
        final validDocs = activeSessionSnapshot.docs.where((doc) {
          final data = doc.data();
          return data['beaconMinorCurrent'] != null;
        }).toList();
        
        _logger.i('📊 Query completed. Found ${activeSessionSnapshot.docs.length} sessions with beaconId, ${validDocs.length} also have beaconMinorCurrent');
        
        if (validDocs.isEmpty) {
          _logger.e('❌ No active session found with both beaconId and beaconMinorCurrent for enrolled sections: $enrolledSections');
          
          // Continue with debug info...
          _logger.i('🔍 Debugging: Checking all active sessions with beacons...');
          final debugSnapshot = await _firestore
              .collection('sessions')
              .where('startTime', isLessThanOrEqualTo: now)
              .where('endTime', isGreaterThanOrEqualTo: now)
              .where('beaconId', isNull: false)
              .get();
          
          _logger.i('📊 All active sessions with beacons (${debugSnapshot.docs.length}):');
          for (final doc in debugSnapshot.docs) {
            final data = doc.data();
            final startTime = (data['startTime'] as Timestamp?)?.toDate();
            final endTime = (data['endTime'] as Timestamp?)?.toDate();
            _logger.i('   📅 Session ${doc.id}:');
            _logger.i('      - Section: "${data['sectionId']}"');
            _logger.i('      - Course: "${data['courseId']}"'); 
            _logger.i('      - Lecturer: "${data['lecturerEmail']}"');
            _logger.i('      - Time: ${startTime?.toString()} - ${endTime?.toString()}');
            _logger.i('      - Beacon ID: "${data['beaconId']}"');
            _logger.i('      - Beacon Major: ${data['beaconMajor']}');
            _logger.i('      - Beacon Minor Current: ${data['beaconMinorCurrent']}');
            _logger.i('      - Beacon Minor Pool: ${data['beaconMinorPool']}');
          }
          return false;
        }
        
        // Use the first valid session
        final targetSessionDoc = validDocs.first;
        
        _logger.i('✅ Found active session for student');
        
        // Get the single active session data
        final sessionDoc = targetSessionDoc;
        final sessionData = sessionDoc.data();
        
        _logger.i('📋 Active session details:');
        _logger.i('   - Session ID: ${sessionDoc.id}');
        _logger.i('   - Section ID: ${sessionData['sectionId']}');
        _logger.i('   - Course ID: ${sessionData['courseId']}');
        _logger.i('   - Lecturer UID: ${sessionData['lecturerEmail']}');
        _logger.i('   - Start Time: ${(sessionData['startTime'] as Timestamp?)?.toDate()}');
        _logger.i('   - End Time: ${(sessionData['endTime'] as Timestamp?)?.toDate()}');
        
        final targetSession = {
          ...sessionData,
          'sessionId': sessionDoc.id,
        };
        
        final beaconId = sessionData['beaconId'] as String?;
        final beaconMajor = sessionData['beaconMajor'] as int?;
        final beaconMinorCurrent = sessionData['beaconMinorCurrent'] as int?;
        final beaconMode = sessionData['beaconMode'] as String?;
        
        _logger.i('🚨 Beacon parameters:');
        _logger.i('   - Beacon ID: $beaconId');
        _logger.i('   - Beacon Major: $beaconMajor');
        _logger.i('   - Beacon Minor Current: $beaconMinorCurrent');
        _logger.i('   - Beacon Mode: $beaconMode');
        
        if (beaconId == null || beaconMajor == null || beaconMinorCurrent == null) {
          _logger.e('❌ Active session missing centralized beacon parameters - beaconId: $beaconId, beaconMajor: $beaconMajor, beaconMinorCurrent: $beaconMinorCurrent');
          return false;
        }
        
        _logger.i('✅ All beacon parameters validated. Starting BLE scanning...');

        // Get the latest beacon data before starting scan to ensure we have current beacon minor
        _logger.i('🔄 Fetching latest beacon data before starting scan...');
        try {
          final freshSessionDoc = await _firestore.collection('sessions').doc(targetSession['sessionId']).get();
          if (freshSessionDoc.exists) {
            final freshData = freshSessionDoc.data()!;
            
            // Log the data sources for debugging
            _logger.i('🔍 Original target session beaconMinorCurrent: ${targetSession['beaconMinorCurrent']}');
            _logger.i('🔍 Fresh Firestore beaconMinorCurrent: ${freshData['beaconMinorCurrent']}');
            
            // Force update target session with absolutely fresh data
            targetSession['beaconMinorCurrent'] = freshData['beaconMinorCurrent'];
            targetSession['beaconMinorPool'] = freshData['beaconMinorPool'];
            targetSession['beaconLastRotated'] = freshData['beaconLastRotated'];
            targetSession['beaconIsRotating'] = freshData['beaconIsRotating'];
            targetSession['beaconUpdatedAt'] = freshData['beaconUpdatedAt'];
            
            _logger.i('🔄 Force-updated target session with latest beacon data - Current minor: ${targetSession['beaconMinorCurrent']}');
          } else {
            _logger.w('⚠️ Session document not found when fetching fresh data');
          }
        } catch (e) {
          _logger.w('⚠️ Failed to fetch fresh beacon data before scan: $e');
        }

        // Set up real-time Firestore listener for beacon data updates
        _logger.i('📡 Setting up real-time beacon listener for session: ${targetSession['sessionId']}');
        await _setupRealtimeBeaconListener(targetSession['sessionId'], targetSession);

        // Reset detection state
        _isBeaconDetected = false;
        _hasMetDetectionThreshold = false;
        _firstDetectionTime = null;
        
        // Cancel any existing timers
        _proximityLostTimer?.cancel();
        _proximityLostTimer = null;
        
        // Create a region for our app UUID - we only need one region since we use the same UUID
        final regions = [flutter_beacon.Region(
          identifier: 'attendance.student.scanner',
          proximityUUID: _APP_BEACON_UUID,
        )];

        // Start ranging with optimized callback handling for the specific session
        _rangingSubscription = flutter_beacon.flutterBeacon.ranging(regions).listen(
          (flutter_beacon.RangingResult result) {
            // Process heavy async operations properly
            _processOptimizedRangingResult(
              result, 
              targetSession, 
              onBeaconDetected, 
              onBeaconThresholdMet, 
              onBeaconLost
            );
          },
          onError: (error) {
            _logger.e('Error ranging beacons: $error');
            onBeaconLost();
          },
        );
        
        // Start scan timeout timer - restart scan if no beacon detected within timeout
        _scanTimeoutTimer?.cancel();
        _scanTimeoutTimer = Timer(_scanTimeoutDuration, () async {
          if (!_isBeaconDetected) {
            _logger.i('⏰ Scan timeout reached with no beacon detected. Restarting scan...');
            await _restartScan(targetSession, onBeaconDetected, onBeaconThresholdMet, onBeaconLost);
          }
        });
        
        _logger.i('Started optimized scanning for session: ${targetSession['sessionId']}');
        return true;
      } catch (e) {
        _logger.e('❌ Firestore query failed: $e');
        return false;
      }
    } catch (e) {
      _logger.e('❌ Error starting beacon scanning: $e');
      return false;
    }
  }

  /// Set up real-time Firestore listener for beacon minor updates
  Future<void> _setupRealtimeBeaconListener(String sessionId, Map<String, dynamic> targetSession) async {
    // Cancel any existing listener
    _sessionListenerSubscription?.cancel();
    
    _logger.i('📡 Creating Firestore listener for session: $sessionId');
    
    // Initialize real-time data with current session data to avoid race condition
    _realtimeSessionData = Map<String, dynamic>.from(targetSession);
    _logger.i('📡 Pre-initialized real-time data with current session data - beaconMinorCurrent: ${_realtimeSessionData?['beaconMinorCurrent']}');
    
    // Set up real-time listener for session document
    _sessionListenerSubscription = FirebaseFirestore.instance
        .collection('sessions')
        .doc(sessionId)
        .snapshots()
        .listen(
      (DocumentSnapshot snapshot) {
        _logger.d('📡 Firestore listener triggered - exists: ${snapshot.exists}');
        if (snapshot.exists && snapshot.data() != null) {
          final freshData = snapshot.data() as Map<String, dynamic>;
          
          // Log before and after values for debugging
          final oldMinor = _realtimeSessionData?['beaconMinorCurrent'];
          final newMinor = freshData['beaconMinorCurrent'];
          
          // Update the realtime session data
          _realtimeSessionData = freshData;
          
          // Update target session with latest beacon data
          targetSession['beaconMinorCurrent'] = freshData['beaconMinorCurrent'];
          targetSession['beaconMinorPool'] = freshData['beaconMinorPool'];
          targetSession['beaconLastRotated'] = freshData['beaconLastRotated'];
          targetSession['beaconIsRotating'] = freshData['beaconIsRotating'];
          
          _logger.i('📡 Current beacon data: beaconMinorCurrent=${freshData['beaconMinorCurrent']}, beaconIsRotating=${freshData['beaconIsRotating']}');
          
          // Monitor for beacon broadcast stopping
          final beaconIsRotating = freshData['beaconIsRotating'] as bool?;
          if (beaconIsRotating == false && _hasMetDetectionThreshold) {
            _logger.i('📡 Detected that beacon broadcasting has stopped via real-time listener');
            // Give a short grace period then trigger lost detection if no beacons detected
            Timer(Duration(seconds: 2), () {
              if (!_isBeaconDetected && _hasMetDetectionThreshold) {
                _logger.i('📡 Beacon broadcasting stopped and no signals detected - triggering lost state');
                _hasMetDetectionThreshold = false;
                _firstDetectionTime = null;
                // Find the callback - we need to store it for this use case
                // For now, let the existing timer logic handle it
              }
            });
          }
          
          // Log beacon minor changes with more detail
          if (oldMinor != newMinor) {
            _logger.i('🔄 Real-time beacon minor update detected: ${oldMinor} → ${newMinor}');
            _logger.i('📊 Real-time session data fully updated: ${_realtimeSessionData?.keys.length} fields');
          }
        } else {
          _logger.w('⚠️ Session document not found in real-time listener');
        }
      },
      onError: (error) {
        _logger.e('❌ Error in real-time beacon listener: $error');
      },
    );
    
    // Wait a moment for the listener to potentially receive the first update
    await Future.delayed(Duration(milliseconds: 100));
    
    _logger.i('📡 Real-time beacon listener active for session: $sessionId');
  }

  /// Restart BLE scan after timeout to improve detection reliability
  Future<void> _restartScan(
    Map<String, dynamic> targetSession,
    Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconDetected,
    Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconThresholdMet,
    Function() onBeaconLost,
  ) async {
    try {
      // Stop current scan
      await _rangingSubscription?.cancel();
      _rangingSubscription = null;
      
      // Clear timeout timer
      _scanTimeoutTimer?.cancel();
      
      // Brief pause to let BLE stack reset
      await Future.delayed(Duration(milliseconds: 100));
      
      // No need to refresh beacon data - real-time listener keeps it current
      _logger.i('🔄 Restarting scan with real-time beacon data - Current minor: ${targetSession['beaconMinorCurrent']}');
      
      // Restart scan with same parameters
      final regions = [flutter_beacon.Region(
        identifier: 'attendance.student.scanner.restart',
        proximityUUID: _APP_BEACON_UUID,
      )];

      _rangingSubscription = flutter_beacon.flutterBeacon.ranging(regions).listen(
        (flutter_beacon.RangingResult result) {
          _processOptimizedRangingResult(
            result, 
            targetSession, 
            onBeaconDetected, 
            onBeaconThresholdMet, 
            onBeaconLost
          );
        },
        onError: (error) {
          _logger.e('Error ranging beacons after restart: $error');
          onBeaconLost();
        },
      );
      
      // Start new timeout timer
      _scanTimeoutTimer = Timer(_scanTimeoutDuration, () async {
        if (!_isBeaconDetected) {
          _logger.i('⏰ Scan restart timeout reached. Retrying scan restart...');
          await _restartScan(targetSession, onBeaconDetected, onBeaconThresholdMet, onBeaconLost);
        }
      });
      
      _logger.i('🔄 BLE scan restarted successfully');
    } catch (e) {
      _logger.e('Error restarting BLE scan: $e');
    }
  }

  /// Process ranging results for a specific target session (optimized approach)
  void _processOptimizedRangingResult(
    flutter_beacon.RangingResult result,
    Map<String, dynamic> targetSession,
    Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconDetected,
    Function(String sessionId, String mode, Map<String, dynamic> sessionData) onBeaconThresholdMet,
    Function() onBeaconLost,
  ) async {
    // Check if any beacons detected
    final beacons = result.beacons;
    final wasDetected = _isBeaconDetected;
    _isBeaconDetected = beacons.isNotEmpty;
    
    _logger.d('🔍 Ranging result: ${beacons.length} beacons detected');
    
    // Record the current time whenever we detect beacons
    if (_isBeaconDetected) {
      // Cancel any pending proximity lost timer as we're getting a signal
      _proximityLostTimer?.cancel();
      _proximityLostTimer = null;
      
      // Cancel scan timeout timer since beacon was detected
      _scanTimeoutTimer?.cancel();
      _scanTimeoutTimer = null;
      
      // Reset any backup lost detection timer
      _backupLostTimer?.cancel();
      _backupLostTimer = null;
    }
    
    // Handle detection logic
    if (_isBeaconDetected) {
      // Get the nearest beacon (beacons are sorted by proximity)
      final nearestBeacon = beacons.first;
      
      final sessionId = targetSession['sessionId'] as String;
      final mode = targetSession['beaconMode'] as String? ?? 'entry';
      final expectedMajor = targetSession['beaconMajor'] as int;
      
      _logger.d('📍 Nearest beacon - UUID: ${nearestBeacon.proximityUUID}, Major: ${nearestBeacon.major}, Minor: ${nearestBeacon.minor}, RSSI: ${nearestBeacon.rssi}');
      _logger.d('🎯 Expected for session $sessionId - Major: $expectedMajor, Mode: $mode');
      
      // OPTIMIZED: Direct match check - no loops needed
      bool isTargetBeacon = false;
      String rejectionReason = '';
      
      if (nearestBeacon.major == expectedMajor) {
        _logger.d('✅ Major ID matches expected: $expectedMajor');
        
        // Debug: Show what real-time data we're using for validation
        final realtimeMinor = _realtimeSessionData?['beaconMinorCurrent'];
        _logger.d('🔍 Using real-time beacon minor for validation: $realtimeMinor');
        
        // Validate centralized beacon minor ID for this specific session using real-time data
        final isValidMinor = await _isValidCentralizedBeaconMinor(nearestBeacon.minor, sessionId);
        if (isValidMinor) {
          _logger.d('✅ Centralized beacon minor validation passed for minor: ${nearestBeacon.minor}');
          isTargetBeacon = true;
        } else {
          rejectionReason = 'Centralized beacon minor validation failed for minor: ${nearestBeacon.minor}';
          _logger.w('❌ $rejectionReason');
        }
      } else {
        rejectionReason = 'Major ID mismatch - detected: ${nearestBeacon.major}, expected: $expectedMajor';
        _logger.w('❌ $rejectionReason');
      }
      
      if (isTargetBeacon) {
        _logger.d('🎯 Target beacon identified, checking proximity and liveness...');
        
        // ** Physical Proximity Check **
        // RSSI threshold to require students to be physically close
        // Generally, -75 to -90 is moderate distance, stronger (less negative) is closer
        final int rssiThreshold = -80;
        if (nearestBeacon.rssi < rssiThreshold) {
          _logger.w('❌ Signal strength too weak: ${nearestBeacon.rssi} dBm (threshold: $rssiThreshold dBm)');
          return; // Signal too weak, likely not physically present
        }
        _logger.d('✅ Proximity check passed. Signal strength: ${nearestBeacon.rssi} dBm');
        
        // ** Liveness Check **
        // Perform a single Firestore read to verify the heartbeat timestamp is fresh.
        final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
        final sessionData = sessionDoc.data();
        if (sessionData == null) {
          _logger.w('❌ Session was deleted mid-scan');
          return; // Session was deleted mid-scan
        }

        final lastHeartbeat = sessionData['beaconUpdatedAt'] as Timestamp?;
        if (lastHeartbeat == null) {
          _logger.w('❌ No heartbeat found in session data');
          return; // No heartbeat found
        }

        // The threshold should be slightly longer than the heartbeat interval
        // Increased from 27s to 35s to provide proper margin for Firestore delays
        final freshnessThreshold = const Duration(seconds: 35);
        final timeSinceHeartbeat = DateTime.now().difference(lastHeartbeat.toDate());

        if (timeSinceHeartbeat > freshnessThreshold) {
          _logger.w('❌ Stale beacon detected for session $sessionId. Time since heartbeat: ${timeSinceHeartbeat.inSeconds}s');
          return; // Stale beacon, ignore it
        }
        
        _logger.d('✅ Liveness check passed. Heartbeat age: ${timeSinceHeartbeat.inSeconds}s');
        
        // ** Liveness Check Passed **
        if (!wasDetected) {
          _logger.i('🎉 Target beacon detected for session: $sessionId, mode: $mode, RSSI: ${nearestBeacon.rssi}');
          _firstDetectionTime = DateTime.now();
          
          // Notify about beacon detection
          onBeaconDetected(sessionId, mode, targetSession);
        }
        
        // Check if detection threshold is met
        if (_firstDetectionTime != null) {
          final detectionDuration = DateTime.now().difference(_firstDetectionTime!).inMilliseconds / 1000.0;
          if (detectionDuration >= _detectionThresholdInSeconds && !_hasMetDetectionThreshold) {
            _hasMetDetectionThreshold = true;
            _logger.i('🏆 Target beacon detection threshold met: ${detectionDuration.toStringAsFixed(3)} seconds');
            
            // Notify that threshold is met
            onBeaconThresholdMet(sessionId, mode, targetSession);
          }
        }
      } else {
        _logger.d('❌ Beacon rejected: $rejectionReason');
        // Beacon detected but not our target - treat as no beacon for this session
        _isBeaconDetected = false;
      }
    }
    
    // Handle proximity lost logic with improved timer management
    if (!_isBeaconDetected) {
      // If beacon is not detected, start a proximity lost timer
      // only if we previously had detected a beacon AND met the threshold
      if (wasDetected && _hasMetDetectionThreshold) {
        // Cancel any existing proximity timer to restart it fresh
        _proximityLostTimer?.cancel();
        
        _logger.i('📡 Target beacon signal lost, starting proximity window timer (${_proximityWindowInSeconds}s)');
        _proximityLostTimer = Timer(Duration(seconds: _proximityWindowInSeconds.toInt()), () {
          _logger.i('📡 Proximity window expired - no target beacon detected within ${_proximityWindowInSeconds} seconds');
          // Only reset if we haven't detected a new signal during this time
          if (!_isBeaconDetected) {
            _hasMetDetectionThreshold = false;
            _firstDetectionTime = null;
            onBeaconLost();
          }
          _proximityLostTimer = null;
        });
      }
    }
    
    // Backup mechanism: Always start a backup lost timer when we have threshold met
    // This catches cases where BLE scanning stops providing callbacks
    if (_hasMetDetectionThreshold && _backupLostTimer == null) {
      // Longer timeout than proximity lost (2x) to give main logic priority
      final backupTimeout = Duration(seconds: (_proximityWindowInSeconds * 2).toInt());
      
      _logger.d('🔄 Starting backup lost detection timer (${backupTimeout.inSeconds}s)');
      _backupLostTimer = Timer(backupTimeout, () {
        if (_hasMetDetectionThreshold && !_isBeaconDetected) {
          _logger.i('⚠️ Backup lost timer triggered - forcing beacon lost state');
          _hasMetDetectionThreshold = false;
          _firstDetectionTime = null;
          onBeaconLost();
        }
        _backupLostTimer = null;
      });
    }
  }

  /// Stop scanning for BLE beacons
  Future<void> stopScanning() async {
    // Cancel subscription
    await _rangingSubscription?.cancel();
    _rangingSubscription = null;
    
    // Cancel real-time beacon listener
    await _sessionListenerSubscription?.cancel();
    _sessionListenerSubscription = null;
    
    // Cancel all timers
    _detectionTimer?.cancel();
    _detectionTimer = null;
    
    _proximityLostTimer?.cancel();
    _proximityLostTimer = null;
    
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    
    _backupLostTimer?.cancel();
    _backupLostTimer = null;
    
    // Reset state
    _isBeaconDetected = false;
    _hasMetDetectionThreshold = false;
    _firstDetectionTime = null;
    _realtimeSessionData = null;
    
    _logger.i('Stopped scanning for beacons');
  }

  /// Check if beacon detection threshold has been met
  bool hasMetDetectionThreshold() {
    return _hasMetDetectionThreshold;
  }

  /// Dispose method to clean up resources
  void dispose() {
    _forceStopBroadcasting(); // Force stop without grace period
    stopScanning();
    _broadcastGracePeriodTimer?.cancel();
    _detectionTimer?.cancel();
    _beaconDetectedController.close();
  }
  
  /// Force stop broadcasting immediately without grace period (used on dispose)
  Future<void> _forceStopBroadcasting() async {
    if (!_isTransmitting || _currentSessionId == null) return;

    try {
      // Stop broadcasting immediately
      await _beaconBroadcast.stop();
      
      // Cancel all timers
      _rollingIdTimer?.cancel();
      // Removed heartbeat timer - now combined with rotation
      _broadcastGracePeriodTimer?.cancel();
      _rollingIdTimer = null;
      
      // Clear beacon fields immediately (no grace period) - but leave heartbeat for natural expiry
      final sessionId = _currentSessionId;
      if (sessionId != null) {
        await _firestore.collection('sessions').doc(sessionId).update({
          'beaconId': FieldValue.delete(),
          'beaconMajor': FieldValue.delete(), 
          'beaconMinor': FieldValue.delete(),
          'beaconMode': FieldValue.delete(),
          // Note: beaconUpdatedAt is NOT deleted - left for natural expiry
        });
        _logger.i('Force cleared beacon fields immediately (heartbeat left for natural expiry)');
      }
      
      _isTransmitting = false;
      _currentSessionId = null;
      
    } catch (e) {
      _logger.e('Error force stopping beacon broadcast: $e');
    }
  }
}
