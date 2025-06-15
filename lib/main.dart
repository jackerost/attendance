import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:provider/provider.dart';

// Import pages
import 'pages/login_page.dart';
import 'pages/home_page.dart';
import 'pages/nfc_scanner_page.dart';
import 'pages/selection_page.dart';

// Import services
import 'services/firebase_auth_service.dart';

// Import utils
import 'utils/constants.dart';

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
        initialRoute: AppRoutes.login,
        routes: {
          // Define routes for navigation
          AppRoutes.login: (context) => const LoginPage(),
          AppRoutes.home: (context) => const HomePage(),
          AppRoutes.nfcScanner: (context) => const NFCScannerPage(),
          AppRoutes.selector: (context) {
            final sessionId = ModalRoute.of(context)!.settings.arguments as String;
            return SelectionPage(sessionId: sessionId);
            }
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
          return user != null ? const HomePage() : const LoginPage();
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
  
  // Prevent instantiation
  AppRoutes._();
}