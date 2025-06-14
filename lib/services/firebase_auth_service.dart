import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FirebaseAuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Expose the authentication state changes as a stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  // Get the current user
  User? get currentUser => _auth.currentUser;
  
  // Check if a user is signed in
  bool get isUserSignedIn => currentUser != null;

  // Sign in with email and password
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      notifyListeners();
      return userCredential;
    } on FirebaseAuthException {
      // Pass the exception up to be handled by the UI
      rethrow;
    }
  }
  
  // Create a new user with email and password
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      notifyListeners();
      return userCredential;
    } on FirebaseAuthException {
      // Pass the exception up to be handled by the UI
      rethrow;
    }
  }
  
  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }
  
  // Get user display name
  String? get userDisplayName => currentUser?.displayName;
  
  // Get user email
  String? get userEmail => currentUser?.email;
  
  // Get user ID
  String? get userId => currentUser?.uid;
  
  // Update user profile
  Future<void> updateUserProfile({String? displayName, String? photoURL}) async {
    try {
      await currentUser?.updateDisplayName(displayName);
      await currentUser?.updatePhotoURL(photoURL);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }
  
  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }
  
  // Check if email is verified
  bool get isEmailVerified => currentUser?.emailVerified ?? false;
  
  // Send email verification
  Future<void> sendEmailVerification() async {
    await currentUser?.sendEmailVerification();
  }
}