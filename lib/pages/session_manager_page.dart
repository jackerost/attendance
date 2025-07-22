import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class SessionManagerPage extends StatefulWidget {
  final String courseId;
  final String documentId; // This is the sectionId

  const SessionManagerPage({
    super.key,
    required this.courseId,
    required this.documentId,
  });

  @override
  SessionManagerState createState() => SessionManagerState();
}

class SessionManagerState extends State<SessionManagerPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _lecturerUid; // Stores the lecturer's UID
  String _errorMessage = '';
  bool _isLoading = true;
  List<Map<String, dynamic>> _sessions = [];
  bool _isCustomSection = false;
  String _sectionTitle = ''; // Will store sectionTitle

  @override
  void initState() {
    super.initState();
    _lecturerUid = _auth.currentUser?.uid; // Get the UID
    if (_lecturerUid == null) {
      _errorMessage = 'User not logged in or UID not found.';
      _isLoading = false;
    } else {
      _checkSectionType();
      _loadSessions();
    }
  }

  Future<void> _checkSectionType() async {
    try {
      final sectionDoc = await _firestore
          .collection('sections')
          .doc(widget.documentId)
          .get();
      
      if (sectionDoc.exists) {
        final sectionData = sectionDoc.data() as Map<String, dynamic>;
        _isCustomSection = sectionData['sectionType'] == 'custom';
        // Use 'sectionTitle' for consistency
        _sectionTitle = sectionData['sectionTitle'] ?? 'Unknown Section';
      }
    } catch (e) {
      print('Error checking section type: $e');
      setState(() {
        _errorMessage = 'Error loading section details.';
      });
    }
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (_lecturerUid == null) {
        _errorMessage = 'Lecturer UID is null.';
        _isLoading = false;
        return;
      }

      final QuerySnapshot sessionSnapshot = await _firestore
          .collection('sessions')
          .where('lecturerEmail', isEqualTo: _lecturerUid) // Filter by lecturer's UID stored in 'lecturerEmail'
          .where('sectionId', isEqualTo: widget.documentId)
          .orderBy('startTime', descending: false)
          .get();

      _sessions = sessionSnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['sessionId'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      _errorMessage = 'Error loading sessions: $e';
      print('Error loading sessions: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSessionDetailsPopup(Map<String, dynamic> session) {
    // Compare with UID stored in 'lecturerEmail' field
    bool canEdit = _lecturerUid == session['lecturerEmail']; 
    bool canDelete = _isCustomSection && canEdit;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Session Details'),
              // Removed the top right edit and delete icons
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                _buildDetailRow('Title', session['title']),
                _buildDetailRow('Venue', session['venue']),
                _buildDetailRow('Start Time', session['startTime'] != null
                    ? DateFormat('dd MMM, hh:mm a').format((session['startTime'] as Timestamp).toDate().toLocal())
                    : 'N/A'),
                _buildDetailRow('End Time', session['endTime'] != null
                    ? DateFormat('dd MMM, hh:mm a').format((session['endTime'] as Timestamp).toDate().toLocal())
                    : 'N/A'),
                _buildDetailRow('Course ID', session['courseId']),
                //_buildDetailRow('Section ID', session['sectionId']),
                // Removed attendees from here if they're no longer managed via sessions UI directly
                //_buildDetailRow('Attendees', (session['attendees'] as List?)?.join(', ') ?? 'None'),

                if (_isCustomSection)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info, size: 16, color: Colors.blue[600]),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Custom Session - Can be deleted and manage participants (via section)',
                            style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            if (canEdit) ...[
              TextButton.icon(
                icon: const Icon(Icons.edit, color: Color(0xFFF4A460)), // Changed edit icon color
                label: const Text('Edit', style: TextStyle(color: Color(0xFFF4A460))), // Changed edit text color
                onPressed: () {
                  Navigator.of(context).pop();
                  _showEditSessionDialog(session);
                },
              ),
              // Removed "Add Participants" button from here
              if (canDelete)
                TextButton.icon(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: const Text('Delete', style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showDeleteConfirmation(session);
                  },
                ),
            ],
            TextButton(
              child: const Text('Close', style: TextStyle(color: Colors.deepPurple)), // Changed close text color to original purple
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> session) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Session'),
          content: Text(
            'Are you sure you want to delete the session "${session['title'] ?? 'Untitled'}"?\n\nThis action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.deepPurple)), // Changed cancel text color to original purple
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _deleteSession(session['sessionId']);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSession(String sessionId) async {
    try {
      // Double-check security before deletion
      final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
      if (!sessionDoc.exists) {
        _showErrorSnackBar('Session not found');
        return;
      }
      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      // Check if the current lecturer's UID matches the session's lecturerEmail (which stores UID)
      if (sessionData['lecturerEmail'] != _lecturerUid) {
        _showErrorSnackBar('Unauthorized: You can only delete your own sessions');
        return;
      }
      
      // Implement deletion logic
      await _firestore.collection('sessions').doc(sessionId).delete();
      _showSuccessSnackBar('Session deleted successfully!');
      _loadSessions(); // Reload sessions after deletion
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to delete session: ${e.message}');
      print('Firebase error deleting session: ${e.code} - ${e.message}');
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred: $e');
    }
  }

  // Helper method to build detail rows for session details popup
  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddSessionDialog() async {
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in.');
      return;
    }
    final TextEditingController titleController = TextEditingController();
    final TextEditingController venueController = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? selectedStartTime;
    TimeOfDay? selectedEndTime;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder( // Use StatefulBuilder to update dialog state
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add New Session'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Session Title'),
                    ),
                    TextField(
                      controller: venueController,
                      decoration: const InputDecoration(labelText: 'Venue'),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: Text(selectedDate == null
                          ? 'Select Date'
                          : DateFormat('dd MMM,yyyy').format(selectedDate!)),
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2101),
                        );
                        if (picked != null && picked != selectedDate) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text(selectedStartTime == null
                          ? 'Select Start Time'
                          : selectedStartTime!.format(context)),
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedStartTime ?? TimeOfDay.now(),
                        );
                        if (picked != null && picked != selectedStartTime) {
                          setState(() {
                            selectedStartTime = picked;
                          });
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text(selectedEndTime == null
                          ? 'Select End Time'
                          : selectedEndTime!.format(context)),
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedEndTime ?? TimeOfDay.now(),
                        );
                        if (picked != null && picked != selectedEndTime) {
                          setState(() {
                            selectedEndTime = picked;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.deepPurple)), // Changed cancel text color to original purple
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty ||
                        venueController.text.trim().isEmpty ||
                        selectedDate == null ||
                        selectedStartTime == null ||
                        selectedEndTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please fill all fields.')),
                      );
                      return;
                    }

                    // Combine date and time
                    final DateTime startDateTime = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedStartTime!.hour,
                      selectedStartTime!.minute,
                    );
                    final DateTime endDateTime = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedEndTime!.hour,
                      selectedEndTime!.minute,
                    );

                    if (endDateTime.isBefore(startDateTime)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('End time cannot be before start time.')),
                      );
                      return;
                    }

                    await _createSession(
                      titleController.text.trim(),
                      venueController.text.trim(),
                      startDateTime,
                      endDateTime,
                    );
                    if (mounted) Navigator.pop(context); // Close dialog
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF4A460), // Changed Add Session button color
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Add Session'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createSession(
      String title, String venue, DateTime startTime, DateTime endTime) async {
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in.');
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      await _firestore.collection('sessions').add({
        'title': title,
        'venue': venue,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'courseId': widget.courseId,
        'sectionId': widget.documentId,
        'lecturerEmail': _lecturerUid, // Store UID in 'lecturerEmail' field
        'createdAt': FieldValue.serverTimestamp(),
        'attendees': [], // Initialize with an empty array of attendees
      });
      _showSuccessSnackBar('Session "$title" created successfully!');
      _loadSessions(); // Reload sessions to include the new one
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to add session: ${e.message}');
      print('Firebase error adding session: ${e.code} - ${e.message}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showEditSessionDialog(Map<String, dynamic> session) async {
    final TextEditingController titleController = TextEditingController(text: session['title']);
    final TextEditingController venueController = TextEditingController(text: session['venue']);
    DateTime? selectedDate = (session['startTime'] as Timestamp).toDate();
    TimeOfDay? selectedStartTime = TimeOfDay.fromDateTime(selectedDate!);
    TimeOfDay? selectedEndTime = TimeOfDay.fromDateTime((session['endTime'] as Timestamp).toDate());

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Session'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Session Title'),
                    ),
                    TextField(
                      controller: venueController,
                      decoration: const InputDecoration(labelText: 'Venue'),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.calendar_today),
                      title: Text(selectedDate == null
                          ? 'Select Date'
                          : DateFormat('dd MMM,yyyy').format(selectedDate!)),
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2101),
                        );
                        if (picked != null && picked != selectedDate) {
                          setState(() {
                            selectedDate = picked;
                          });
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text(selectedStartTime == null
                          ? 'Select Start Time'
                          : selectedStartTime!.format(context)),
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedStartTime ?? TimeOfDay.now(),
                        );
                        if (picked != null && picked != selectedStartTime) {
                          setState(() {
                            selectedStartTime = picked;
                          });
                        }
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.access_time),
                      title: Text(selectedEndTime == null
                          ? 'Select End Time'
                          : selectedEndTime!.format(context)),
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: selectedEndTime ?? TimeOfDay.now(),
                        );
                        if (picked != null && picked != selectedEndTime) {
                          setState(() {
                            selectedEndTime = picked;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.deepPurple)), // Changed cancel text color to original purple
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty ||
                        venueController.text.trim().isEmpty ||
                        selectedDate == null ||
                        selectedStartTime == null ||
                        selectedEndTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please fill all fields.')),
                      );
                      return;
                    }

                    final DateTime startDateTime = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedStartTime!.hour,
                      selectedStartTime!.minute,
                    );
                    final DateTime endDateTime = DateTime(
                      selectedDate!.year,
                      selectedDate!.month,
                      selectedDate!.day,
                      selectedEndTime!.hour,
                      selectedEndTime!.minute,
                    );

                    if (endDateTime.isBefore(startDateTime)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('End time cannot be before start time.')),
                      );
                      return;
                    }

                    await _updateSession(
                      session['sessionId'],
                      titleController.text.trim(),
                      venueController.text.trim(),
                      startDateTime,
                      endDateTime,
                    );
                    if (mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF4A460), // Changed update session button color
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Update Session'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _updateSession(
      String sessionId, String title, String venue, DateTime startTime, DateTime endTime) async {
    if (_lecturerUid == null) {
      _showErrorSnackBar('User not logged in.');
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
      if (!sessionDoc.exists) {
        _showErrorSnackBar('Session not found for update.');
        return;
      }
      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      // Check if the current lecturer's UID matches the session's lecturerEmail (which stores UID)
      if (sessionData['lecturerEmail'] != _lecturerUid) {
        _showErrorSnackBar('Unauthorized: You can only edit your own sessions');
        return;
      }

      await _firestore.collection('sessions').doc(sessionId).update({
        'title': title,
        'venue': venue,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        // lecturerEmail, courseId, sectionId, createdAt should not change on update
      });
      _showSuccessSnackBar('Session "$title" updated successfully!');
      _loadSessions();
    } on FirebaseException catch (e) {
      _showErrorSnackBar('Failed to update session: ${e.message}');
      print('Firebase error updating session: ${e.code} - ${e.message}');
    } finally {
      setState(() {
        _isLoading = false;
      });
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
        title: Text(
          _sectionTitle.isEmpty ? 'Manage Sessions' : 'Sessions for $_sectionTitle',
          style: const TextStyle(color: Color(0xFFFFFDD0)), // Changed text color
        ),
        backgroundColor: const Color(0xFF8B0000), // Changed bar color
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage))
                    : _sessions.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text(
                                'No sessions found for this section.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16.0),
                            itemCount: _sessions.length,
                            itemBuilder: (context, index) {
                              final session = _sessions[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12.0),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                child: InkWell(
                                  onTap: () => _showSessionDetailsPopup(session),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          session['title'] ?? 'Unnamed Session',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, fontSize: 18),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.location_on, size: 16),
                                            const SizedBox(width: 4),
                                            Text(session['venue'] ?? 'N/A'),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.schedule, size: 16),
                                            const SizedBox(width: 4),
                                            Text(
                                              session['startTime'] != null && session['endTime'] != null
                                                  ? '${DateFormat('dd MMM, hh:mm a').format((session['startTime'] as Timestamp).toDate().toLocal())} - ${DateFormat('hh:mm a').format((session['endTime'] as Timestamp).toDate().toLocal())}'
                                                  : 'N/A',
                                            ),
                                          ],
                                        ),
                                        // Show deletion icon for custom sections owned by the lecturer
                                        if (_isCustomSection && _lecturerUid == session['lecturerEmail'])
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: IconButton(
                                              onPressed: () => _showDeleteConfirmation(session),
                                              icon: Icon(
                                                Icons.delete,
                                                color: Colors.red[400],
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          // Show "Add Session" button only for custom sections
          if (_isCustomSection)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _showAddSessionDialog,
                  icon: const Icon(Icons.add, color: Color(0xFFFFFDD0)), // Changed icon color
                  label: const Text(
                    'Add Custom Session',
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
        ],
      ),
    );
  }
}
