import 'package:flutter/material.dart';
import '../main.dart';

class SelectionPage extends StatelessWidget {
  final String sessionId;
  const SelectionPage({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Selection',
          style: TextStyle(color: Color(0xFFFFFDD0)), // Changed text color
        ),
        backgroundColor: const Color(0xFF8B0000), // Changed bar color
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose Your Mode',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            
            // STRICT Button
            _buildSelectionButton(
              context: context,
              title: 'STRICT',
              description: 'Card Scanning + Facial Recognition',
              color: const Color(0xFF5F4B8B), // Changed STRICT button bar color
              onPressed: () {
                // Navigator.push(context, MaterialPageRoute(builder: (context) => StrictModePage()));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Navigating to Strict mode...')),
                );
              },
            ),
            
            const SizedBox(height: 24),
            
            // LENIENT Button
            _buildSelectionButton(
              context: context,
              title: 'LENIENT',
              description: 'Card Scanning Only',
              color: const Color(0xFFE2725B), // Changed LENIENT button bar color
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.nfcScanner,
                  arguments: sessionId, //use sessionId from constructor
                );
              },
            ),
            
            const SizedBox(height: 24),
            
            // BULK Button for Self Check-In/Out
            _buildSelectionButton(
              context: context,
              title: 'BULK',
              description: 'Student Self Check-In & Out',
              color: const Color(0xFF1E8449), // Green color for BULK button
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.bulkSelfScan,
                  arguments: sessionId,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionButton({
    required BuildContext context,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
