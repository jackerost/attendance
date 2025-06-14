import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/services.dart';

import 'constants.dart';

/// A centralized error handling utility for the application.
/// 
/// This class provides methods for handling, logging, and reporting errors
/// in a consistent way throughout the application.
class ErrorHandler {
  /// Private constructor to prevent instantiation
  ErrorHandler._();

  /// Flag to determine if detailed error logging is enabled
  static bool _detailedLoggingEnabled = kDebugMode;

  /// Enable or disable detailed error logging
  static void setDetailedLogging(bool enabled) {
    _detailedLoggingEnabled = enabled;
  }

  /// Log an error with optional stack trace and additional information
  static void logError(
    String message,
    dynamic error,
    [StackTrace? stackTrace, Map<String, dynamic>? additionalInfo]
  ) {
    // Print to console in debug mode
    if (_detailedLoggingEnabled) {
      debugPrint('ERROR: $message');
      debugPrint('ERROR DETAILS: $error');
      if (stackTrace != null) {
        debugPrint('STACK TRACE:\n$stackTrace');
      }
      if (additionalInfo != null) {
        debugPrint('ADDITIONAL INFO: $additionalInfo');
      }
    }

    // Report to Firebase Crashlytics in non-debug mode
    if (!kDebugMode) {
      _reportToCrashlytics(message, error, stackTrace, additionalInfo);
    }
  }

  /// Report an error to Firebase Crashlytics
  static void _reportToCrashlytics(
    String message,
    dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic>? additionalInfo
  ) {
    try {
      final crashlytics = FirebaseCrashlytics.instance;
      
      // Set custom keys for additional context
      if (additionalInfo != null) {
        additionalInfo.forEach((key, value) {
          crashlytics.setCustomKey(key, value.toString());
        });
      }
      
      // Log the error message
      crashlytics.log(message);
      
      // Record the error with Crashlytics
      crashlytics.recordError(
        error,
        stackTrace,
        reason: message,
        printDetails: true,
      );
    } catch (e) {
      // Fallback if Crashlytics reporting fails
      debugPrint('Failed to report to Crashlytics: $e');
    }
  }

  /// Handle an error with a user-friendly message and optional callback
  static void handleError(
    BuildContext context,
    String message,
    dynamic error,
    [StackTrace? stackTrace, VoidCallback? onRetry]
  ) {
    // Log the error
    logError(message, error, stackTrace);
    
    // Show a user-friendly error message
    _showErrorDialog(context, _getUserFriendlyMessage(error), onRetry);
  }

  /// Convert technical errors to user-friendly messages
  static String _getUserFriendlyMessage(dynamic error) {
    if (error is SocketException || error is TimeoutException) {
      return ErrorMessages.networkError;
    } else if (error is PlatformException) {
      if (error.code == 'sign_in_failed') {
        return ErrorMessages.authError;
      } else if (error.code.contains('nfc')) {
        return ErrorMessages.nfcError;
      }
    } else if (error is FirebaseException) {
      if (error.code.startsWith('auth/')) {
        return ErrorMessages.authError;
      } else if (error.code.startsWith('firestore/')) {
        return ErrorMessages.databaseError;
      }
    }
    
    // Default error message
    return ErrorMessages.generalError;
  }

  /// Show an error dialog to the user
  static void _showErrorDialog(
    BuildContext context,
    String message,
    VoidCallback? onRetry
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onRetry();
              },
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  /// Show a snackbar with an error message
  static void showErrorSnackbar(
    BuildContext context,
    String message,
    [SnackBarAction? action]
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        action: action,
      ),
    );
  }

  /// Wrap a future with error handling
  static Future<T?> wrapFuture<T>(
    BuildContext context,
    Future<T> future,
    String errorMessage, {
    bool showDialog = true,
    VoidCallback? onRetry,
  }) async {
    try {
      return await future;
    } catch (e, stackTrace) {
      logError(errorMessage, e, stackTrace);
      
      if (showDialog) {
        handleError(context, errorMessage, e, stackTrace, onRetry);
      } else {
        showErrorSnackbar(context, _getUserFriendlyMessage(e));
      }
      
      return null;
    }
  }

  /// Get a user-friendly error message from an exception
  static String getErrorMessage(dynamic error) {
    return _getUserFriendlyMessage(error);
  }
  
  /// Global error handler for uncaught exceptions
  static void setupErrorHandling() {
    // Handle Flutter framework errors
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      logError(
        'Flutter framework error',
        details.exception,
        details.stack,
        {'context': details.context?.toString() ?? 'unknown'},
      );
    };
    
    // Handle Dart errors outside Flutter
    PlatformDispatcher.instance.onError = (error, stack) {
      logError('Uncaught platform error', error, stack);
      return true; // Prevents the error from being handled by the platform
    };
    
    // Initialize Crashlytics if not in debug mode
    if (!kDebugMode) {
      FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    }
  }
}

/// Extension for easier error handling in async code
extension FutureExtension<T> on Future<T> {
  /// Handle errors with a default value
  Future<T> withDefault(T defaultValue) async {
    try {
      return await this;
    } catch (e, stackTrace) {
      ErrorHandler.logError('Error in future', e, stackTrace);
      return defaultValue;
    }
  }
  
  /// Handle errors with a callback
  Future<T> withErrorHandler(
    BuildContext context,
    String errorMessage, {
    bool showDialog = true,
    VoidCallback? onRetry,
  }) {
    return ErrorHandler.wrapFuture(
      context,
      this,
      errorMessage,
      showDialog: showDialog,
      onRetry: onRetry,
    ).then((value) => value as T);
  }
}