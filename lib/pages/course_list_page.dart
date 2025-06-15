import 'package:flutter/material.dart';

class CourseListPage extends StatefulWidget {
  const CourseListPage({super.key});

  @override
  CourseListState createState() => CourseListState();
}

class CourseListState extends State<CourseListPage> {
  // Sample course data - replace with your Firestore data
  List<Map<String, dynamic>> courses = [
    {'courseTitle': 'Flutter Development', 'courseId': 'FLT001'},
    {'courseTitle': 'Dart Programming', 'courseId': 'DRT002'},
    {'courseTitle': 'Mobile App Design', 'courseId': 'MAD003'},
    {'courseTitle': 'Firebase Integration', 'courseId': 'FIR004'},
    {'courseTitle': 'State Management', 'courseId': 'STM005'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Session Manager',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          // COURSES Section
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  child: const Text(
                    'COURSES',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Course List
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: courses.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: ListTile(
                          title: Text(
                            courses[index]['courseTitle'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            courses[index]['courseId'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.grey,
                              size: 20,
                            ),
                            onPressed: () {
                              // Navigate to course details/classes page
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Navigate to classes for ${courses[index]['courseTitle']}',
                                  ),
                                ),
                              );
                            },
                          ),
                          onTap: () {
                            // Optional: Handle course selection
                            print('Selected course: ${courses[index]['courseTitle']}');
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          
          // CUSTOM EVENTS Button
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton(
              onPressed: () {
                // Navigate to custom events page
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Navigate to Custom Events page'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'CUSTOM EVENTS',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Example of how you might structure your Firestore data fetching
class FirestoreService {
  // Placeholder for Firestore integration
  Future<List<Map<String, dynamic>>> getCourses() async {
    // Replace this with actual Firestore query
    // Example:
    // QuerySnapshot snapshot = await FirebaseFirestore.instance
    //     .collection('courses')
    //     .get();
    // return snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    
    return [
      {'courseTitle': 'Flutter Development', 'courseId': 'FLT001'},
      {'courseTitle': 'Dart Programming', 'courseId': 'DRT002'},
      {'courseTitle': 'Mobile App Design', 'courseId': 'MAD003'},
    ];
  }
}