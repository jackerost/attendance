import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/constants.dart';
import '../utils/error_handler.dart';
import 'package:logger/logger.dart';

enum AttendanceScanType { entry, exit }

class AttendanceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final logger = Logger();

  // Singleton pattern
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  /// Marks attendance for a student in a specific session
  Future<String> markAttendance({
    required String sessionId,
    required String studentId,
    required String courseId,
    required String sectionId,
    required AttendanceScanType scanType,
    bool isSpecialAttendance = false, // NEW PARAMETER
    String? specialReason,            // NEW PARAMETER
  }) async {
    try {
      // Existing session status check
      final sessionStatus = await _checkSessionStatus(sessionId, courseId, sectionId);
      if (!sessionStatus.isActive) return 'Session is not active: ${sessionStatus.message}';

      // Conditional check for student enrollment
      if (!isSpecialAttendance) { // Only check enrollment for regular attendance
        final isEnrolled = await _isStudentEnrolledInSection(studentId, sectionId);
        if (!isEnrolled) return 'Student not enrolled in this section';
      }

      // Determine attendance type to save
      String attendanceType = isSpecialAttendance ? 'special_absent_reason' : 'regular';

      // Handle entry scan
      if (scanType == AttendanceScanType.entry) {
        final existingEntry = await getExistingAttendanceRecords(sessionId, studentId);
        if (existingEntry != null) {
          if (existingEntry['exitTimestamp'] != null) {
            return 'Attendance already completed for this session';
          }
          return 'Already entered for this session. Waiting for exit scan.';
        }

        await _firestore.collection(FirestorePaths.attendanceRecords).add({
          'sessionId': sessionId,
          'studentId': studentId,
          'courseId': courseId,
          'sectionId': sectionId,
          'entryTimestamp': Timestamp.now(),
          'exitTimestamp': null,
          'status': 'entry_scanned',
          'attendanceType': attendanceType, // NEW FIELD
          'specialReason': specialReason,   // NEW FIELD (will be null for regular attendance)
          'scanType': scanType.name,
        });
        return 'Entry attendance marked successfully';
      }
      // Handle exit scan
      else if (scanType == AttendanceScanType.exit) {
        final existingEntry = await getExistingAttendanceRecords(sessionId, studentId);
        if (existingEntry == null) {
          return 'No entry record found for this session. Please scan for entry first.';
        }
        if (existingEntry['exitTimestamp'] != null) {
          return 'Exit attendance already marked for this session.';
        }

        // Update the existing record with exit timestamp and final status
        await _firestore.collection(FirestorePaths.attendanceRecords).doc(existingEntry.id).update({
          'exitTimestamp': Timestamp.now(),
          'status': AttendanceStatus.present,
          'scanType': scanType.name,
        });
        return 'Exit attendance marked successfully';
      }
      return 'Invalid scan type';
    } catch (e, stackTrace) {
      ErrorHandler.logError('Failed to mark attendance', e, stackTrace);
      return 'Failed to mark attendance: ${e.toString()}';
    }
  }

  /// Marks attendance specifically for the student self-scan feature.
  /// This uses the student's document ID for verification and record creation.
  Future<String> markSelfScanAttendance({
    required String sessionId,
    required String studentDocId, // Uses Document ID
    required String courseId,
    required String sectionId,
    required AttendanceScanType scanType,
  }) async {
    try {
      // Session Status Check (can be reused)
      final sessionStatus = await _checkSessionStatus(sessionId, courseId, sectionId);
      if (!sessionStatus.isActive) return 'Session is not active: ${sessionStatus.message}';

      // Enrollment Check using Document ID
      final isEnrolled = await _isStudentEnrolledInSectionById(studentDocId, sectionId);
      if (!isEnrolled) return 'Student not enrolled in this section';

      // Handle entry scan
      if (scanType == AttendanceScanType.entry) {
        final existingEntry = await getExistingAttendanceRecords(sessionId, studentDocId);
        if (existingEntry != null) {
          if (existingEntry['exitTimestamp'] != null) {
            return 'Attendance already completed for this session';
          }
          return 'Already entered for this session. Waiting for exit scan.';
        }

        await _firestore.collection(FirestorePaths.attendanceRecords).add({
          'sessionId': sessionId,
          'studentId': studentDocId, // Storing Document ID
          'courseId': courseId,
          'sectionId': sectionId,
          'entryTimestamp': Timestamp.now(),
          'exitTimestamp': null,
          'status': 'entry_scanned',
          'attendanceType': 'regular',
          'specialReason': null,
          'scanType': scanType.name,
        });
        return 'Entry attendance marked successfully';
      }
      // Handle exit scan
      else if (scanType == AttendanceScanType.exit) {
        final existingEntry = await getExistingAttendanceRecords(sessionId, studentDocId);
        if (existingEntry == null) {
          return 'No entry record found for this session. Please scan for entry first.';
        }
        if (existingEntry['exitTimestamp'] != null) {
          return 'Exit attendance already marked for this session.';
        }

        // Update the existing record with exit timestamp and final status
        await _firestore.collection(FirestorePaths.attendanceRecords).doc(existingEntry.id).update({
          'exitTimestamp': Timestamp.now(),
          'status': AttendanceStatus.present,
          'scanType': scanType.name,
        });
        return 'Exit attendance marked successfully';
      }
      return 'Invalid scan type';
    } catch (e, stackTrace) {
      ErrorHandler.logError('Failed to mark self-scan attendance', e, stackTrace);
      return 'Failed to mark self-scan attendance: ${e.toString()}';
    }
  }

  Future<DocumentSnapshot?> getExistingAttendanceRecords(String sessionId, String studentId) async {
    final querySnapshot = await _firestore
        .collection(FirestorePaths.attendanceRecords)
        .where('sessionId', isEqualTo: sessionId)
        .where('studentId', isEqualTo: studentId)
        .limit(1)
        .get();
    return querySnapshot.docs.isNotEmpty ? querySnapshot.docs.first : null;
  }

  Future<bool> _isStudentEnrolledInSection(String studentId, String sectionId) async {
    try {
      final studentQuery = await _firestore
        .collection(FirestorePaths.students)
        .where('studentId', isEqualTo: studentId)
        .limit(1)
        .get();

    if (studentQuery.docs.isEmpty) {
      logger.w('No student found with studentId: $studentId');
      return false;
    }

    final studentDoc = studentQuery.docs.first;
    final enrolledSections = List<String>.from(studentDoc.data()['enrolledSections'] ?? []);
    return enrolledSections.contains(sectionId);
  } catch (e) {
    ErrorHandler.logError('Section enrollment check failed', e);
    return false;
  }
  }

  /// Checks enrollment using the student's document ID.
  Future<bool> _isStudentEnrolledInSectionById(String studentDocId, String sectionId) async {
    try {
      final studentDoc = await _firestore
        .collection(FirestorePaths.students)
        .doc(studentDocId)
        .get();

    if (!studentDoc.exists) {
      logger.w('No student found with document ID: $studentDocId');
      return false;
    }

    final studentData = studentDoc.data()!;
    final enrolledSections = List<String>.from(studentData['enrolledSections'] ?? []);
    return enrolledSections.contains(sectionId);
    } catch (e) {
      ErrorHandler.logError('Section enrollment check by ID failed', e);
      return false;
    }
  }

  Future<List<DocumentSnapshot>> getSessionAttendance(String sessionId) async {
    try {
      final snapshot = await _firestore
          .collection(FirestorePaths.attendanceRecords)
          .where('sessionId', isEqualTo: sessionId)
          .get();
      return snapshot.docs;
    } catch (e, stackTrace) {
      ErrorHandler.logError('Failed to get session attendance', e, stackTrace);
      return [];
    }
  }

  Future<List<DocumentSnapshot>> getStudentAttendance(String studentId, String courseId) async {
    try {
      final snapshot = await _firestore
          .collection(FirestorePaths.attendanceRecords)
          .where('studentId', isEqualTo: studentId)
          .where('courseId', isEqualTo: courseId)
          .get();
      return snapshot.docs;
    } catch (e, stackTrace) {
      ErrorHandler.logError('Failed to get student attendance', e, stackTrace);
      return [];
    }
  }

  Future<SessionStatus> _checkSessionStatus(String sessionId, String courseId, String sectionId) async {
    try {
      final doc = await _firestore.collection(FirestorePaths.sessions).doc(sessionId).get();
      if (!doc.exists) return SessionStatus(false, 'Session does not exist');
      final data = doc.data()!;

      if (data['courseId'] != courseId || data['sectionId'] != sectionId) {
        return SessionStatus(false, 'Session does not match course or section');
      }

      final now = Timestamp.now();
      if (now.compareTo(data['startTime']) < 0) return SessionStatus(false, 'Session not started yet');
      if (now.compareTo(data['endTime']) > 0) return SessionStatus(false, 'Session already ended');
      if (data['isClosed'] == true) return SessionStatus(false, 'Session closed by lecturer');

      return SessionStatus(true, 'Session is active');
    } catch (e, stackTrace) {
      ErrorHandler.logError('Session check failed', e, stackTrace);
      return SessionStatus(false, 'Failed to check session: ${e.toString()}');
    }
  }

  Future<bool> updateAttendanceStatus({
    required String recordId,
    required String newStatus,
    String? reason,
  }) async {
    try {
      await _firestore.collection(FirestorePaths.attendanceRecords).doc(recordId).update({
        'status': newStatus,
        'reason': reason,
        'updatedAt': Timestamp.now(),
      });
      return true;
    } catch (e, stackTrace) {
      ErrorHandler.logError('Failed to update attendance status', e, stackTrace);
      return false;
    }
  }

  Future<List<DocumentSnapshot>> getLecturerSessions() async {
    try {
      final lecturerUid = _auth.currentUser?.uid;
      if (lecturerUid == null) return [];

      final sectionsSnapshot = await _firestore
          .collection(FirestorePaths.sections)
          .where('lecturerEmail', isEqualTo: lecturerUid)
          .get();

      final sectionIds = sectionsSnapshot.docs.map((doc) => doc.id).toList();
      if (sectionIds.isEmpty) return [];

      final sessionsSnapshot = await _firestore
          .collection(FirestorePaths.sessions)
          .where('sectionId', whereIn: sectionIds)
          .get();

      return sessionsSnapshot.docs;
    } catch (e, stackTrace) {
      ErrorHandler.logError('Failed to get lecturer sessions', e, stackTrace);
      return [];
    }
  }
}

class SessionStatus {
  final bool isActive;
  final String message;
  SessionStatus(this.isActive, this.message);
}

// Ensure AttendanceStatus is defined in utils/constants.dart
// For example:
// class AttendanceStatus {
//   static const String present = 'present';
//   static const String absent = 'absent';
//   static const String entryScanned = 'entry_scanned';
// }