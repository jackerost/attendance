import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class SessionManagerPage extends StatefulWidget {
  final String courseId;
  final String documentId;

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

  String? _lecturerUid;
  String _errorMessage = '';
  bool _isLoading = true;
  List<Map<String, dynamic>> _sessions = [];
  bool _isCustomSection = false;
  String _sectionTitle = '';

  @override
  void initState() {
    super.initState();
    _lecturerUid = _auth.currentUser?.uid;
    if (_lecturerUid == null) {
      _errorMessage = 'User not logged in.';
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
        _sectionTitle = sectionData['sectionTitle'] ?? 'Unknown Section';
      }
    } catch (e) {
      print('Error checking section type: $e');
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
          .where('lecturerEmail', isEqualTo: _lecturerUid)
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
              if (canEdit)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Color.fromARGB(255, 25, 154, 163)),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showEditSessionDialog(session);
                      },
                    ),
                    if (canDelete)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showDeleteConfirmation(session);
                        },
                      ),
                  ],
                ),
            ],
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                _buildDetailRow('Title', session['title']),
                _buildDetailRow('Venue', session['venue']),
                _buildDetailRow('Start Time', session['startTime'] != null 
                    ? DateFormat('dd MMM yyyy, hh:mm a').format((session['startTime'] as Timestamp).toDate().toLocal()) 
                    : 'N/A'),
                _buildDetailRow('End Time', session['endTime'] != null 
                    ? DateFormat('dd MMM yyyy, hh:mm a').format((session['endTime'] as Timestamp).toDate().toLocal()) 
                    : 'N/A'),
                _buildDetailRow('Course ID', session['courseId']),
                _buildDetailRow('Section ID', session['sectionId']),
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
                            'Custom Session - Can be deleted',
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
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _showEditSessionDialog(session);
                },
              ),
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
              child: const Text('Close'),
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
              child: const Text('Cancel'),
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
      if (sessionData['lecturerEmail'] != _lecturerUid) {
        _showErrorSnackBar('Unauthorized: You can only delete your own sessions');
        return;
      }

      if (!_isCustomSection) {
        _showErrorSnackBar('Cannot delete sessions from non-custom sections');
        return;
      }

      await _firestore.collection('sessions').doc(sessionId).delete();
      _showSuccessSnackBar('Session deleted successfully');
      _loadSessions(); // Refresh the list
    } catch (e) {
      print('Error deleting session: $e');
      _showErrorSnackBar('Failed to delete session: ${e.toString()}');
    }
  }

  void _showAddSessionDialog() {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController venueController = TextEditingController();
    
    DateTime? startTime;
    DateTime? endTime;
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add New Session'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Session Title *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: venueController,
                      decoration: const InputDecoration(
                        labelText: 'Venue *',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDateTimePicker(
                      'Start Time',
                      startTime,
                      (newDateTime) {
                        setDialogState(() {
                          startTime = newDateTime;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildDateTimePicker(
                      'End Time',
                      endTime,
                      (newDateTime) {
                        setDialogState(() {
                          endTime = newDateTime;
                        });
                      },
                    ),
                    if (isCreating) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isCreating ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isCreating ? null : () async {
                    if (_validateInputs(titleController.text, venueController.text, startTime, endTime)) {
                      setDialogState(() {
                        isCreating = true;
                      });
                      
                      await _createSession(
                        titleController.text.trim(),
                        venueController.text.trim(),
                        startTime!,
                        endTime!,
                      );
                      
                      if (mounted) {
                        Navigator.of(context).pop();
                        _loadSessions(); // Refresh the list
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 25, 154, 163),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Create Session'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createSession(String title, String venue, DateTime startTime, DateTime endTime) async {
    try {
      final newStartTime = Timestamp.fromDate(startTime);
      final newEndTime = Timestamp.fromDate(endTime);
      final sessionSnapshot = await _firestore
      .collection('sessions')
      .where('lecturerEmail', isEqualTo: _lecturerUid)
      .where('sectionId', isEqualTo: widget.documentId)
      .get();

      for (var doc in sessionSnapshot.docs) {
      final data = doc.data();
      final existingStartTime = data['startTime'] as Timestamp?;
      final existingEndTime = data['endTime'] as Timestamp?;
      if (existingStartTime != null && existingEndTime != null) {
        if (!(newEndTime.toDate().isBefore(existingStartTime.toDate()) ||
              newStartTime.toDate().isAfter(existingEndTime.toDate()))) {
          _showErrorSnackBar('Session time overlaps with an existing session');
          return;
          }
        }
      }
      // Create the session if no overlaps
      await _firestore.collection('sessions').add({
        'title': title,
        'venue': venue,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'courseId': widget.courseId,
        'sectionId': widget.documentId,
        'lecturerEmail': _lecturerUid
      });

      _showSuccessSnackBar('Session created successfully');
    } catch (e) {
      print('Error creating session: $e');
      _showErrorSnackBar('Failed to create session: ${e.toString()}');
    }
  }

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
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(value ?? 'N/A'),
          ),
        ],
      ),
    );
  }

  void _showEditSessionDialog(Map<String, dynamic> session) {
    final TextEditingController titleController = TextEditingController(text: session['title'] ?? '');
    final TextEditingController venueController = TextEditingController(text: session['venue'] ?? '');
    
    DateTime? startTime = session['startTime'] != null 
        ? (session['startTime'] as Timestamp).toDate().toLocal() 
        : null;
    DateTime? endTime = session['endTime'] != null 
        ? (session['endTime'] as Timestamp).toDate().toLocal() 
        : null;
    
    bool isUpdating = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_isCustomSection ? 'Edit Custom Session' : 'Edit Session'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Session Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: venueController,
                      decoration: const InputDecoration(
                        labelText: 'Venue',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDateTimePicker(
                      'Start Time',
                      startTime,
                      (newDateTime) {
                        setDialogState(() {
                          startTime = newDateTime;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildDateTimePicker(
                      'End Time',
                      endTime,
                      (newDateTime) {
                        setDialogState(() {
                          endTime = newDateTime;
                        });
                      },
                    ),
                    if (!_isCustomSection)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.orange[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info, size: 16, color: Colors.orange[600]),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Regular session - Only basic details can be edited',
                                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (isUpdating) ...[
                      const SizedBox(height: 16),
                      const CircularProgressIndicator(),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUpdating ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isUpdating ? null : () async {
                    if (_validateInputs(titleController.text, venueController.text, startTime, endTime)) {
                      setDialogState(() {
                        isUpdating = true;
                      });
                      
                      await _updateSession(
                        session['sessionId'],
                        titleController.text.trim(),
                        venueController.text.trim(),
                        startTime!,
                        endTime!,
                      );
                      
                      if (mounted) {
                        Navigator.of(context).pop();
                        _loadSessions(); // Refresh the list
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 25, 154, 163),
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

  Widget _buildDateTimePicker(String label, DateTime? dateTime, Function(DateTime) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _selectDateTime(dateTime, onChanged),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateTime != null 
                      ? DateFormat('dd MMM yyyy, hh:mm a').format(dateTime)
                      : 'Select $label',
                  style: TextStyle(
                    color: dateTime != null ? Colors.black : Colors.grey[600],
                  ),
                ),
                const Icon(Icons.calendar_today, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _selectDateTime(DateTime? currentDateTime, Function(DateTime) onChanged) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: currentDateTime ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: currentDateTime != null 
            ? TimeOfDay.fromDateTime(currentDateTime) 
            : TimeOfDay.now(),
      );
      
      if (pickedTime != null) {
        final DateTime newDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        onChanged(newDateTime);
      }
    }
  }

  bool _validateInputs(String title, String venue, DateTime? startTime, DateTime? endTime) {
    if (title.isEmpty) {
      _showErrorSnackBar('Please enter a session title');
      return false;
    }
    if (venue.isEmpty) {
      _showErrorSnackBar('Please enter a venue');
      return false;
    }
    if (startTime == null || endTime == null) {
      _showErrorSnackBar('Please select both start and end times');
      return false;
    }
    if (endTime.isBefore(startTime)) {
      _showErrorSnackBar('End time must be after start time');
      return false;
    }
    return true;
  }

  Future<void> _updateSession(String sessionId, String title, String venue, DateTime startTime, DateTime endTime) async {
    try {
      // Double-check security: ensure the session belongs to the current user
      final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
      
      if (!sessionDoc.exists) {
        _showErrorSnackBar('Session not found');
        return;
      }
      
      final sessionData = sessionDoc.data() as Map<String, dynamic>;
      if (sessionData['lecturerEmail'] != _lecturerUid) {
        _showErrorSnackBar('Unauthorized: You can only edit your own sessions');
        return;
      }

      // Check for overlapping sessions (excluding the current session)
      final newStartTime = Timestamp.fromDate(startTime);
      final newEndTime = Timestamp.fromDate(endTime);
      final sessionSnapshot = await _firestore
      .collection('sessions')
      .where('lecturerEmail', isEqualTo: _lecturerUid)
      .where('sectionId', isEqualTo: sessionData['sectionId'])
      .get();
      
      for (var doc in sessionSnapshot.docs) {
        if (doc.id == sessionId) continue; // Skip the session being updated
        final data = doc.data();
        final existingStartTime = data['startTime'] as Timestamp?;
        final existingEndTime = data['endTime'] as Timestamp?;
        if (existingStartTime != null && existingEndTime != null) {
          if (!(newEndTime.toDate().isBefore(existingStartTime.toDate()) ||
          newStartTime.toDate().isAfter(existingEndTime.toDate()))) {
            _showErrorSnackBar('Session time overlaps with an existing session');
            return;
            }
            }
            }

      // Update only the allowed fields if no overlap
      await _firestore.collection('sessions').doc(sessionId).update({
        'title': title,
        'venue': venue,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime)
      });

      _showSuccessSnackBar('Session updated successfully');
    } catch (e) {
      print('Error updating session: $e');
      _showErrorSnackBar('Failed to update session: ${e.toString()}');
    }
  }

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
        title: Text(_sectionTitle.isNotEmpty ? _sectionTitle : 'Session List'),
        backgroundColor: const Color.fromARGB(255, 25, 154, 163),
        foregroundColor: Colors.white,
        actions: [
          if (_isCustomSection)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: Chip(
                label: const Text('CUSTOM', style: TextStyle(fontSize: 10)),
                backgroundColor: Colors.orange[100],
                labelStyle: TextStyle(color: Colors.orange[800]),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage))
                    : _sessions.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_busy,
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _isCustomSection 
                                      ? 'No custom sessions created yet.\nTap "Add Session" to create your first session!'
                                      : 'No sessions found for this section.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _sessions.length,
                            padding: const EdgeInsets.all(16.0),
                            itemBuilder: (context, index) {
                              final session = _sessions[index];
                              String formattedStartTime = (session['startTime'] as Timestamp?) != null
                                  ? DateFormat('hh:mm a').format((session['startTime'] as Timestamp).toDate().toLocal())
                                  : 'N/A';
                              String formattedEndTime = (session['endTime'] as Timestamp?) != null
                                  ? DateFormat('hh:mm a').format((session['endTime'] as Timestamp).toDate().toLocal())
                                  : 'N/A';

                              bool canEdit = _lecturerUid == session['lecturerEmail'];
                              bool canDelete = _isCustomSection && canEdit;

                              return GestureDetector(
                                onTap: () => _showSessionDetailsPopup(session),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 12.0),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                  elevation: 2,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 4.0,
                                          height: 80.0,
                                          decoration: BoxDecoration(
                                            color: _isCustomSection 
                                                ? Colors.orange[400] 
                                                : const Color.fromARGB(255, 25, 154, 163),
                                            borderRadius: BorderRadius.circular(2.0),
                                          ),
                                          margin: const EdgeInsets.only(right: 12.0),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              formattedStartTime,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            Text(
                                              formattedEndTime,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 16.0),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      session['title'] ?? 'No Title',
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (_isCustomSection)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: Colors.orange[100],
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Text(
                                                        'CUSTOM',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.orange[800],
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              Text(
                                                session['venue'] ?? 'No Venue',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                              Text(
                                                session['startTime'] != null 
                                                    ? DateFormat('dd MMMM').format((session['startTime'] as Timestamp).toDate().toLocal()) 
                                                    : 'N/A',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          children: [
                                            Icon(
                                              canEdit ? Icons.edit : Icons.visibility,
                                              color: canEdit ? const Color.fromARGB(255, 25, 154, 163) : Colors.grey,
                                              size: 20,
                                            ),
                                            if (canDelete)
                                              const SizedBox(height: 4),
                                            if (canDelete)
                                              Icon(
                                                Icons.delete,
                                                color: Colors.red[400],
                                                size: 16,
                                              ),
                                          ],
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
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text(
                    'Add Custom Session',
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
        ],
      ),
    );
  }
}