import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';
import '../services/nfc_service.dart';
import '../widgets/scanned_student_list.dart';
import '../services/attendance_service.dart'; // Ensure this import is correct
import 'package:logger/logger.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth

class NFCScannerPage extends StatefulWidget {
  final String sessionId; // Add sessionId as a required parameter
  const NFCScannerPage({super.key, required this.sessionId}); // Update constructor

  @override
  _NFCScannerPageState createState() => _NFCScannerPageState();
}

class _NFCScannerPageState extends State<NFCScannerPage> {
  final List<Student> _scannedStudents = [];
  bool _isScanning = false;
  String _status = 'Tap to scan';
  final Logger logger = Logger();
  final NFCService _nfcService = NFCService();
  final AttendanceService _attendanceService = AttendanceService();

  @override
  void initState() {
    super.initState();
    // No need to get sessionId from ModalRoute anymore, it's passed directly
    // from the constructor (SelectionPage will pass it).
  }

  Future<void> _scanTag() async {
    if (widget.sessionId.isEmpty) { // Using widget.sessionId directly
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active session'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _status = 'Scanning...';
      logger.d('Starting NFC scan for session: ${widget.sessionId}');
    });

    try {
      final student = await _nfcService.scanAndFetchStudent();

      if (student != null) {
        logger.d('Student found: ${student.name} (${student.studentId})');

        // Fetch session details
        final sessionDoc = await FirebaseFirestore.instance.collection('sessions').doc(widget.sessionId).get();
        if (!sessionDoc.exists) {
          logger.e('Error: Session details not found for ID: ${widget.sessionId}');
          setState(() => _status = 'Error: Session details not found.');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: Session details not found.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isScanning = false);
          return;
        }
        final sessionData = sessionDoc.data()!;
        final courseId = sessionData['courseId'] as String;
        final sectionId = sessionData['sectionId'] as String;
        logger.d('Fetched session details: CourseID=$courseId, SectionID=$sectionId');

        // --- START DEBUGGING AUTHENTICATION ---
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          logger.i('🐛 Authenticated User ID: ${currentUser.uid}');
          logger.i('🐛 Authenticated User Email: ${currentUser.email}');
        } else {
          logger.e('❌ No authenticated user found during NFC scan!');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Authentication error: No user logged in.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() => _isScanning = false);
          return; // Stop further processing if no user is authenticated
        }
        // --- END DEBUGGING AUTHENTICATION ---

        // Check for existing attendance record to determine scan type
        final existingRecord = await _attendanceService.getExistingAttendanceRecords(widget.sessionId, student.studentId);
        logger.d('Existing attendance record found: ${existingRecord != null ? existingRecord.id : 'None'}');

        AttendanceScanType scanType;
        String successMessage;

        if (existingRecord == null) {
          scanType = AttendanceScanType.entry;
          successMessage = 'Entry attendance marked successfully for ${student.name}';
        } else if (existingRecord['exitTimestamp'] == null) {
          scanType = AttendanceScanType.exit;
          successMessage = 'Exit attendance marked successfully for ${student.name}';
        } else {
          successMessage = 'Attendance already completed for ${student.name}';
          setState(() {
            _status = successMessage;
            _isScanning = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMessage),
              backgroundColor: Colors.blueGrey,
            ),
          );
          return; // Exit as attendance is already completed
        }

        // --- Attempt to mark attendance regularly first ---
        String result = await _attendanceService.markAttendance(
          sessionId: widget.sessionId,
          studentId: student.studentId,
          courseId: courseId,
          sectionId: sectionId,
          scanType: scanType,
          isSpecialAttendance: false, // Initial attempt is regular
        );

        logger.d('Initial markAttendance result: $result');

        if (result == 'Student not enrolled in this section') {
          // --- Student not enrolled, prompt for special attendance ---
          logger.i('Student not enrolled. Prompting for special attendance.');
          final bool? markAsSpecial = await _showSpecialAttendanceDialog(student.name);

          if (markAsSpecial != null && markAsSpecial) {
            String? specialReason = await _showReasonDialog(); // Get the reason

            if (specialReason != null && specialReason.isNotEmpty) {
              result = await _attendanceService.markAttendance(
                sessionId: widget.sessionId,
                studentId: student.studentId,
                courseId: courseId,
                sectionId: sectionId,
                scanType: scanType,
                isSpecialAttendance: true, // Mark as special
                specialReason: specialReason,
              );
              logger.d('Special attendance mark result: $result');
              _handleAttendanceResult(result, successMessage, student);
            } else {
              _status = 'Special attendance cancelled: No reason provided.';
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Special attendance cancelled: No reason provided.'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } else {
            _status = 'Attendance not marked: Student not enrolled.';
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Attendance not marked: Student not enrolled in this section.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          // --- Handle regular attendance result ---
          _handleAttendanceResult(result, successMessage, student);
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
        logger.w('NFC scan returned null student (Tag not recognized)');
      }
    } catch (e, stackTrace) {
      logger.e('Error during NFC scan or attendance marking: $e', error: e, stackTrace: stackTrace);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during scan: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isScanning = false);
      logger.d('NFC scan process finished.');
    }
  }

  // Helper function to handle the result of markAttendance
  void _handleAttendanceResult(String result, String successMessage, Student student) {
    if (result.contains('successfully')) {
      setState(() {
        _status = successMessage;
        final index = _scannedStudents.indexWhere((s) => s.studentId == student.studentId);
        if (index == -1) {
          _scannedStudents.add(student);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );
      logger.i('Attendance marked: $successMessage');
    } else {
      setState(() {
        _status = 'Attendance Error: $result';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Attendance Error: $result'),
          backgroundColor: Colors.red,
        ),
      );
      logger.e('Attendance marking failed: $result');
    }
  }

  // Dialog to confirm special attendance
  Future<bool?> _showSpecialAttendanceDialog(String studentName) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must tap a button
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Student Not Enrolled'),
          content: Text('"$studentName" is not enrolled in this section. Do you want to mark this as special attendance?'),
          actions: <Widget>[
            TextButton(
              child: const Text('No (Cancel)'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              child: const Text('Yes (Mark Special)'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

  // Dialog to get special attendance reason
  Future<String?> _showReasonDialog() async {
    String? reason;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Reason for Special Attendance'),
          content: TextField(
            onChanged: (value) {
              reason = value;
            },
            decoration: const InputDecoration(hintText: 'Enter reason (e.g., "Attending due to urgent absence")'),
            maxLines: 3,
            minLines: 1,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(null); // Return null if cancelled
              },
            ),
            ElevatedButton(
              child: const Text('Submit'),
              onPressed: () {
                Navigator.of(context).pop(reason); // Return the entered reason
              },
            ),
          ],
        );
      },
    );
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