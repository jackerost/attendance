import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Make sure to import main.dart if AppRoutes is defined there
// import '../main.dart'; // Uncomment if AppRoutes is not already globally accessible

class SessionManagerPage extends StatefulWidget {
  final String courseId; // Still useful for display purposes or other logic
  final String documentId; // The section's Firestore document ID

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

      // Query sessions collection
      // Filter by lecturerEmail AND sectionId (using the documentId of the parent section)
      final QuerySnapshot sessionSnapshot = await _firestore
          .collection('sessions')
          .where('lecturerEmail', isEqualTo: _lecturerUid)
          .where('sectionId', isEqualTo: widget.documentId) // <-- IMPORTANT CHANGE HERE
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
                Text('Course ID: ${session['courseId'] ?? 'N/A'}'), // Still show courseId from session document
                Text('Section ID: ${session['sectionId'] ?? 'N/A'}'), // Show sectionId from session document
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
        title: Text('Sessions for ${widget.courseId}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage))
              : _sessions.isEmpty
                  ? const Center(child: Text('No sessions found for this course and lecturer.'))
                  : ListView.builder(
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final session = _sessions[index];
                        String startTime = (session['startTime'] as Timestamp?)?.toDate().toLocal().toString() ?? 'N/A';
                        String endTime = (session['endTime'] as Timestamp?)?.toDate().toLocal().toString() ?? 'N/A';

                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            title: Text(session['title'] ?? 'No Title'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Venue: ${session['venue'] ?? 'N/A'}'),
                                Text('Start: $startTime'),
                                Text('End: $endTime'),
                              ],
                            ),
                            onTap: () => _showSessionDetailsPopup(session),
                          ),
                        );
                      },
                    ),
    );
  }
}