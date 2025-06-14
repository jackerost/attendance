import 'package:flutter/material.dart';
import '../models/student.dart';

class ScannedStudentList extends StatelessWidget {
  final List<Student> students;

  const ScannedStudentList({super.key, required this.students});

  @override
  Widget build(BuildContext context) {
    if (students.isEmpty) {
      return const Center(
        child: Text('No students scanned yet.'),
      );
    }

    return ListView.builder(
      itemCount: students.length,
      itemBuilder: (context, index) {
        final student = students[index];

        return ListTile(
          leading: CircleAvatar(
            backgroundImage: student.photoUrl != null && student.photoUrl!.isNotEmpty
                ? NetworkImage(student.photoUrl!)
                : null,
            child: student.photoUrl == null || student.photoUrl!.isEmpty
                ? Text(student.name[0])
                : null,
          ),
          title: Text(student.name),
          subtitle: Text('ID: ${student.id}'),
        );
      },
    );
  }
}
