import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';
import '../services/nfc_service.dart';
import '../widgets/scanned_student_list.dart';
import '../services/attendance_service.dart';
import 'package:logger/logger.dart';

class NFCScannerPage extends StatefulWidget {
  const NFCScannerPage({super.key});

  @override
  _NFCScannerPageState createState() => _NFCScannerPageState();
}

class _NFCScannerPageState extends State<NFCScannerPage> {
  final List<Student> _scannedStudents = [];
  bool _isScanning = false;
  String _status = 'Tap to scan';
  String? _sessionId;
  final Logger logger = Logger();
  final NFCService _nfcService = NFCService();
  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionId = ModalRoute.of(context)?.settings.arguments as String?;
      if (_sessionId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No session ID provided'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    });
  }

  Future<void> _scanTag() async {
    if (_sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active session'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Verify session is still active based on timestamp
    final currentTime = Timestamp.now();
    final sessionDoc = await FirebaseFirestore.instance
        .collection('sessions')
        .doc(_sessionId)
        .get();
    
    if (!sessionDoc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session not found'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
      return;
    }

    final sessionData = sessionDoc.data();
    final startTime = sessionData?['startTime'] as Timestamp?;
    final endTime = sessionData?['endTime'] as Timestamp?;
    if (startTime == null || endTime == null || 
        !startTime.toDate().isBefore(currentTime.toDate()) || 
        !endTime.toDate().isAfter(currentTime.toDate())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session has ended. Returning to homepage.'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.pop(context);
      return;
    }

    setState(() {
      _isScanning = true;
      _status = 'Scanning...';
    });

    final student = await _nfcService.scanAndFetchStudent();

    if (!mounted) return;

    if (student != null) {
      setState(() {
        // Check if student is already in list to avoid duplicates in UI
        if (!_scannedStudents.any((s) => s.id == student.id)) {
          _scannedStudents.add(student);
        }
        _status = 'Scanned: ${student.name}';
      });
      
      // Get session details to pass to attendance service
      try {
        final courseId = sessionData?['courseId'] ?? '';
        final sectionId = sessionData?['sectionId'] ?? '';

        // Check if student is enrolled in section
        if (!student.enrolledSections.contains(sectionId)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${student.name} is not enrolled in this section'),
              backgroundColor: Colors.deepOrange,
            ),
          );
          return;
        }
        
        // Mark attendance
        final result = await _attendanceService.markAttendance(
          sessionId: _sessionId!,
          studentId: student.studentId,
          courseId: courseId,
          sectionId: sectionId,
        );
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${student.name} (${student.studentId}): $result'),
            backgroundColor: result.contains('successfully') ? Colors.green : Colors.orange,
          ),
        );
      } catch (e) {
        logger.e('Error marking attendance: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error marking attendance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      setState(() {
        _status = 'Tag not recognized';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unknown tag or error occurred'),
          backgroundColor: Colors.orange,
        ),
      );
    }

    setState(() => _isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Attendance'),
        backgroundColor: Colors.blueGrey[800],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _scanTag,
              icon: const Icon(Icons.nfc),
              label: Text(_isScanning ? 'Scanning...' : 'Scan Student Tag'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 14.0),
              ),
            ),
          ),
          Text(_status),
          const Divider(),
          Expanded(
            child: ScannedStudentList(students: _scannedStudents),
          ),
        ],
      ),
    );
  }
}