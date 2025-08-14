import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart'; // Added for logging
import '../main.dart'; // For AppRoutes

class CourseListPage extends StatefulWidget {
  const CourseListPage({super.key});

  @override
  CourseListPageState createState() => CourseListPageState();
}

class CourseListPageState extends State<CourseListPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Logger _logger = Logger(); // Initialize logger
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
      _logger.e('Firebase error loading sections: ${e.code} - ${e.message}');
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: $e';
      _logger.e('Error loading sections: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Create new custom section ---
  Future<void> _showCreateNewCustomSectionDialog() async {
    final TextEditingController sectionTitleController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create New Custom Section'),
          content: TextField(
            controller: sectionTitleController,
            decoration: const InputDecoration(hintText: 'Enter section title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (sectionTitleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Section title cannot be empty.')),
                  );
                  return;
                }
                await _createCustomSection(sectionTitleController.text.trim());
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF4A460), // Changed button color
                foregroundColor: Colors.white, // Changed text color
              ),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createCustomSection(String sectionTitle) async {
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in.');
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      await _firestore.collection('sections').add({
        'sectionTitle': sectionTitle,
        'lecturerEmail': _lecturerUid,
        'sectionType': 'custom',
        'courseId': 'CUSTOM_SECTION_GENERATED',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _showSuccessSnackBar('Custom section "$sectionTitle" created successfully!');
      _loadAllSections();
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to create custom section: ${e.message}');
      _logger.e('Error creating custom section: ${e.code} - ${e.message}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- Show dialog for adding participants to a custom section ---
  Future<void> _showAddParticipantsDialog(String sectionId, String sectionTitle) async {
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in.');
      return;
    }

    List<String> validStudentIds = [];
    try {
  final studentSnapshot = await _firestore.collection('students').get();
  validStudentIds = studentSnapshot.docs
      .map((doc) => doc.data()['studentId']?.toString())
      .where((id) => id != null)
      .cast<String>()
      .toList();
  _logger.i('Valid student IDs fetched: $validStudentIds');
} catch (e) {
      _logger.e('Error fetching student IDs: $e');
      _showErrorSnackBar('Failed to load student list: $e');
      return;
    }

    final TextEditingController studentIdsController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Add Participants to "$sectionTitle"'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter student IDs (e.g., 12345, 67890) separated by commas.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<String>.empty();
                  }
                  return validStudentIds.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  if (studentIdsController.text.isEmpty) {
                    studentIdsController.text = selection;
                  } else {
                    studentIdsController.text += ', $selection';
                  }
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  studentIdsController.text = controller.text;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      hintText: 'e.g., 12345, 67890',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    keyboardType: TextInputType.text,
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (studentIdsController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Student IDs cannot be empty.')),
                  );
                  return;
                }
                await _addParticipantsToSection(sectionId, studentIdsController.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF4A460), // Changed button color
                foregroundColor: Colors.white, // Changed text color
              ),
              child: const Text('Add Participants'),
            ),
          ],
        );
      },
    );
  }

  // --- Add participants to a custom section with ownership check ---
  Future<void> _addParticipantsToSection(String sectionId, String studentIdsString) async {
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in. Cannot add participants.');
      return;
    }

    _logger.i('Current user: UID=${_auth.currentUser?.uid}, Email=${_auth.currentUser?.email}');
    _logger.i('Raw input student IDs: $studentIdsString');

    try {
      final sectionDoc = await _firestore.collection('sections').doc(sectionId).get();
      if (!sectionDoc.exists) {
        _showErrorSnackBar('Section not found.');
        return;
      }
      final sectionData = sectionDoc.data();
      if (sectionData?['lecturerEmail'] != _lecturerUid || sectionData?['sectionType'] != 'custom') {
        _showErrorSnackBar('Unauthorized: You can only add participants to custom sections you created.');
        return;
      }

      final List<String> studentIds = studentIdsString
          .split(',')
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList();

      _logger.i('Parsed student IDs: $studentIds');

      if (studentIds.isEmpty) {
        _showErrorSnackBar('No valid student IDs provided.');
        return;
      }

      int addedCount = 0;
      int notFoundCount = 0;
      int alreadyEnrolledCount = 0;
      List<String> notFoundIds = [];

      for (final inputStudentId in studentIds) {
        _logger.i('Querying for student with studentId: $inputStudentId');
        final querySnapshot = await _firestore
            .collection('students')
            .where('studentId', isEqualTo: inputStudentId)
            .limit(1)
            .get();

        if (querySnapshot.docs.isEmpty) {
          _logger.i('No student found with studentId: $inputStudentId');
          notFoundCount++;
          notFoundIds.add(inputStudentId);
          continue;
        }

        final studentDoc = querySnapshot.docs.first;
        final studentDocId = studentDoc.id;
        _logger.i('Found student with studentId: $inputStudentId, Document ID: $studentDocId');

        await _firestore.runTransaction((transaction) async {
          final studentDocRef = _firestore.collection('students').doc(studentDocId);
          final studentDocSnapshot = await transaction.get(studentDocRef);

          if (studentDocSnapshot.exists) {
            final currentEnrolledSections = (studentDocSnapshot.data()?['enrolledSections'] as List<dynamic>?)?.cast<String>() ?? [];
            _logger.i('Current enrolled sections for $studentDocId: $currentEnrolledSections');
            if (!currentEnrolledSections.contains(sectionId)) {
              transaction.update(studentDocRef, {
                'enrolledSections': FieldValue.arrayUnion([sectionId]),
              });
              addedCount++;
            } else {
              alreadyEnrolledCount++;
            }
          } else {
            _logger.w('Student document $studentDocId disappeared during transaction');
            notFoundCount++;
            notFoundIds.add(inputStudentId);
          }
        });
      }

      String message = 'Enrollment complete:';
      if (addedCount > 0) message += ' $addedCount student(s) enrolled successfully.';
      if (alreadyEnrolledCount > 0) message += ' $alreadyEnrolledCount student(s) already enrolled.';
      if (notFoundCount > 0) message += ' $notFoundCount student(s) not found: ${notFoundIds.join(", ")}';

      _showSuccessSnackBar(message);
    } on FirebaseException catch (e) {
      _logger.e('Firebase error: ${e.code} - ${e.message}');
      _showErrorSnackBar('Failed to add participants: ${e.message}');
    } catch (e) {
      _logger.e('Unexpected error: $e');
      _showErrorSnackBar('An unexpected error occurred: $e');
    } finally {
      if (mounted) Navigator.pop(context); // Close dialog after adding participants
    }
  }

  // --- Show dialog for renaming a custom section ---
  Future<void> _showRenameSectionDialog(String sectionId, String currentTitle) async {
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in.');
      return;
    }
    final TextEditingController newTitleController = TextEditingController(text: currentTitle);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Section'),
          content: TextField(
            controller: newTitleController,
            decoration: const InputDecoration(hintText: 'Enter new section title'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (newTitleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Section title cannot be empty.')),
                  );
                  return;
                }
                await _renameCustomSection(newTitleController.text.trim(), sectionId); // Corrected argument order
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF4A460), // Changed button color
                foregroundColor: Colors.white, // Changed text color
              ),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }

  // --- Reusable Ownership Check for Custom Sections ---
  Future<bool> _isUserOwnerOfCustomSection(String sectionId) async {
    final sectionDoc = await _firestore.collection('sections').doc(sectionId).get();
    if (!sectionDoc.exists) return false;

    final data = sectionDoc.data();
    return data?['lecturerEmail'] == _lecturerUid && data?['sectionType'] == 'custom';
  }

  // --- Rename a custom section with ownership check ---
  Future<void> _renameCustomSection(String newTitle, String sectionId) async { // Corrected argument order
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in. Cannot rename section.');
      return;
    }

    final isOwner = await _isUserOwnerOfCustomSection(sectionId);
    if (!isOwner) {
      _showErrorSnackBar('Unauthorized: You can only rename custom sections you created.');
      return;
    }

    try {
      await _firestore.collection('sections').doc(sectionId).update({
        'sectionTitle': newTitle,
      });
      _showSuccessSnackBar('Section renamed to "$newTitle" successfully!');
      _loadAllSections();
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to rename section: ${e.message}');
      _logger.e('Firebase error renaming section: ${e.code} - ${e.message}');
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
      _logger.e('Error renaming section: $e');
    }
  }

  // --- Delete a custom section with ownership check ---
  Future<void> _deleteCustomSection(String sectionId, String sectionTitle) async {
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in. Cannot delete section.');
      return;
    }

    final isOwner = await _isUserOwnerOfCustomSection(sectionId);
    if (!isOwner) {
      _showErrorSnackBar('Unauthorized: You can only delete custom sections you created.');
      return;
    }

    final confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Section'),
            content: Text('Are you sure you want to delete "$sectionTitle" and all its sessions? This action cannot be undone.'),
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

    try {
      final sessionSnapshot = await _firestore
          .collection('sessions')
          .where('sectionId', isEqualTo: sectionId)
          .get();
      for (var doc in sessionSnapshot.docs) {
        await doc.reference.delete();
      }

      final studentSnapshot = await _firestore
          .collection('students')
          .where('enrolledSections', arrayContains: sectionId)
          .get();
      for (var studentDoc in studentSnapshot.docs) {
        if (studentDoc.data() != null) {
          await studentDoc.reference.update({
            'enrolledSections': FieldValue.arrayRemove([sectionId]),
          });
        }
      }

      await _firestore.collection('sections').doc(sectionId).delete();

      _showSuccessSnackBar('Section "$sectionTitle" and its sessions deleted successfully!');
      _loadAllSections();
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to delete section: ${e.message}');
      _logger.e('Firebase error deleting section: ${e.code} - ${e.message}');
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
      _logger.e('Error deleting section: $e');
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
        title: const Text(
          'Manage Sections',
          style: TextStyle(color: Color(0xFFFFFDD0)), // Changed text color
        ),
        backgroundColor: const Color(0xFF8B0000), // Changed bar color
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
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
                    style: TextStyle(fontSize: 18, color: Color(0xFFFFFDD0)), // Changed text color
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF4A460), // Changed button color
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
                                final bool isOwnedByMe = _lecturerUid == section['lecturerEmail'];

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12.0),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                  color: isCustom ? Colors.white : Colors.white, // Custom sections will have their own color
                                  child: ListTile(
                                    leading: Icon(
                                      isCustom ? Icons.folder_special : Icons.folder,
                                      color: isCustom ? const Color(0xFFF4A460) : const Color(0xFF8B0000), // Changed folder colors
                                    ),
                                    title: Text(
                                      section['sectionTitle'] ?? 'Unnamed Section',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isCustom ? const Color(0xFFF4A460) : Colors.black87, // Changed text color
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Course: ${section['courseId'] ?? 'N/A'}' + (isCustom ? ' (Custom)' : ''),
                                      style: TextStyle(color: Colors.grey[700]),
                                    ),
                                    trailing: isCustom && isOwnedByMe
                                        ? PopupMenuButton<String>(
                                            onSelected: (value) {
                                              if (value == 'add_participants') {
                                                _showAddParticipantsDialog(section['id'], section['sectionTitle']);
                                              } else if (value == 'rename_section') {
                                                _showRenameSectionDialog(section['id'], section['sectionTitle']);
                                              } else if (value == 'delete_section') {
                                                _deleteCustomSection(section['id'], section['sectionTitle']);
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
                                            icon: const Icon(Icons.settings, color: Colors.grey), // Changed icon to settings gear
                                          )
                                        : const Icon(Icons.arrow_forward_ios, color: Colors.grey),
                                    onTap: () {
                                      Navigator.pushNamed(
                                        context,
                                        AppRoutes.sessionPage,
                                        arguments: {
                                          'courseId': section['courseId'] ?? 'N/A',
                                          'documentId': section['id'],
                                        },
                                      ).then((_) => _loadAllSections());
                                    },
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
