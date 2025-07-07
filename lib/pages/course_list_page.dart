import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../main.dart'; // For AppRoutes
import 'session_manager_page.dart'; // For navigating to manage sessions for a specific section

class CourseListPage extends StatefulWidget {
  const CourseListPage({super.key});

  @override
  CourseListPageState createState() => CourseListPageState();
}

class CourseListPageState extends State<CourseListPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _lecturerUid;
  String? _lecturerEmail; // Keep this for clarity, but _lecturerUid will be used for 'lecturerEmail' field in Firestore
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _allSections = []; // Combined list of all sections

  @override
  void initState() {
    super.initState();
    _lecturerUid = _auth.currentUser?.uid;
    _lecturerEmail = _auth.currentUser?.email; // Store email for display/logging if needed

    if (_lecturerUid == null || _lecturerEmail == null) {
      _errorMessage = 'User not logged in or email not found.';
      _isLoading = false;
    } else {
      _loadAllSections();
    }
  }

  // Method to load all sections (regular and custom)
  Future<void> _loadAllSections() async {
    if (_lecturerUid == null || _lecturerEmail == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _allSections = [];
    });

    try {
      final List<Map<String, dynamic>> loadedSections = [];

      // 1. Fetch regular sections where the lecturer's UID (stored in 'lecturerEmail') matches
      //    This aligns with Firestore rules that check 'lecturerEmail' for ownership.
      final QuerySnapshot regularSectionsSnapshot = await _firestore
          .collection('sections')
          .where('sectionType', isEqualTo: 'regular')
          .where('lecturerEmail', isEqualTo: _lecturerUid) // Use _lecturerUid to match 'lecturerEmail' in Firestore
          .get();

      for (var doc in regularSectionsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        loadedSections.add(data);
      }

      // 2. Fetch custom sections created by the current lecturer (using UID stored in 'lecturerEmail')
      //    Aligns with Firestore rules for 'lecturerEmail' ownership.
      final QuerySnapshot customSectionsSnapshot = await _firestore
          .collection('sections')
          .where('lecturerEmail', isEqualTo: _lecturerUid) // Use _lecturerUid to match 'lecturerEmail' in Firestore
          .where('sectionType', isEqualTo: 'custom')
          .get();

      for (var doc in customSectionsSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id; // Store document ID
        loadedSections.add(data);
      }

      // Sort sections by title for better display
      loadedSections.sort((a, b) => (a['sectionTitle'] ?? '').compareTo(b['sectionTitle'] ?? ''));

      setState(() {
        _allSections = loadedSections;
      });
    } on FirebaseException catch (e) {
      _errorMessage = 'Failed to load sections: ${e.message}';
      print('Firebase error loading sections: ${e.code} - ${e.message}');
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: $e';
      print('Error loading sections: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Create new custom section ---
  Future<void> _showCreateNewCustomSectionDialog() async {
    final TextEditingController sectionTitleController = TextEditingController(); // Renamed to sectionTitleController
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create New Custom Section'),
          content: TextField(
            controller: sectionTitleController, // Use sectionTitleController
            decoration: const InputDecoration(hintText: 'Enter section title'), // Updated hint text
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (sectionTitleController.text.trim().isEmpty) { // Check sectionTitleController
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Section title cannot be empty.')), // Updated message
                  );
                  return;
                }
                await _createCustomSection(sectionTitleController.text.trim()); // Pass sectionTitle
                if (mounted) Navigator.pop(context); // Close the dialog
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createCustomSection(String sectionTitle) async { // Renamed parameter to sectionTitle
    if (_lecturerUid == null) { // Only UID is relevant here for Firestore rule matching
      _showErrorSnackBar('User not logged in.');
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      await _firestore.collection('sections').add({
        'sectionTitle': sectionTitle, // Use sectionTitle
        'lecturerEmail': _lecturerUid, // Store UID in 'lecturerEmail' to match rules
        'sectionType': 'custom',
        'courseId': 'CUSTOM_SECTION_GENERATED', // Consistent placeholder for custom sections
        'createdAt': FieldValue.serverTimestamp(), // Use 'createdAt' to match rules
      });
      _showSuccessSnackBar('Custom section "$sectionTitle" created successfully!'); // Updated message
      _loadAllSections(); // Reload list to include the new section
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to create custom section: ${e.message}');
      print('Error creating custom section: ${e.code} - ${e.message}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Show dialog for adding participants to a custom section ---
  Future<void> _showAddParticipantsDialog(String sectionId, String sectionTitle) async { // Renamed sectionName to sectionTitle
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in.');
      return;
    }
    final TextEditingController studentIdsController = TextEditingController(); // Renamed to studentIdsController for bulk input
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Participants to "$sectionTitle"'), // Use sectionTitle
          content: TextField(
            controller: studentIdsController, // Use studentIdsController
            decoration: const InputDecoration(hintText: 'Enter student IDs (comma-separated)'), // Updated hint for bulk input
            maxLines: 3, // Allow multiple lines for bulk input
            keyboardType: TextInputType.multiline,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (studentIdsController.text.trim().isEmpty) { // Check studentIdsController
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Student IDs cannot be empty.')),
                  );
                  return;
                }
                // Pass sectionId and the comma-separated string for bulk processing
                await _addParticipantsToSection(sectionId, studentIdsController.text.trim());
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Add Participants'), // Updated button text
            ),
          ],
        );
      },
    );
  }

  // --- Add participants to a custom section with ownership check ---
  Future<void> _addParticipantsToSection(String sectionId, String studentIdsString) async { // Renamed to _addParticipantsToSection
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in. Cannot add participants.');
      return;
    }

    try {
      final sectionDoc = await _firestore.collection('sections').doc(sectionId).get();
      if (!sectionDoc.exists) {
        _showErrorSnackBar('Section not found.');
        return;
      }
      final sectionData = sectionDoc.data();
      // Ownership check: Use 'lecturerEmail' field for UID comparison
      if (sectionData?['lecturerEmail'] != _lecturerUid || sectionData?['sectionType'] != 'custom') {
        _showErrorSnackBar('Unauthorized: You can only add participants to custom sections you created.');
        return;
      }

      final List<String> studentIds = studentIdsString
          .split(',')
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList();

      if (studentIds.isEmpty) {
        _showErrorSnackBar('No valid student IDs found to add.');
        return;
      }

      int addedCount = 0;
      int notFoundCount = 0;
      int alreadyEnrolledCount = 0;

      for (final studentId in studentIds) {
        final studentDocRef = _firestore.collection('students').doc(studentId);
        
        // Use a transaction to safely update and check existence
        await _firestore.runTransaction((transaction) async {
          final studentDocSnapshot = await transaction.get(studentDocRef);

          if (studentDocSnapshot.exists) {
            final currentEnrolledSections = (studentDocSnapshot.data()?['enrolledSections'] as List<dynamic>?)?.cast<String>() ?? [];

            if (!currentEnrolledSections.contains(sectionId)) {
              transaction.update(studentDocRef, {
                'enrolledSections': FieldValue.arrayUnion([sectionId]),
              });
              addedCount++;
            } else {
              alreadyEnrolledCount++;
            }
          } else {
            notFoundCount++;
          }
        });
      }

      String message = 'Enrollment complete:';
      if (addedCount > 0) message += ' $addedCount student(s) enrolled successfully.';
      if (alreadyEnrolledCount > 0) message += ' $alreadyEnrolledCount student(s) already enrolled.';
      if (notFoundCount > 0) message += ' $notFoundCount student(s) not found.';

      _showSuccessSnackBar(message);

    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to add participants: ${e.message}');
      print('Firebase error adding participants: ${e.code} - ${e.message}');
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
    }
  }

  // --- Show dialog for renaming a custom section ---
  Future<void> _showRenameSectionDialog(String sectionId, String currentTitle) async { // Renamed currentName to currentTitle
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in.');
      return;
    }
    final TextEditingController newTitleController = TextEditingController(text: currentTitle); // Renamed controller
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Section'),
          content: TextField(
            controller: newTitleController, // Use newTitleController
            decoration: const InputDecoration(hintText: 'Enter new section title'), // Updated hint
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newTitleController.text.trim().isEmpty) { // Check newTitleController
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Section title cannot be empty.')), // Updated message
                  );
                  return;
                }
                await _renameCustomSection(sectionId, newTitleController.text.trim()); // Pass new title
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }

  // --- Rename a custom section with ownership check ---
  Future<void> _renameCustomSection(String sectionId, String newTitle) async { // Renamed newName to newTitle
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in. Cannot rename section.');
      return;
    }

    try {
      final sectionDoc = await _firestore.collection('sections').doc(sectionId).get();
      if (!sectionDoc.exists) {
        _showErrorSnackBar('Section not found.');
        return;
      }
      final sectionData = sectionDoc.data();
      // Ownership check: Use 'lecturerEmail' field for UID comparison
      if (sectionData?['lecturerEmail'] != _lecturerUid || sectionData?['sectionType'] != 'custom') {
        _showErrorSnackBar('Unauthorized: You can only rename custom sections you created.');
        return;
      }

      await _firestore.collection('sections').doc(sectionId).update({
        'sectionTitle': newTitle, // Update 'sectionTitle'
      });
      _showSuccessSnackBar('Section renamed to "$newTitle" successfully!'); // Updated message
      _loadAllSections(); // Reload list to reflect the name change
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to rename section: ${e.message}');
      print('Firebase error renaming section: ${e.code} - ${e.message}');
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
    }
  }

  // --- Delete a custom section with ownership check ---
  Future<void> _deleteCustomSection(String sectionId, String sectionTitle) async { // Renamed sectionName to sectionTitle
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in. Cannot delete section.');
      return;
    }

    try {
      final sectionDoc = await _firestore.collection('sections').doc(sectionId).get();
      if (!sectionDoc.exists) {
        _showErrorSnackBar('Section not found for deletion.');
        return;
      }
      final sectionData = sectionDoc.data();
      // Ownership check: Use 'lecturerEmail' field for UID comparison
      if (sectionData?['lecturerEmail'] != _lecturerUid || sectionData?['sectionType'] != 'custom') {
        _showErrorSnackBar('Unauthorized: You can only delete custom sections you created.');
        return;
      }

      final bool confirm = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Section'),
              content: Text('Are you sure you want to delete "$sectionTitle" and all its sessions? This action cannot be undone.'), // Use sectionTitle
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false;

      if (!confirm) return;

      // 1. Delete all sessions linked to this section
      final QuerySnapshot sessionSnapshot = await _firestore
          .collection('sessions')
          .where('sectionId', isEqualTo: sectionId)
          .get();
      for (DocumentSnapshot doc in sessionSnapshot.docs) {
        await doc.reference.delete();
      }

      // 2. Remove this section from all students' 'enrolledSections'
      final QuerySnapshot studentSnapshot = await _firestore
          .collection('students')
          .where('enrolledSections', arrayContains: sectionId)
          .get();
      for (DocumentSnapshot studentDoc in studentSnapshot.docs) {
        // Ensure studentDoc.data() is not null before casting
        if (studentDoc.data() != null) {
          await studentDoc.reference.update({
            'enrolledSections': FieldValue.arrayRemove([sectionId]),
          });
        }
      }

      // 3. Delete the section document itself
      await _firestore.collection('sections').doc(sectionId).delete();

      _showSuccessSnackBar('Section "$sectionTitle" and its sessions deleted successfully!'); // Use sectionTitle
      _loadAllSections(); // Reload the list of sections
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to delete section: ${e.message}');
      print('Firebase error deleting section: ${e.code} - ${e.message}');
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
    }
  }

  // Helper for snackbars
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Sections'),
        backgroundColor: const Color(0xFF1976D2), // Changed to match your design
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _showCreateNewCustomSectionDialog,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Create New Custom Section',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[600],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage))
                    : _allSections.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'No sections found. Create your first custom section above!',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: _allSections.length,
                            itemBuilder: (context, index) {
                              final section = _allSections[index];
                              final bool isCustom = section['sectionType'] == 'custom';
                              // Ownership check: Now uses 'lecturerEmail' field for UID comparison
                              final bool isOwnedByMe = _lecturerUid == section['lecturerEmail'];

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12.0),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                color: isCustom ? Colors.orange[50] : Colors.white, // Orange tint for custom sections
                                child: ListTile(
                                  leading: Icon(
                                    isCustom ? Icons.folder_special : Icons.folder,
                                    color: isCustom ? Colors.orange[700] : Colors.blue[600],
                                  ),
                                  title: Text(
                                    section['sectionTitle'] ?? 'Unnamed Section', // Use 'sectionTitle'
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isCustom ? Colors.orange[800] : Colors.black87,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Course: ${section['courseId'] ?? 'N/A'}' + (isCustom ? ' (Custom)' : ''),
                                    style: TextStyle(color: Colors.grey[700]),
                                  ),
                                  trailing: isCustom && isOwnedByMe // Show actions only for custom sections owned by the user
                                      ? PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'add_participants') {
                                              _showAddParticipantsDialog(section['id'], section['sectionTitle']); // Pass sectionTitle
                                            } else if (value == 'rename_section') {
                                              _showRenameSectionDialog(section['id'], section['sectionTitle']); // Pass sectionTitle
                                            } else if (value == 'delete_section') {
                                              _deleteCustomSection(section['id'], section['sectionTitle']); // Pass sectionTitle
                                            }
                                          },
                                          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                            const PopupMenuItem<String>(
                                              value: 'add_participants',
                                              child: ListTile(
                                                leading: Icon(Icons.group_add),
                                                title: Text('Add Participants'),
                                              ),
                                            ),
                                            const PopupMenuItem<String>(
                                              value: 'rename_section',
                                              child: ListTile(
                                                leading: Icon(Icons.edit),
                                                title: Text('Rename Section'),
                                              ),
                                            ),
                                            const PopupMenuItem<String>(
                                              value: 'delete_section',
                                              child: ListTile(
                                                leading: Icon(Icons.delete_forever, color: Colors.red),
                                                title: Text('Delete Section'),
                                              ),
                                            ),
                                          ],
                                          icon: const Icon(Icons.more_vert, color: Colors.grey),
                                        )
                                      : const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                                  onTap: () {
                                    // Navigate to SessionManagerPage to manage sessions for this specific section
                                    Navigator.pushNamed(
                                      context,
                                      AppRoutes.sessionPage,
                                      arguments: {
                                        'courseId': section['courseId'] ?? 'N/A',
                                        'documentId': section['id'], // 'id' is the Firestore document ID
                                      },
                                    ).then((_) => _loadAllSections()); // Reload sections when returning
                                  },
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}