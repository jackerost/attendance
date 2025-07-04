class AppRoutes {
  // Private constructor to prevent instantiation
  AppRoutes._();
  
  // Define route constants
  static const String login = '/login';
  static const String home = '/home';
  static const String nfcScanner = '/nfc_scanner';
  static const String selector = '/select-page';
  static const String courseList = '/course-page';
  
  // Optional: Define route names for more context (useful for logging)
  static const Map<String, String> routeNames = {
    login: 'Login Page',
    home: 'Home Page',
    nfcScanner: 'NFC Scanner Page',
    selector: 'Selection Page',
    courseList: 'Course Listing Page'
  };
}