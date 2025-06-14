import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/student.dart';
import 'package:logger/logger.dart';

class NFCService {
  final logger = Logger();

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

        final Timestamp timestamp = data['intake'] is Timestamp 
            ? data['intake'] 
            : Timestamp.now();

        return Student(
          id: tagId,
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          studentId: data['studentId'] ?? '',
          photoUrl: data['photoUrl'],
          enrolledSections: List<String>.from(data['enrolledSections'] ?? []),
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
