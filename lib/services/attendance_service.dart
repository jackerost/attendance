import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/constants.dart';
import '../utils/error_handler.dart';
import 'package:logger/logger.dart';

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
  }) async {
    try {
      // Existing session status check
      final sessionStatus = await _checkSessionStatus(sessionId, courseId, sectionId);
      if (!sessionStatus.isActive) return 'Session is not active: ${sessionStatus.message}';

      // New: Check if student is enrolled in this specific section
      final isEnrolled = await _isStudentEnrolledInSection(studentId, sectionId);
      if (!isEnrolled) return 'Student not enrolled in this section';

      // Existing duplicate check
      final isDuplicate = await _checkForDuplicateAttendance(sessionId, studentId);
      if (isDuplicate) return 'Already marked present for this session';

      await _firestore.collection(FirestorePaths.attendanceRecords).add({
        'sessionId': sessionId,
        'studentId': studentId,
        'courseId': courseId,
        'sectionId': sectionId,
        'timestamp': Timestamp.now(),
        'status': AttendanceStatus.present,
      });

      return 'Attendance marked successfully';
    } catch (e, stackTrace) {
      ErrorHandler.logError('Failed to mark attendance', e, stackTrace);
      return 'Failed to mark attendance: ${e.toString()}';
    }
  }
  //New Helper Method
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

  Future<bool> _checkForDuplicateAttendance(String sessionId, String studentId) async {
    try {
      final snapshot = await _firestore
          .collection(FirestorePaths.attendanceRecords)
          .where('sessionId', isEqualTo: sessionId)
          .where('studentId', isEqualTo: studentId)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e, stackTrace) {
      ErrorHandler.logError('Duplicate check failed', e, stackTrace);
      throw Exception('Duplicate check failed: ${e.toString()}');
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

  /// Retrieves all sessions assigned to the currently logged-in lecturer
  Future<List<DocumentSnapshot>> getLecturerSessions() async {
    try {
      final lecturerUid = _auth.currentUser?.uid; //.uid so uses uid
      if (lecturerUid == null) return [];

      final sectionsSnapshot = await _firestore
          .collection(FirestorePaths.sections)
          .where('lecturerEmail', isEqualTo: lecturerUid) //now field lecturerEmail uses uid
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
