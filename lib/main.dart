import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';

// Import pages
import 'pages/login_page.dart';
import 'pages/mock_page.dart';
import 'pages/home_page.dart';
import 'pages/nfc_scanner_page.dart';
import 'pages/selection_page.dart';
import 'pages/course_list_page.dart';
import 'pages/session_manager_page.dart';
import 'pages/bulk_self_scan_page.dart';
import 'pages/student_self_scan_page.dart';

// Import services
import 'services/firebase_auth_service.dart';

// Import utils
import 'utils/constants.dart';
import 'routes.dart' as routes;

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Provide Firebase Authentication service
        ChangeNotifierProvider<FirebaseAuthService>(
          create: (_) => FirebaseAuthService(),
        ),
        // Add other providers as needed
      ],
      child: MaterialApp(
        title: 'NFC Attendance App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
          useMaterial3: true,
          // Add more theme customization as needed
        ),
        // Initial route when app starts
        initialRoute: routes.AppRoutes.login,
        routes: {
          // Define routes for navigation
          routes.AppRoutes.login: (context) => const LoginPage(),
          routes.AppRoutes.dashboard: (context) => const MockPage(),
          routes.AppRoutes.home: (context) => const HomePage(),
          routes.AppRoutes.nfcScanner: (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          if (args is String) {
            return NFCScannerPage(sessionId: args);
          }
          // Handle the case where no sessionId is passed or it's not a String
          // You might want to navigate back or show an error
          return const Scaffold(
            body: Center(
              child: Text('Error: Session ID not provided for NFC Scanner.'),
            ),
          );
        },
          routes.AppRoutes.selector: (context) {
            final sessionId = ModalRoute.of(context)!.settings.arguments as String;
            return SelectionPage(sessionId: sessionId);
            },
          routes.AppRoutes.courseList: (context) => const CourseListPage(),
          routes.AppRoutes.sessionPage: (context) {
            final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
            final courseId = args['courseId'] as String;
            final documentId = args['documentId'] as String;

            return SessionManagerPage(
              courseId: courseId,
              documentId: documentId,
            );
          },
          // Self-scan routes
          routes.AppRoutes.bulkSelfScan: (context) {
            final sessionId = ModalRoute.of(context)!.settings.arguments as String;
            return BulkSelfScanPage(sessionId: sessionId);
          },
          routes.AppRoutes.studentSelfScan: (context) => const StudentSelfScanPage(),
        },
        // If route isn't found, redirect to login
        onUnknownRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => const LoginPage(),
          );
        },
      ),
    );
  }
}

// AuthGate widget to handle authentication state changes
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Get the auth service
    final authService = Provider.of<FirebaseAuthService>(context);
    
    // Listen to authentication state changes
    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // If connection is active and user is logged in
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          return user != null ? const MockPage() : const LoginPage();
        }
        
        // Show loading spinner while connecting
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}

// Adding a class to hold route constants for easy reference
class AppRoutes {
  static const String login = '/login';
  static const String home = '/home';
  static const String nfcScanner = '/nfc-scanner';
  static const String selector = '/select-page';
  static const String courseList = '/course-page';
  static const String sessionPage = '/session-page';
  static const String bulkSelfScan = '/bulk-self-scan';
  static const String studentSelfScan = '/student-self-scan';
  
  // Prevent instantiation
  AppRoutes._();
}