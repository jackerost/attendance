import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Import for date/time formatting

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

  @override
  void initState() {
    super.initState();
    _lecturerUid = _auth.currentUser?.uid;
    if (_lecturerUid == null) {
      _errorMessage = 'User not logged in.';
      _isLoading = false;
    } else {
      _loadSessions();
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
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Session Details'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Title: ${session['title'] ?? 'N/A'}'),
                Text('Venue: ${session['venue'] ?? 'N/A'}'),
                Text('Start Time: ${session['startTime'] != null ? (session['startTime'] as Timestamp).toDate().toLocal().toString() : 'N/A'}'),
                Text('End Time: ${session['endTime'] != null ? (session['endTime'] as Timestamp).toDate().toLocal().toString() : 'N/A'}'),
                Text('Course ID: ${session['courseId'] ?? 'N/A'}'),
                Text('Section ID: ${session['sectionId'] ?? 'N/A'}'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session List'), // Changed AppBar title
        backgroundColor: const Color.fromARGB(255, 25, 154, 163), // Added AppBar color
        foregroundColor: Colors.white, // Added AppBar text color
      ),
      body: Column( // Use Column to place list and button
        children: [
          Expanded( // List takes available space
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text(_errorMessage))
                    : _sessions.isEmpty
                        ? const Center(child: Text('No sessions found for this course and lecturer.'))
                        : ListView.builder(
                            itemCount: _sessions.length,
                            padding: const EdgeInsets.all(16.0), // Padding around the list
                            itemBuilder: (context, index) {
                              final session = _sessions[index];
                              // Format Timestamp to a readable string for display on card
                              String formattedStartTime = (session['startTime'] as Timestamp?) != null
                                  ? DateFormat('hh:mm a').format((session['startTime'] as Timestamp).toDate().toLocal())
                                  : 'N/A';
                              String formattedEndTime = (session['endTime'] as Timestamp?) != null
                                  ? DateFormat('hh:mm a').format((session['endTime'] as Timestamp).toDate().toLocal())
                                  : 'N/A';

                              return GestureDetector( // Use GestureDetector for onTap
                                onTap: () => _showSessionDetailsPopup(session),
                                child: Card(
                                  margin: const EdgeInsets.only(bottom: 12.0), // Space between cards
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                                  elevation: 2, // Card shadow
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Row(
                                      children: [
                                        // Vertical blue line
                                        Container(
                                          width: 4.0,
                                          height: 80.0, // Adjust height as needed
                                          decoration: BoxDecoration(
                                            color: const Color.fromARGB(255, 25, 154, 163), // Blue color
                                            borderRadius: BorderRadius.circular(2.0),
                                          ),
                                          margin: const EdgeInsets.only(right: 12.0),
                                        ),
                                        // Time section
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
                                        const SizedBox(width: 16.0), // Space between time and details
                                        // Session Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                session['title'] ?? 'No Title',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                session['venue'] ?? 'No Course ID',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                              Text(
                                                session['startTime'] != null ? DateFormat('dd-MM').format((session['startTime'] as Timestamp).toDate().toLocal()) : 'N/A',
                                                style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
                                                ),
                                                ), 
                                            ],
                                          ),
                                        ),
                                        // Right gear icon
                                        const Icon(
                                          Icons.settings, // Changed to the gear icon
                                          color: Colors.grey,
                                          size: 24, // Matches the previous fontSize for the arrow
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
          // "Add Session" Button at the bottom (edit later only for custom)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              height: 50, // Fixed height for the button
              child: ElevatedButton.icon(
                onPressed: () {
                  // TODO: Navigate to Add Session page
                  print('Add Session button pressed');
                },
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Add Session',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 25, 154, 163), // Blue background
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0), // Rounded corners
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