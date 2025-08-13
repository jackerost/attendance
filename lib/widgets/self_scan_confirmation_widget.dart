import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/student.dart';

class SelfScanConfirmationWidget extends StatelessWidget {
  final Student student;
  final Map<String, dynamic> sessionData;
  final String attendanceType;
  
  const SelfScanConfirmationWidget({
    super.key,
    required this.student,
    required this.sessionData,
    required this.attendanceType, // 'entry' or 'exit'
  });

  @override
  Widget build(BuildContext context) {
    final String attendanceTypeDisplay = attendanceType == 'entry' 
        ? 'Entry Attendance Accepted' 
        : 'Exit Attendance Accepted';
        
    // Format session start and end time
    String timeRangeText = '';
    if (sessionData['startTime'] != null && sessionData['endTime'] != null) {
      final startTime = (sessionData['startTime'] as Timestamp).toDate();
      final endTime = (sessionData['endTime'] as Timestamp).toDate();
      timeRangeText = '${DateFormat('h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Attendance type header
          Text(
            attendanceTypeDisplay,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Main card with green border as shown in figure 6
          Container(
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Student photo
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: student.photoUrl != null && student.photoUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              student.photoUrl!,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Text(
                                    'PROFILE\nPHOTO HERE',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.black54,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        : const Center(
                            child: Text(
                              'PROFILE\nPHOTO HERE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Student name
                  Text(
                    student.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Student ID
                  Text(
                    student.studentId,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  const SizedBox(height: 16),
                  const Divider(height: 1, thickness: 1),
                  const SizedBox(height: 16),
                  
                  // Session info
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.school, size: 16, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text(
                        '[${sessionData['title'] ?? 'Lecture'}]',
                        style: const TextStyle(
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        sessionData['courseId'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Session time
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.access_time, size: 16, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text(
                        timeRangeText,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Session section ID
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.groups, size: 16, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text(
                        sessionData['sectionId'] ?? '',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
