import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';

import '../services/ble_service.dart';
import '../services/nfc_service.dart';
import '../services/attendance_service.dart';
import '../services/selfscancheck.dart';
import '../models/student.dart';
import '../models/security_check_result.dart';
import '../widgets/ble_status_widget.dart';
import '../widgets/self_scan_confirmation_widget.dart';
import '../utils/ble_detection_status.dart';

class StudentSelfScanPage extends StatefulWidget {
  const StudentSelfScanPage({super.key});

  @override
  _StudentSelfScanPageState createState() => _StudentSelfScanPageState();
}

class _StudentSelfScanPageState extends State<StudentSelfScanPage> with WidgetsBindingObserver {
  final BLEService _bleService = BLEService();
  final NFCService _nfcService = NFCService();
  final AttendanceService _attendanceService = AttendanceService();
  final SelfScanCheckService _selfScanCheckService = SelfScanCheckService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger();
  
  // BLE detection state
  bool _isBLEScanning = false;
  BLEDetectionStatus _detectionStatus = BLEDetectionStatus.notDetected;
  String? _detectedSessionId;
  String? _detectedMode; // 'entry' or 'exit'
  Map<String, dynamic>? _sessionData;
  
  // Student data
  Student? _currentStudent;
  bool _isLoading = true;
  bool _scanningNFC = false;
  bool _showConfirmation = false;
  Map<String, dynamic>? _attendanceRecord;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    // Register observer for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    _initializeStudent();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Stop BLE scanning when leaving the page
    _stopScanning();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Restart scanning when app is resumed, stop when inactive
    if (state == AppLifecycleState.resumed) {
      if (!_isBLEScanning) {
        _startScanning();
      }
    } else if (state != AppLifecycleState.resumed) {
      _stopScanning();
    }
  }
  
  Future<void> _initializeStudent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'You are not logged in';
          _isLoading = false;
        });
        return;
      }
      
      // Fetch current student data
      final userEmail = currentUser.email;
      if (userEmail == null) {
        setState(() {
          _errorMessage = 'User email not found';
          _isLoading = false;
        });
        return;
      }
      
      // Query Firestore for student data
      final studentSnapshot = await _firestore
          .collection('students')
          .where('email', isEqualTo: userEmail)
          .limit(1)
          .get();
      
      if (studentSnapshot.docs.isEmpty) {
        setState(() {
          _errorMessage = 'Student profile not found';
          _isLoading = false;
        });
        return;
      }
      
      final studentDoc = studentSnapshot.docs.first;
      final studentData = studentDoc.data();
      
      // Create Student object
      setState(() {
        _currentStudent = Student(
          id: studentDoc.id,
          name: studentData['name'] ?? 'Unknown',
          studentId: studentData['studentId'] ?? 'Unknown',
          email: studentData['email'] ?? '',
          tagId: studentData['tagId'] ?? '',
          photoUrl: studentData['photoUrl'],
          enrolledSections: List<String>.from(studentData['enrolledSections'] ?? []),
        );
        _isLoading = false;
      });
      
      // Start BLE scanning
      _startScanning();
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading student data: $e';
        _isLoading = false;
      });
      _logger.e('Error loading student data: $e');
    }
  }
  
  Future<void> _startScanning() async {
    if (_isBLEScanning) return;
    
    setState(() {
      _isBLEScanning = true;
      _detectionStatus = BLEDetectionStatus.notDetected;
      _detectedSessionId = null;
      _detectedMode = null;
      _sessionData = null;
    });
    
    // Start scanning for BLE beacons
    await _bleService.startScanning(
      onBeaconDetected: (String sessionId, String mode, Map<String, dynamic> sessionData) {
        setState(() {
          _detectionStatus = BLEDetectionStatus.detected;
          _detectedSessionId = sessionId;
          _detectedMode = mode;
          _sessionData = sessionData;
        });
      },
      onBeaconThresholdMet: (String sessionId, String mode, Map<String, dynamic> sessionData) {
        setState(() {
          _detectionStatus = BLEDetectionStatus.thresholdMet;
          _detectedSessionId = sessionId;
          _detectedMode = mode;
          _sessionData = sessionData;
        });
      },
      onBeaconLost: () {
        setState(() {
          _detectionStatus = BLEDetectionStatus.notDetected;
          _detectedSessionId = null;
          _detectedMode = null;
          _sessionData = null;
        });
      },
    );
  }
  
  void _stopScanning() {
    if (!_isBLEScanning) return;
    
    _bleService.stopScanning();
    
    setState(() {
      _isBLEScanning = false;
      _detectionStatus = BLEDetectionStatus.notDetected;
      _detectedSessionId = null;
      _detectedMode = null;
      _sessionData = null;
    });
  }
  
  Future<void> _scanNFCAndMarkAttendance() async {
    if (_detectionStatus != BLEDetectionStatus.thresholdMet || 
        _detectedSessionId == null || 
        _detectedMode == null ||
        _currentStudent == null) {
      _showSnackBar('Session beacon not detected. Please try again when in range.');
      return;
    }
    
    setState(() {
      _scanningNFC = true;
      _errorMessage = null;
      _showConfirmation = false;
    });
    
    try {
      // Determine attendance scan type based on detected mode
      final attendanceScanType = _detectedMode!.toLowerCase() == 'entry'
          ? AttendanceScanType.entry
          : AttendanceScanType.exit;
      
      // Use NFCService to scan the card and get student info
      final tagId = await _nfcService.scanTag();
      
      if (tagId == null) {
        setState(() {
          _scanningNFC = false;
          _errorMessage = 'Failed to scan NFC card';
        });
        _showSnackBar('Failed to scan NFC card. Please try again.');
        return;
      }
      
      // Check if the user is allowed to self-scan
      final canSelfScanResult = await _selfScanCheckService.canUserSelfScan();
      if (!canSelfScanResult.success) {
        setState(() {
          _scanningNFC = false;
          _errorMessage = canSelfScanResult.message;
        });
        _showSnackBar(canSelfScanResult.message);
        return;
      }
      
      // Verify that the NFC card belongs to the logged-in user
      final verificationResult = await _selfScanCheckService.verifyNfcCardOwnership(tagId);
      
      if (!verificationResult.success) {
        setState(() {
          _scanningNFC = false;
          _errorMessage = verificationResult.message;
        });
        _showSnackBar(verificationResult.message);
        return;
      }
      
      // Extract the verified student from the result data
      final verifiedStudent = verificationResult.data as Student?;
      
      // Make sure we have a valid verified student
      if (verifiedStudent == null) {
        setState(() {
          _scanningNFC = false;
          _errorMessage = 'Unable to verify student data';
        });
        _showSnackBar('Unable to verify student data. Please try again.');
        return;
      }
      
      // Re-check session data as it may have changed during async operations
      if (_sessionData == null || _detectedSessionId == null || _detectedMode == null) {
        setState(() {
          _scanningNFC = false;
          _errorMessage = 'Session connection lost during scan';
        });
        _showSnackBar('Session connection lost. Please try again when in range.');
        return;
      }
      
      // Verify student enrollment in section
      final enrollmentResult = await _selfScanCheckService.verifyStudentEnrollment(
        verifiedStudent.studentId, 
        _sessionData!['sectionId'] ?? ''
      );
      
      if (!enrollmentResult.success) {
        setState(() {
          _scanningNFC = false;
          _errorMessage = enrollmentResult.message;
        });
        _showSnackBar(enrollmentResult.message);
        return;
      }
      
      // Check if the user can mark attendance for this session
      final canMarkResult = await _selfScanCheckService.canMarkAttendance(
        _detectedSessionId!,
        verifiedStudent.studentId,
        attendanceScanType
      );
      
      if (!canMarkResult.success) {
        setState(() {
          _scanningNFC = false;
          _errorMessage = canMarkResult.message;
        });
        _showSnackBar(canMarkResult.message);
        return;
      }
      
      // All verifications passed - mark attendance using AttendanceService
      await _attendanceService.markAttendance(
        sessionId: _detectedSessionId!,
        studentId: verifiedStudent.studentId,
        courseId: _sessionData!['courseId'] ?? '',
        sectionId: _sessionData!['sectionId'] ?? '',
        scanType: attendanceScanType,
      );
      
      // Attendance marked successfully
      setState(() {
        _scanningNFC = false;
        _showConfirmation = true;
        _attendanceRecord = {
          'student': verifiedStudent.toMap(),
          'sessionData': _sessionData,
          'attendanceType': _detectedMode,
          'timestamp': Timestamp.now(),
        };
      });
    } catch (e) {
      setState(() {
        _scanningNFC = false;
        _errorMessage = 'Error scanning NFC: $e';
      });
      _logger.e('Error during NFC scan: $e');
      _showSnackBar('Error scanning NFC: $e');
    }
  }
  
  void _dismissConfirmation() {
    setState(() {
      _showConfirmation = false;
      _attendanceRecord = null;
    });
  }
  
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Self Check-In & Out',
          style: TextStyle(color: Color(0xFFFFFDD0)), // Text color matches design
        ),
        backgroundColor: const Color(0xFF8B0000), // Bar color matches design
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _showConfirmation
                  ? _buildConfirmationView()
                  : _buildMainContent(),
    );
  }
  
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An unknown error occurred',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _initializeStudent,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildConfirmationView() {
    if (_attendanceRecord == null) {
      return const Center(child: Text('No attendance record to display'));
    }
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          SelfScanConfirmationWidget(
            student: _currentStudent!,
            sessionData: _sessionData!,
            attendanceType: _detectedMode!,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _dismissConfirmation,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: const Text('Done', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMainContent() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Student info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundImage: _currentStudent?.photoUrl != null && _currentStudent!.photoUrl!.isNotEmpty
                          ? NetworkImage(_currentStudent!.photoUrl!)
                          : null,
                      child: _currentStudent?.photoUrl == null || _currentStudent!.photoUrl!.isEmpty
                          ? Text(_currentStudent?.name.substring(0, 1) ?? '?', 
                              style: const TextStyle(fontSize: 32))
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _currentStudent?.name ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ID: ${_currentStudent?.studentId ?? 'Unknown'}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentStudent?.email ?? 'No email',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // BLE Status Widget
            BLEStatusWidget(
              isBeaconDetected: _detectionStatus != BLEDetectionStatus.notDetected,
              isThresholdMet: _detectionStatus == BLEDetectionStatus.thresholdMet,
              distance: null, // We don't have distance information
            ),
            
            const SizedBox(height: 24),
            
            // NFC Scan button
            ElevatedButton(
              onPressed: _detectionStatus == BLEDetectionStatus.thresholdMet && !_scanningNFC
                  ? _scanNFCAndMarkAttendance
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                disabledBackgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _scanningNFC
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Scanning NFC...'),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.nfc),
                        const SizedBox(width: 12),
                        Text(
                          _detectedMode?.toLowerCase() == 'entry'
                              ? 'Tap to Check In'
                              : _detectedMode?.toLowerCase() == 'exit'
                                  ? 'Tap to Check Out'
                                  : 'Scan NFC Card',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
            ),
            
            // Instructions
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How to Self Check In/Out:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildInstructionStep(1, 'Stand close to the lecturer\'s device.'),
                  _buildInstructionStep(2, 'Wait until the session is detected (green indicator).'),
                  _buildInstructionStep(3, 'Tap the button above and hold your student ID card to your phone.'),
                  _buildInstructionStep(4, 'Wait for confirmation.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInstructionStep(int number, String instruction) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF8B0000),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              instruction,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
