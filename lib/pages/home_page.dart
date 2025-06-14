import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../services/attendance_service.dart';
import '../utils/constants.dart';
import 'package:logger/logger.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final AttendanceService _attendanceService = AttendanceService();
  final Logger logger = Logger();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  String? _activeCourseId;
  String? _activeSectionId;
  String? _activeSessionId;
  bool _isLoading = true;
  bool _hasActiveSession = false;

  @override
  void initState() {
    super.initState();
    // Listen to authentication state changes to handle unexpected sign-outs
    _auth.authStateChanges().listen((User? user) {
      if (user == null && mounted) {
        logger.w('User signed out unexpectedly, redirecting to login');
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
    });
    _checkForActiveSession();
  }

  // Check if there's an active session for this lecturer based on time
  Future<void> _checkForActiveSession() async {
    setState(() => _isLoading = true);
    
    try {
      final currentTime = Timestamp.now();
      final sessions = await _attendanceService.getLecturerSessions();
      
      // Check for sessions within the current timeframe
      final activeSession = sessions.firstWhere(
        (session) {
          final sessionData = session.data() as Map<String, dynamic>?;
          final startTime = sessionData?['startTime'] as Timestamp?;
          final endTime = sessionData?['endTime'] as Timestamp?;
          return startTime != null && endTime != null &&
                 startTime.toDate().isBefore(currentTime.toDate()) &&
                 endTime.toDate().isAfter(currentTime.toDate());
        },
        orElse: () => throw Exception('No active session'),
      );
      
      if (activeSession.exists) {
        final sessionData = activeSession.data() as Map<String, dynamic>;
        setState(() {
          _activeSessionId = activeSession.id;
          _activeCourseId = sessionData['courseId'];
          _activeSectionId = sessionData['sectionId'];
          _hasActiveSession = true;
        });
      } else {
        setState(() {
          _hasActiveSession = false;
          _activeSessionId = null;
        });
      }
    } catch (e) {
      // No active session found
      setState(() {
        _hasActiveSession = false;
        _activeSessionId = null;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startAttendanceSession() async {
    // Log the current user state to debug navigation issue
    logger.i('Starting attendance session, user: ${_auth.currentUser?.email}');
    
    // If user is not signed in, redirect to login
    if (_auth.currentUser == null) {
      logger.w('No user signed in, redirecting to login');
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.login);
      }
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final currentTime = Timestamp.now();
      if (_hasActiveSession && _activeSessionId != null) {
        // Verify the session is still within its timeframe
        final sessionDoc = await FirebaseFirestore.instance
            .collection(FirestorePaths.sessions)
            .doc(_activeSessionId)
            .get();
        if (sessionDoc.exists) {
          final sessionData = sessionDoc.data() as Map<String, dynamic>;
          final startTime = sessionData['startTime'] as Timestamp?;
          final endTime = sessionData['endTime'] as Timestamp?;
          if (startTime != null && endTime != null &&
              startTime.toDate().isBefore(currentTime.toDate()) &&
              endTime.toDate().isAfter(currentTime.toDate())) {
            if (mounted) {
              logger.i('Navigating to NFC scanner with session ID: $_activeSessionId');
              try {
                await Navigator.pushNamed(
                  context,
                  AppRoutes.nfcScanner, // Now resolves to /nfc-scanner from main.dart
                  arguments: _activeSessionId,
                ).then((_) => _handleScannerReturn());
              } catch (e) {
                logger.e('Navigation to NFC scanner failed: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to navigate to scanner: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
            return;
          } else {
            // Session is outside timeframe, reset state
            setState(() {
              _hasActiveSession = false;
              _activeSessionId = null;
            });
          }
        }
      }

      // Look for a session within the current timeframe
      final QuerySnapshot sessionSnapshot = await FirebaseFirestore.instance
          .collection(FirestorePaths.sessions)
          .where('startTime', isLessThanOrEqualTo: currentTime)
          .where('endTime', isGreaterThanOrEqualTo: currentTime)
          .where('lecturerEmail', isEqualTo: _auth.currentUser!.email)
          .limit(1)
          .get();

      if (sessionSnapshot.docs.isNotEmpty) {
        final sessionDoc = sessionSnapshot.docs.first;
        final sessionData = sessionDoc.data() as Map<String, dynamic>;
        
        setState(() {
          _activeSessionId = sessionDoc.id;
          _activeCourseId = sessionData['courseId'];
          _activeSectionId = sessionData['sectionId'];
          _hasActiveSession = true;
        });

        if (mounted) {
          logger.i('Navigating to NFC scanner with session ID: $_activeSessionId');
          try {
            await Navigator.pushNamed(
              context,
              AppRoutes.nfcScanner, // Now resolves to /nfc-scanner from main.dart
              arguments: _activeSessionId,
            ).then((_) => _handleScannerReturn());
          } catch (e) {
            logger.e('Navigation to NFC scanner failed: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to navigate to scanner: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No session available at this time.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() {
          _hasActiveSession = false;
          _activeSessionId = null;
        });
      }
    } catch (e, stack) {
      logger.e('Error finding session: $e', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error finding session: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  // Handle when returning from NFC scanner
  void _handleScannerReturn() {
    // Refresh session status based on current time
    _checkForActiveSession();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lecturer Dashboard'),
        backgroundColor: Colors.blueGrey[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, AppRoutes.login);
              }
            },
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User info card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.person, size: 40),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Logged in as:', style: TextStyle(fontSize: 14)),
                              Text(
                                FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  const Text('Session Status', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  
                  // Session status card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _hasActiveSession ? Icons.check_circle : Icons.info,
                                color: _hasActiveSession ? Colors.green : Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Status:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _hasActiveSession ? 'Session in progress...' : 'No active session',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.login),
                              label: Text(_hasActiveSession 
                                ? 'Continue Attendance Session' 
                                : 'Find Active Session'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: _startAttendanceSession,
                            ),
                          ),
                          if (_hasActiveSession) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'A session is currently active. You can continue scanning.',
                              style: TextStyle(color: Colors.red),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  // Rest of your dashboard content...
                ],
              ),
            ),
          ),
    );
  }
}