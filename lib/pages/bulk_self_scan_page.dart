import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

import '../services/ble_service.dart';
// Removed unused import

class BulkSelfScanPage extends StatefulWidget {
  final String sessionId;
  
  const BulkSelfScanPage({
    super.key,
    required this.sessionId,
  });

  @override
  State<BulkSelfScanPage> createState() => _BulkSelfScanPageState();
}

class _BulkSelfScanPageState extends State<BulkSelfScanPage> with WidgetsBindingObserver {
  final Logger _logger = Logger();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final BLEService _bleService = BLEService();
  
  bool _isLoading = true;
  bool _errorState = false;
  String _errorMessage = '';
  Map<String, dynamic>? _sessionData;
  
  // BLE broadcast state
  bool _isEntryModeActive = false;
  bool _isExitModeActive = false;
  Timer? _cooldownTimer;
  bool _inCooldown = false;
  
  // Attendance listener subscription
  StreamSubscription<QuerySnapshot>? _attendanceSubscription;
  
  // List of scanned students
  final List<dynamic> _scannedStudents = [];
  
  @override
  void initState() {
    super.initState();
    // Register observer for app lifecycle changes (to stop BLE when app is inactive)
    WidgetsBinding.instance.addObserver(this);
    _loadSessionData();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Cancel attendance subscription to stop ongoing reads
    _attendanceSubscription?.cancel();
    // Stop BLE broadcasting when leaving the page
    _stopBroadcasting();
    _cooldownTimer?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Stop BLE broadcasting when app is inactive
    if (state != AppLifecycleState.resumed) {
      _stopBroadcasting();
    }
  }
  
  Future<void> _loadSessionData() async {
    setState(() {
      _isLoading = true;
      _errorState = false;
      _errorMessage = '';
    });
    
    try {
      // Get session data from Firestore
      final sessionDoc = await _firestore.collection('sessions').doc(widget.sessionId).get();
      if (!sessionDoc.exists) {
        setState(() {
          _errorState = true;
          _errorMessage = 'Session not found';
        });
        return;
      }
      
      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      
      // Check lecturer permissions
      final currentUserUid = _auth.currentUser?.uid;
      if (currentUserUid != sessionData['lecturerEmail']) {
        setState(() {
          _errorState = true;
          _errorMessage = 'You are not authorized to manage this session';
        });
        return;
      }
      
      // Check if session is active
      final now = Timestamp.now();
      final startTime = sessionData['startTime'] as Timestamp?;
      final endTime = sessionData['endTime'] as Timestamp?;
      
      if (startTime == null || endTime == null) {
        setState(() {
          _errorState = true;
          _errorMessage = 'Session time information is missing';
        });
        return;
      }
      
      if (now.compareTo(startTime) < 0) {
        setState(() {
          _errorState = true;
          _errorMessage = 'Session has not started yet';
        });
        return;
      }
      
      if (now.compareTo(endTime) > 0) {
        setState(() {
          _errorState = true;
          _errorMessage = 'Session has already ended';
        });
        return;
      }
      
      // Check if session already has beacon state
      if (sessionData['beaconId'] != null) {
        final mode = sessionData['beaconMode'] ?? 'entry';
        setState(() {
          if (mode.toLowerCase() == 'entry') {
            _isEntryModeActive = true;
          } else {
            _isExitModeActive = true;
          }
        });
      }
      
      setState(() {
        _sessionData = sessionData;
        _isLoading = false;
      });
      
      // Start listening for attendance records to update the UI
      _setupAttendanceListener();
      
    } catch (e) {
      setState(() {
        _errorState = true;
        _errorMessage = 'Error loading session data: $e';
        _isLoading = false;
      });
      _logger.e('Error loading session data: $e');
    }
  }
  
  void _setupAttendanceListener() {
    // Set up a listener for attendance records for this session
    // Set up real-time listener for attendance updates
    _attendanceSubscription = _firestore
        .collection('attendance')
        .where('sessionId', isEqualTo: widget.sessionId)
        .orderBy('entryTimestamp', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
          final students = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'studentId': data['studentId'],
              'entryTimestamp': data['entryTimestamp'],
              'exitTimestamp': data['exitTimestamp'],
              'status': data['status'],
            };
          }).toList();
          
          setState(() {
            _scannedStudents.clear();
            _scannedStudents.addAll(students);
          });
        });
  }
  
  Future<void> _toggleEntryMode() async {
    if (_inCooldown) {
      _showSnackBar('Please wait before toggling modes');
      return;
    }
    
    if (_isEntryModeActive) {
      await _stopBroadcasting();
    } else {
      // Stop exit mode if active
      if (_isExitModeActive) {
        await _stopBroadcasting();
      }
      
      // Show loading indicator
      setState(() {
        _isLoading = true;
      });
      
      // Start entry mode
      final success = await _bleService.startBroadcasting(widget.sessionId, 'entry');
      
      setState(() {
        _isLoading = false;
        _isEntryModeActive = success;
        _isExitModeActive = false;
      });
      
      if (success) {
        _showSnackBar('Entry Self-Scan mode activated');
        // Start cooldown to prevent rapid toggling
        _startCooldown();
      } else {
        _showSnackBar('Failed to activate Entry Self-Scan mode');
      }
    }
  }
  
  Future<void> _toggleExitMode() async {
    if (_inCooldown) {
      _showSnackBar('Please wait before toggling modes');
      return;
    }
    
    if (_isExitModeActive) {
      await _stopBroadcasting();
    } else {
      // Stop entry mode if active
      if (_isEntryModeActive) {
        await _stopBroadcasting();
      }
      
      // Show loading indicator
      setState(() {
        _isLoading = true;
      });
      
      // Start exit mode
      final success = await _bleService.startBroadcasting(widget.sessionId, 'exit');
      
      setState(() {
        _isLoading = false;
        _isExitModeActive = success;
        _isEntryModeActive = false;
      });
      
      if (success) {
        _showSnackBar('Exit Self-Scan mode activated');
        // Start cooldown to prevent rapid toggling
        _startCooldown();
      } else {
        _showSnackBar('Failed to activate Exit Self-Scan mode');
      }
    }
  }
  
  Future<void> _stopBroadcasting() async {
    if (_isEntryModeActive || _isExitModeActive) {
      final success = await _bleService.stopBroadcasting();
      
      setState(() {
        _isEntryModeActive = false;
        _isExitModeActive = false;
      });
      
      if (success) {
        _showSnackBar('Self-Scan mode deactivated');
        // Start cooldown to prevent rapid toggling
        _startCooldown();
      } else {
        _showSnackBar('Failed to deactivate Self-Scan mode');
      }
    }
  }
  
  void _startCooldown() {
    setState(() {
      _inCooldown = true;
    });
    
    // 2-second cooldown as specified
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(const Duration(seconds: 2), () {
      setState(() {
        _inCooldown = false;
      });
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
          'NFC Attendance',
          style: TextStyle(color: Color(0xFFFFFDD0)), // Text color matches Figure 4
        ),
        backgroundColor: const Color(0xFF8B0000), // Bar color matches Figure 4
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorState
              ? _buildErrorState()
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
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadSessionData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMainContent() {
    // Format session details for display
    final formattedStartTime = _sessionData?['startTime'] != null
        ? DateFormat('dd MMM, hh:mm a').format((_sessionData!['startTime'] as Timestamp).toDate())
        : 'N/A';
    final formattedEndTime = _sessionData?['endTime'] != null
        ? DateFormat('hh:mm a').format((_sessionData!['endTime'] as Timestamp).toDate())
        : 'N/A';
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Self-scan mode toggle buttons - matches Figure 4
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _inCooldown ? null : _toggleEntryMode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isEntryModeActive ? Colors.green : Colors.green.shade600,
                    disabledBackgroundColor: Colors.green.shade200,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    _isEntryModeActive ? 'Stop Entry Self Scan' : 'Start Entry Self Scan',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _inCooldown ? null : _toggleExitMode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isExitModeActive ? Colors.green : Colors.green.shade600,
                    disabledBackgroundColor: Colors.green.shade200,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    _isExitModeActive ? 'Stop Exit Self Scan' : 'Start Exit Self Scan',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          
          // Instructional text - matches Figure 4
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              'Tap to ${(_isEntryModeActive || _isExitModeActive) ? 'stop' : 'start'} scanning',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          
          // Session info
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _sessionData?['title'] ?? 'Unnamed Session',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '$formattedStartTime - $formattedEndTime',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _sessionData?['venue'] ?? 'No venue',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Self-scan status
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_isEntryModeActive || _isExitModeActive)
                  ? Colors.green.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (_isEntryModeActive || _isExitModeActive)
                    ? Colors.green.shade300
                    : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  (_isEntryModeActive || _isExitModeActive)
                      ? Icons.bluetooth_connected
                      : Icons.bluetooth_disabled,
                  color: (_isEntryModeActive || _isExitModeActive)
                      ? Colors.green
                      : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (_isEntryModeActive || _isExitModeActive)
                            ? 'Self-Scan ${_isEntryModeActive ? "Entry" : "Exit"} Mode Active'
                            : 'Self-Scan Mode Inactive',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: (_isEntryModeActive || _isExitModeActive)
                              ? Colors.green
                              : Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        (_isEntryModeActive || _isExitModeActive)
                            ? 'Students can now self-check ${_isEntryModeActive ? "in" : "out"}'
                            : 'Activate a mode above to enable student self-check',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Recently scanned students heading
          const SizedBox(height: 16),
          const Text(
            'Recent Attendance',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          
          // Scanned students list - matches Figure 4
          Expanded(
            child: _scannedStudents.isEmpty
                ? const Center(
                    child: Text('No students scanned yet'),
                  )
                : ListView.builder(
                    itemCount: _scannedStudents.length,
                    itemBuilder: (context, index) {
                      final student = _scannedStudents[index];
                      
                      // We need to fetch the student info to display name and photo
                      return FutureBuilder<DocumentSnapshot?>(
                        future: _firestore
                            .collection('students')
                            .where('studentId', isEqualTo: student['studentId'])
                            .limit(1)
                            .get()
                            .then((snapshot) => snapshot.docs.isNotEmpty 
                                ? snapshot.docs.first 
                                : null as DocumentSnapshot?),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const ListTile(
                              leading: CircleAvatar(child: Icon(Icons.person)),
                              title: Text('Loading...'),
                            );
                          }
                          
                          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.error)),
                              title: Text('Student ${student['studentId']}'),
                              subtitle: Text(
                                'Status: ${student['status'] ?? "Unknown"}'
                              ),
                            );
                          }
                          
                          final studentData = snapshot.data!.data() as Map<String, dynamic>?;
                          if (studentData == null) {
                            return ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person)),
                              title: Text('Student ${student['studentId']}'),
                              subtitle: Text(
                                'Status: ${student['status'] ?? "Unknown"}'
                              ),
                            );
                          }
                          
                          final name = studentData['name'] ?? 'Unknown';
                          final photoUrl = studentData['photoUrl'];
                          final timestamp = student['entryTimestamp'] != null
                              ? DateFormat('hh:mm:ss a').format((student['entryTimestamp'] as Timestamp).toDate())
                              : 'N/A';
                              
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: photoUrl == null || photoUrl.isEmpty
                                  ? Text(name[0])
                                  : null,
                            ),
                            title: Text(name),
                            subtitle: Text(
                              'Student ID: ${student['studentId']}\nTime: $timestamp'
                            ),
                            trailing: Icon(
                              student['status'] == 'present' || student['exitTimestamp'] != null
                                  ? Icons.check_circle
                                  : Icons.login,
                              color: student['status'] == 'present' || student['exitTimestamp'] != null
                                  ? Colors.green
                                  : Colors.blue,
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
