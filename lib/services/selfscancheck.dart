import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';

import '../models/student.dart';
import '../models/security_check_result.dart';
import '../services/attendance_service.dart';

/// Service class that handles security checks for student self-scan attendance
class SelfScanCheckService {
  // Singleton pattern
  static final SelfScanCheckService _instance = SelfScanCheckService._internal();
  factory SelfScanCheckService() => _instance;
  SelfScanCheckService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Logger _logger = Logger();

  /// Verifies that the NFC card matches the logged-in user
  /// 
  /// This is a critical security check that ensures:
  /// 1. The NFC card's tagId exists in the students collection
  /// 2. The logged-in user's UID matches the email field in that student document
  ///
  /// Returns a SecurityCheckResult with a Student object if verification passes
  Future<SecurityCheckResult> verifyNfcCardOwnership(String tagId) async {
    try {
      // Check if user is logged in
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        _logger.w('No user logged in during NFC verification');
        return SecurityCheckResult.failure(message: 'You are not logged in');
      }

      final userEmail = currentUser.email;

      if (userEmail == null) {
        _logger.w('Logged-in user has no email');
        return SecurityCheckResult.failure(message: 'User email not found');
      }

      _logger.i('Verifying NFC card ownership for user: $userEmail');

      // Query Firestore for the student with this tagId
      final studentQuery = await _firestore
          .collection('students')
          .where('tagId', isEqualTo: tagId)
          .limit(1)
          .get();

      if (studentQuery.docs.isEmpty) {
        _logger.w('No student found with NFC tag ID: $tagId');
        return SecurityCheckResult.failure(message: 'This NFC card is not registered in the system');
      }

      final studentDoc = studentQuery.docs.first;
      final studentData = studentDoc.data();

      // Verify the student document's email matches the logged-in user
      final studentEmail = studentData['email'] as String?;
      
      if (studentEmail == null || studentEmail != userEmail) {
        _logger.w('NFC card belongs to a different student. Card email: $studentEmail, User email: $userEmail');
        return SecurityCheckResult.failure(message: 'The scanned card does not belong to you');
      }

      _logger.i('NFC card ownership verified successfully');
      
      // Return the verified student object
      final student = Student(
        id: studentDoc.id,
        name: studentData['name'] ?? 'Unknown',
        email: studentEmail,
        studentId: studentData['studentId'] ?? '',
        photoUrl: studentData['photoUrl'],
        tagId: tagId,
        enrolledSections: List<String>.from(studentData['enrolledSections'] ?? []),
      );
      
      return SecurityCheckResult.success(
        message: 'Card ownership verified successfully',
        data: student
      );
    } catch (e) {
      _logger.e('Error verifying NFC card ownership: $e');
      return SecurityCheckResult.failure(message: 'Error verifying card ownership: $e');
    }
  }

  /// Verifies the user has permission to access the self-scan feature
  /// 
  /// This checks if the current user is a student registered in the system
  Future<SecurityCheckResult> canUserSelfScan() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null || currentUser.email == null) {
        return SecurityCheckResult.failure(message: 'You are not logged in');
      }

      // Check if user exists in students collection
      final studentQuery = await _firestore
          .collection('students')
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get();

      if (studentQuery.docs.isEmpty) {
        return SecurityCheckResult.failure(message: 'You are not registered as a student');
      }
      
      return SecurityCheckResult.success(message: 'User is authorized for self-scan');
    } catch (e) {
      _logger.e('Error checking self-scan permission: $e');
      return SecurityCheckResult.failure(message: 'Error checking self-scan permission: $e');
    }
  }

  /// Verifies if student is enrolled in the session's section
  /// 
  /// This ensures students can only self-scan for sections they're enrolled in
  Future<SecurityCheckResult> verifyStudentEnrollment(String studentDocId, String sectionId) async {
    try {
      if (sectionId.isEmpty) {
        return SecurityCheckResult.failure(message: 'Invalid section ID');
      }
      
      // Fetch the student document directly by its ID
      final studentDoc = await _firestore.collection('students').doc(studentDocId).get();

      if (!studentDoc.exists) {
        _logger.w('Student profile not found for document ID: $studentDocId');
        return SecurityCheckResult.failure(message: 'Student profile not found');
      }

      final studentData = studentDoc.data()!;
      final enrolledSections = List<String>.from(studentData['enrolledSections'] ?? []);

      if (!enrolledSections.contains(sectionId)) {
        _logger.w('Student $studentDocId is not enrolled in section $sectionId');
        return SecurityCheckResult.failure(
          message: 'You are not enrolled in this section'
        );
      }
      
      _logger.i('Student enrollment verified for $studentDocId in section $sectionId');
      return SecurityCheckResult.success(message: 'Student enrollment verified');
    } catch (e) {
      _logger.e('Error verifying student enrollment: $e');
      return SecurityCheckResult.failure(message: 'Error verifying enrollment: $e');
    }
  }
  
  /// Only checks for duplicate attendance without verifying session state
  /// 
  /// This is useful during grace periods when session may temporarily appear inactive
  Future<SecurityCheckResult> checkDuplicateAttendance(String sessionId, String studentDocId, AttendanceScanType scanType) async {
    try {
      // Check for duplicate entry/exit in the correct collection
      final attendanceQuery = await _firestore
          .collection('attendance_records') // Corrected collection name
          .where('sessionId', isEqualTo: sessionId)
          .where('studentId', isEqualTo: studentDocId) // This is now the document ID
          .where('scanType', isEqualTo: scanType.name)
          .get();
          
      if (attendanceQuery.docs.isNotEmpty) {
        final message = scanType == AttendanceScanType.entry 
            ? 'You have already checked in to this session' 
            : 'You have already checked out from this session';
            
        return SecurityCheckResult.failure(message: message);
      }
      
      // Check entry before exit
      if (scanType == AttendanceScanType.exit) {
        final entryQuery = await _firestore
            .collection('attendance_records') // Corrected collection name
            .where('sessionId', isEqualTo: sessionId)
            .where('studentId', isEqualTo: studentDocId) // This is now the document ID
            .where('status', isEqualTo: 'entry_scanned')
            .get();
            
        if (entryQuery.docs.isEmpty) {
          return SecurityCheckResult.failure(message: 'You must check in before checking out');
        }
      }
      
      return SecurityCheckResult.success(message: 'No duplicate attendance found');
    } catch (e) {
      _logger.e('Error checking duplicate attendance: $e');
      
      // Special handling for permission-denied errors
      if (e.toString().contains('permission-denied')) {
        return SecurityCheckResult.failure(message: 'Permission denied. Please ensure you are logged in and have access to this session.');
      }
      
      return SecurityCheckResult.failure(message: 'Error checking attendance: $e');
    }
  }

  /// Checks if the user can mark attendance for this session
  /// 
  /// Verifies session exists, is active, and checks for duplicate attendance
  Future<SecurityCheckResult> canMarkAttendance(String sessionId, String studentId, AttendanceScanType scanType) async {
    try {
      // First verify session exists and is active
      final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
      
      if (!sessionDoc.exists) {
        return SecurityCheckResult.failure(message: 'Session not found');
      }
      
      final sessionData = sessionDoc.data()!;
      
      // Check if the session is active based on time rather than just the isActive flag
      // This is more resilient during grace periods when the flag might be temporarily removed
      final now = Timestamp.now();
      final startTime = sessionData['startTime'] as Timestamp?;
      final endTime = sessionData['endTime'] as Timestamp?;
      
      // Check time-based activity if timestamps are available
      if (startTime != null && endTime != null) {
        if (now.compareTo(startTime) < 0) {
          return SecurityCheckResult.failure(message: 'This session has not started yet');
        }
        if (now.compareTo(endTime) > 0) {
          return SecurityCheckResult.failure(message: 'This session has already ended');
        }
      } else {
        // Fall back to isActive flag if timestamps are not available
        final bool isActive = sessionData['isActive'] ?? false;
        if (!isActive) {
          return SecurityCheckResult.failure(message: 'This session is not active');
        }
      }
      
      // Reuse duplicate attendance check logic
      final duplicateCheck = await checkDuplicateAttendance(sessionId, studentId, scanType);
      if (!duplicateCheck.success) {
        return duplicateCheck;
      }
      
      return SecurityCheckResult.success(
        message: 'Attendance verification passed', 
        data: sessionData
      );
    } catch (e) {
      _logger.e('Error checking attendance eligibility: $e');
      return SecurityCheckResult.failure(message: 'Error checking attendance eligibility: $e');
    }
  }
}
