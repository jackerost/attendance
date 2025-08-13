/// Security check result model
/// 
/// Represents the result of a security verification check
/// Used by SelfScanCheckService for returning verification results
class SecurityCheckResult {
  /// Whether the security check passed
  final bool success;
  
  /// Message explaining the result (error message if failed)
  final String message;
  
  /// Optional data that can be returned with the result
  final dynamic data;
  
  /// Creates a new SecurityCheckResult instance
  SecurityCheckResult({
    required this.success,
    required this.message,
    this.data,
  });
  
  /// Factory method to create a successful result
  factory SecurityCheckResult.success({String message = 'Verification successful', dynamic data}) {
    return SecurityCheckResult(
      success: true,
      message: message,
      data: data,
    );
  }
  
  /// Factory method to create a failed result
  factory SecurityCheckResult.failure({required String message}) {
    return SecurityCheckResult(
      success: false,
      message: message,
    );
  }
}
