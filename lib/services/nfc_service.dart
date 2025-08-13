import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';
import 'package:logger/logger.dart';

class NFCService {
  final logger = Logger();

  /// Scan NFC tag and return just the tag ID
  /// 
  /// This method only scans the tag and returns its ID without querying Firestore
  /// Useful for security verification workflows
  Future<String?> scanTag() async {
    try {
      // Start scanning
      final tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 15));
      final tagId = tag.id;
      
      // Always finish the NFC session
      await FlutterNfcKit.finish();
      
      return tagId;
    } catch (e) {
      logger.e('NFC scan error', error: e);
      await FlutterNfcKit.finish();
      return null;
    }
  }

  Future<Student?> scanAndFetchStudent() async {
    try {
      // Start scanning
      final tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 15));
      final tagId = tag.id;

      // Fetch matching student from Firestore
      final query = await FirebaseFirestore.instance
          .collection('students')
          .where('tagId', isEqualTo: tagId)
          .limit(1)
          .get();

      await FlutterNfcKit.finish();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final data = doc.data();

        return Student(
          id: tagId,
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          studentId: data['studentId'] ?? '',
          photoUrl: data['photoUrl'],
          enrolledSections: List<String>.from(data['enrolledSections'] ?? []),
          tagId: tagId, // Include tagId in the Student object
          //department: data['department'] ?? '',
          //yearOfStudy: data['yearOfStudy'] ?? 1,
          //program: data['program'] ?? '',
          //isActive: data['isActive'] ?? true,
          //intake: timestamp.toDate(),
          //metadata: data['metadata'],
        );
      }
    } catch (e) {
      logger.e('NFC scan error', error: e);
      await FlutterNfcKit.finish();
    }
    return null;
  }
}
