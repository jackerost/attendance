# Supplemental Copilot Instructions: BLE + NFC Self-Scan


This document extends `.github/copilot-instructions.md` with crucial knowledge for the BLE + NFC self-scan attendance feature.


## Firestore
- Only add/remove `beaconId` (BLE UUID) in session documents to control self-scan state.
- No other schema changes are required.


## Access Control
- **Lecturer:** Can toggle self-scan only if their UID matches `lecturerEmail` and session is active (by time).
- **Student:** Can access self-scan only if their `enrolledSections` contains the section, session is active, and `beaconId` is present.


## BLE + NFC Logic
- BLE beacon is broadcast by lecturer’s device and detected by students.
- Students must detect the beacon for 1.5s, then have 10s to scan their NFC card.
- NFC tagId must match the logged-in student’s Firestore record.
- Entry/exit mode is handled in app state, not Firestore.


## UI/UX
- Use `bulk_self_scan_page.dart` for lecturer BLE controls.
- Use `student_self_scan_page.dart` for student BLE/NFC scan.
- Use `ble_status_widget.dart` for BLE detection feedback.
- Use `self_scan_confirmation_widget.dart` for scan confirmation.


## Security
- All business logic checks (enrollment, session time, UID, beacon, tagId) must be enforced in services, not just UI.
- Firestore security rules should prevent unauthorized toggling or attendance marking.


## File Structure
- See main instructions for canonical file locations. New files: `bulk_self_scan_page.dart`, `student_self_scan_page.dart`, `ble_service.dart`, `ble_status_widget.dart`, `self_scan_confirmation_widget.dart`.

---
