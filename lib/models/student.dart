import 'package:cloud_firestore/cloud_firestore.dart';

/// Student model class representing a student in the attendance tracking system.
///
/// This class provides methods to convert between Firestore data and typed
/// Dart objects, as well as utility methods for student-related functionality.
class Student {
  /// Unique identifier from Firestore
  final String id; //tagId?
  
  /// Full name of the student
  final String name;
  
  /// Email address of the student (usually institutional email)
  final String email;
  
  /// University/College ID number (student ID card number)
  final String studentId;
  
  /// URL to student's profile photo (optional)
  final String? photoUrl;
  
  /// NFC card tag ID (for attendance verification)
  final String? tagId;
  
  /// IDs of courses the student is enrolled in
  final List<String> enrolledSections;
  
  /// Student's department or faculty
  //final String department;
  
  /// Student's year of study or semester
  //final int yearOfStudy;
  
  /// Student's academic program (e.g., "Computer Science", "Electrical Engineering")
  //final String program;
  
  /// Flag indicating if the student account is active
  //final bool isActive;
  
  /// Contact phone number (optional)
  //final String? phoneNumber;
  
  /// Date when the student was registered in the system
  //final DateTime intake;
  
  /// Additional metadata or properties for the student
  //final Map<String, dynamic>? metadata;

  /// Creates a new Student instance
  Student({
    required this.id,
    required this.name,
    required this.email,
    required this.studentId,
    this.photoUrl,
    this.tagId,
    required this.enrolledSections,
    //required this.department,
    //required this.yearOfStudy,
    //required this.program,
    //required this.isActive,
    //this.phoneNumber,
    //required this.intake,
    //this.metadata,
  });

  /// Creates a Student object from a Firestore document
  ///
  /// This factory constructor converts the raw document data into a
  /// structured Student object with proper typing.
  factory Student.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    // Extract timestamp and convert to DateTime, defaulting to current time if null
    // Note: intake timestamp not currently used
    
    return Student(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      studentId: data['studentId'] ?? '',
      photoUrl: data['photoUrl'],
      enrolledSections: List<String>.from(data['enrolledSections'] ?? []),
      //department: data['department'] ?? '',
      //yearOfStudy: data['yearOfStudy'] ?? 1,
      //program: data['program'] ?? '',
      //isActive: data['isActive'] ?? true,
      //phoneNumber: data['phoneNumber'],
      //intake: timestamp.toDate(),
      //metadata: data['metadata'],
    );
  }

  /// Creates a Student object from a map of data (useful for API responses)
  factory Student.fromMap(Map<String, dynamic> data, String id) {
    // Note: intake timestamp not currently used
    
    return Student(
      id: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      studentId: data['studentId'] ?? '',
      photoUrl: data['photoUrl'],
      enrolledSections: List<String>.from(data['enrolledSections'] ?? []),
      //department: data['department'] ?? '',
      //yearOfStudy: data['yearOfStudy'] ?? 1,
      //program: data['program'] ?? '',
      //isActive: data['isActive'] ?? true,
      //phoneNumber: data['phoneNumber'],
      //intake: timestamp.toDate(),
      //metadata: data['metadata'],
    );
  }

  /// Converts Student object to a map for Firestore storage
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'studentId': studentId,
      'photoUrl': photoUrl,
      'enrolledSections': enrolledSections,
      //'department': department,
      //'yearOfStudy': yearOfStudy,
      //'program': program,
      //'isActive': isActive,
      //'phoneNumber': phoneNumber,
      //'intake': Timestamp.fromDate(intake),
      //'metadata': metadata,
    };
  }

  /// Creates a copy of this Student with the given fields replaced with new values
  Student copyWith({
    String? name,
    String? email,
    String? studentId,
    String? photoUrl,
    List<String>? enrolledSections,
    String? department,
    //int? yearOfStudy,
    //String? program,
    //bool? isActive,
    //String? phoneNumber,
    //DateTime? intake,
    //Map<String, dynamic>? metadata,
  }) {
    return Student(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      studentId: studentId ?? this.studentId,
      photoUrl: photoUrl ?? this.photoUrl,
      enrolledSections: enrolledSections ?? this.enrolledSections,
      //department: department ?? this.department,
      //yearOfStudy: yearOfStudy ?? this.yearOfStudy,
      //program: program ?? this.program,
      //isActive: isActive ?? this.isActive,
      //phoneNumber: phoneNumber ?? this.phoneNumber,
      //intake: intake ?? this.intake,
      //metadata: metadata ?? this.metadata,
    );
  }

  /// Calculates the attendance rate for a specific course
  ///
  /// Takes total number of attended sessions and total sessions in the course
  double calculateAttendanceRate(int attendedSessions, int totalSessions) {
    if (totalSessions == 0) return 0.0;
    return attendedSessions / totalSessions;
  }

  /// Determines if the student's attendance meets the minimum requirement
  ///
  /// [attendanceRate]: The student's current attendance rate as a decimal (0.0 to 1.0)
  /// [minimumRequired]: The minimum attendance rate required (default is 0.75 or 75%)
  bool meetsAttendanceRequirement(double attendanceRate, {double minimumRequired = 0.75}) {
    return attendanceRate >= minimumRequired;
  }

  /// Returns a formatted display name for the student (first name + last initial)
  String get displayName {
    final nameParts = name.split(' ');
    if (nameParts.length > 1) {
      // First name + last initial (e.g., "John D.")
      return '${nameParts.first} ${nameParts.last[0]}.';
    }
    return name;
  }

  /// Get the initials of the student (e.g., "JD" for "John Doe")
  String get initials {
    final nameParts = name.split(' ');
    if (nameParts.isEmpty) return '';
    
    if (nameParts.length == 1) {
      return nameParts[0].isNotEmpty ? nameParts[0][0].toUpperCase() : '';
    }
    
    return (nameParts.first.isNotEmpty ? nameParts.first[0] : '') + 
           (nameParts.last.isNotEmpty ? nameParts.last[0] : '');
  }

  /// Checks if a student is enrolled in a specific course
  bool isEnrolledInSection(String sectionId) {
    return enrolledSections.contains(sectionId);
  }

  /// Returns the student's year of study as a string (e.g., "1st Year")
  //String get yearOfStudyText {
    //switch (yearOfStudy) {
      //case 1: return '1st Year';
      //case 2: return '2nd Year';
      //case 3: return '3rd Year';
      //default: return '${yearOfStudy}th Year';
    //}
  //}

  @override
  String toString() {
    return 'Student(id: $id, name: $name, studentId: $studentId)';
  }
}