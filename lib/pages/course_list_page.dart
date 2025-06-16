import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';

class CourseListPage extends StatefulWidget {
  const CourseListPage({super.key});

  @override
  CourseListState createState() => CourseListState();
}

class CourseListState extends State<CourseListPage> {
  // This list will hold our Firestore data
  List<Map<String, dynamic>> courses = [];
  bool isLoading = true; // Track loading state
  String errorMessage = ''; // Track any errors

  @override
  void initState() {
    super.initState();
    // Load courses when the page initializes
    loadCourses();
  }

  // Function to load courses from Firestore
  Future<void> loadCourses() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });

      //get logged in users uid
      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      //if null uid, dont show courses and exit
      if (currentUid == null) {
        setState(() { isLoading = false; });
        return;
      }

      // 1. Query Firestore collection for lecturer specific section
      QuerySnapshot lecturerSectionsSnapshot = await FirebaseFirestore.instance
          .collection('sections') // collection name
          .where('lecturerEmail', isEqualTo: currentUid) // Filter by the lecturer's UID
          .get();

      // 2. Query firestore for "custom" section
      QuerySnapshot customSectionsSnapshot = await FirebaseFirestore.instance
          .collection('sections')
          .where('sectionType', isEqualTo: 'custom') // Filter for 'custom' sectionType
          .get();

      // Convert Firestore documents to our course list
      List<Map<String, dynamic>> loadedCourses = [];

      //lecturer specific query
      for (QueryDocumentSnapshot doc in lecturerSectionsSnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['documentId'] = doc.id;
        loadedCourses.add(data);
      }

      //custom query
      for (QueryDocumentSnapshot doc in customSectionsSnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['documentId'] = doc.id;
        if (!loadedCourses.any((course) => course['documentId'] == data['documentId'])) {
          loadedCourses.add(data);
        }
      }

      setState(() {
        courses = loadedCourses;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading courses: $e';
        isLoading = false;
      });
      print('Error loading courses: $e');
    }
  }

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
                    'CLASS SECTIONS',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Course List with loading and error handling
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: isLoading
                      ? // Show loading indicator while data is being fetched
                      const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : errorMessage.isNotEmpty
                          ? // Show error message if something went wrong
                          Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Text(
                                  errorMessage,
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : courses.isEmpty
                              ? // Show message when no courses are found
                              const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(20.0),
                                    child: Text('No courses found'),
                                  ),
                                )
                              : // Show the actual course list
                              ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: courses.length,
                                  itemBuilder: (context, index) {
                                    // Get individual course data
                                    Map<String, dynamic> course = courses[index];
                                    
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
                                        // Display section title from Firestore
                                        title: Text(
                                          course['sectionTitle'] ?? 'No Title',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        // Display course ID from Firestore
                                        subtitle: Text(
                                          course['courseId'] ?? 'No ID',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        trailing: Text(
                                            '»', style: TextStyle(
                                              fontSize: 24,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.bold,
                                            ),
                                        ),
                                        onTap: () {
                                          Navigator.pushNamed(
                                            context,
                                            AppRoutes.sessionPage,  // This resolves to '/session-page'
                                            arguments: {
                                              'courseId': course['courseId'],
                                              'documentId': course['documentId'],
                                              },
                                              );
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
        ],
      ),
    );
  }
}

// Additional helper methods for more advanced Firestore operations
extension CourseListPageExtensions on CourseListState {
  
  // Method to refresh the course list (useful for pull-to-refresh)
  Future<void> refreshCourses() async {
    await loadCourses();
  }
  
  // Method to filter courses by a specific field (optional)
  Future<void> loadCoursesByFilter(String field, dynamic value) async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = '';
      });

      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('sections')
          .where(field, isEqualTo: value)
          .get();

      List<Map<String, dynamic>> loadedCourses = [];
      for (QueryDocumentSnapshot doc in querySnapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['documentId'] = doc.id;
        loadedCourses.add(data);
      }

      setState(() {
        courses = loadedCourses;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading filtered courses: $e';
        isLoading = false;
      });
    }
  }
}