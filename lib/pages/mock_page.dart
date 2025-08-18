import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../routes.dart';

class MockPage extends StatefulWidget {
  const MockPage({super.key});

  @override
  MockPageState createState() => MockPageState();
}

class MockPageState extends State<MockPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  int _currentNotificationIndex = 0;
  final List<String> _notifications = [
    "Welcome to Taylor's University!",
    "Check your attendance status",
    "New semester schedules available",
  ];
  String? _studentName;
  bool _isLoadingName = true;

  @override
  void initState() {
    super.initState();
    _fetchStudentName();
  }

  Future<void> _fetchStudentName() async {
    final user = _auth.currentUser;
    if (user?.email == null) {
      setState(() {
        _studentName = null;
        _isLoadingName = false;
      });
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('email', isEqualTo: user!.email)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          // Use the 'name' field from the students document as requested
          _studentName = snapshot.docs.first.data()['name'] as String?;
          _isLoadingName = false;
        });
      } else {
        setState(() {
          _studentName = null;
          _isLoadingName = false;
        });
      }
    } catch (e) {
      setState(() {
        _studentName = null;
        _isLoadingName = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // greeting is sourced from the matching student document's 'email' field

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Top red section with Taylor's logo
            Container(
              width: double.infinity,
              color: const Color(0xFFAA0000),
              padding: const EdgeInsets.only(top: 50, bottom: 20),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "👨‍🎓 TAYLOR'S",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _isLoadingName
                      ? const SizedBox(
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          _studentName != null
                              ? "Hello, $_studentName"
                              : "Error: no matching student record found for this email.",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                ],
              ),
            ),

            // Menu icons row
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 5,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMenuIcon("Attendance", "👋", true),
                  _buildMenuIcon("Timetable", "📅", false),
                  _buildMenuIcon("Virtual ID", "🪪", false),
                  _buildMenuIcon("Profile", "👤", false),
                ],
              ),
            ),

            // Notification bar
            GestureDetector(
              onTap: () {
                setState(() {
                  _currentNotificationIndex = 
                      (_currentNotificationIndex + 1) % _notifications.length;
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      spreadRadius: 2,
                      blurRadius: 5,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Notification Bar",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_left),
                    const SizedBox(width: 5),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),

            // Advertisement section
            Container(
              margin: const EdgeInsets.all(10),
              height: 160,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(
                child: Text(
                  "INSERT ADVERTISEMENT",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Bottom grid of services
            Container(
              padding: const EdgeInsets.all(10),
              child: GridView.count(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                crossAxisCount: 3,
                childAspectRatio: 0.9,
                children: [
                  _buildServiceIcon("Academic\nResult", "📄"),
                  _buildServiceIcon("Exam\nTimetable", "📝"),
                  _buildServiceIcon("Fees", "💰"),
                  _buildServiceIcon("Module\nRegistration", "📚"),
                  _buildServiceIcon("Registered\nModules", "📋"),
                  _buildServiceIcon("Library\nAccount", "📚"),
                  _buildServiceIcon("Chat with\nCampus\nCentral", "💬"),
                  _buildServiceIcon("myTIMeS", "🎓"),
                  _buildServiceIcon("More", "•••"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuIcon(String label, String emoji, bool isActive) {
    return InkWell(
      onTap: () {
        if (label == "Attendance") {
          Navigator.pushReplacementNamed(context, AppRoutes.home);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFAA0000) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? const Color(0xFFAA0000) : Colors.grey[300]!,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                emoji,
                style: TextStyle(
                  fontSize: 28,
                  color: isActive ? Colors.white : Colors.black,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceIcon(String label, String emoji) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
