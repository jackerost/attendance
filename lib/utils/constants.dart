import 'package:flutter/material.dart';

/// This file contains app-wide constants to avoid hardcoded values
/// scattered throughout the code

// Firebase Firestore collection paths
class FirestorePaths {
  //static const String users = 'users';
  //static const String lecturers = 'lecturers';
  static const String students = 'students';
  //static const String courses = 'courses';
  static const String sessions = 'sessions';
  static const String attendanceRecords = 'attendance_records';
  static const String sections = 'sections';
  //static const String courseEnrollments = 'course_enrollments';
}

// Attendance status constants
class AttendanceStatus {
  static const String present = 'present';
  static const String absent = 'absent';
  static const String excused = 'excused';
  static const String late = 'late';
}

// App Colors
class AppColors {
  static const Color primary = Color(0xFF3F51B5);
  static const Color accent = Color(0xFFFF4081);
  static const Color background = Color(0xFFF5F5F5);
  static const Color cardBackground = Colors.white;
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFF44336);
  static const Color warning = Color(0xFFFF9800);
  static const Color info = Color(0xFF2196F3);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color divider = Color(0xFFBDBDBD);
}

// App Text Styles
class AppTextStyles {
  static const TextStyle heading1 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle heading2 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle heading3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle body = TextStyle(
    fontSize: 16,
    color: AppColors.textPrimary,
  );
  
  static const TextStyle caption = TextStyle(
    fontSize: 14,
    color: AppColors.textSecondary,
  );
  
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
}

// App Dimensions
class AppDimensions {
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double borderRadius = 8.0;
  static const double cardElevation = 2.0;
  static const double iconSize = 24.0;
}

// Animation Durations
class AppDurations {
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 500);
  static const Duration long = Duration(milliseconds: 800);
}

// App Keys
class AppKeys {
  static const String sessionIdKey = 'session_id';
  static const String courseIdKey = 'course_id';
  static const String studentIdKey = 'student_id';
  static const String lecturerIdKey = 'lecturer_id';
  static const String authTokenKey = 'auth_token';
  static const String userRoleKey = 'user_role';
}

// User Roles
class UserRoles {
  static const String lecturer = 'lecturer';
  static const String student = 'student';
  static const String admin = 'admin';
}

// NFC Scanner Related Constants
class NfcConstants {
  static const String scannerInstructionText = 'Tap your student ID on the back of the device';
  static const Duration scanTimeout = Duration(seconds: 30);
  static const String scanTimeoutMessage = 'Scan timed out. Please try again.';
  static const String scanSuccessMessage = 'Scan successful! Marking attendance...';
  static const String scanErrorMessage = 'Error scanning. Please try again.';
}

// Attendance Related Constants
class AttendanceConstants {
  static const Duration sessionDefaultDuration = Duration(hours: 1);
  static const int minimumAttendancePercentage = 75;
  static const String attendanceSuccessMessage = 'Attendance marked successfully!';
  static const String attendanceDuplicateMessage = 'You have already been marked present for this session.';
  static const String attendanceErrorMessage = 'Failed to mark attendance. Please try again.';
  static const String attendanceSessionClosedMessage = 'This session is closed.';
}

// Error Messages
class ErrorMessages {
  static const String generalError = 'Something went wrong. Please try again.';
  static const String networkError = 'Network error. Please check your connection.';
  static const String authError = 'Authentication error. Please login again.';
  static const String sessionError = 'Session error. Please try again.';
  static const String databaseError = 'Database error. Please try again later.';
  static const String nfcError = 'NFC error. Please try again.';
  static const String nfcNotSupported = 'NFC is not supported on this device.';
  static const String nfcDisabled = 'NFC is disabled. Please enable it in your device settings.';
}

// Assets Paths
class AssetPaths {
  static const String logo = 'assets/images/logo.png';
  static const String placeholder = 'assets/images/placeholder.png';
  static const String successAnimation = 'assets/animations/success.json';
  static const String errorAnimation = 'assets/animations/error.json';
  static const String loadingAnimation = 'assets/animations/loading.json';
}

// API Endpoints (if used)
class ApiEndpoints {
  static const String baseUrl = 'https://api.example.com';
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String courses = '/courses';
  static const String sessions = '/sessions';
  static const String attendance = '/attendance';
}

// Shared Preferences Keys
class SharedPrefKeys {
  static const String authToken = 'auth_token';
  static const String userId = 'user_id';
  static const String userRole = 'user_role';
  static const String rememberMe = 'remember_me';
  static const String darkMode = 'dark_mode';
  static const String lastSyncTime = 'last_sync_time';
}

// App Settings
class AppSettings {
  static const String appName = 'Attendance Tracker';
  static const String appVersion = '1.0.0';
  static const bool enableOfflineMode = true;
  static const bool enablePushNotifications = true;
  static const bool enableBiometricLogin = true;
  static const int sessionTimeoutMinutes = 30;
}

// Validation Rules
class ValidationRules {
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 20;
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 20;
  static const String emailRegex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
  static const String passwordRegex = r'^(?=.*[A-Za-z])(?=.*\d)[A-Za-z\d]{8,}$';
}