class UserProfile {
  final String uid;
  final String farmId;
  final String email;
  final String displayName;
  final String role; // ADMIN / FERMIER / VETERINAIRE / DEPOT
  final bool active;

  const UserProfile({
    required this.uid,
    required this.farmId,
    required this.email,
    required this.displayName,
    required this.role,
    required this.active,
  });

  factory UserProfile.fromMap({
    required String uid,
    required String farmId,
    required Map<String, dynamic> map,
  }) {
    String asStr(dynamic v) => (v ?? '').toString().trim();
    bool asBool(dynamic v) => v == true;

    final r = asStr(map['role']);
    return UserProfile(
      uid: uid,
      farmId: farmId,
      email: asStr(map['email']),
      displayName: asStr(map['displayName']),
      role: r.isEmpty ? 'FERMIER' : r,
      active: asBool(map['active']),
    );
  }

  bool get isAdmin => role == 'ADMIN';
  bool get isFarmer => role == 'FERMIER';
  bool get isVet => role == 'VETERINAIRE';
  bool get isDepot => role == 'DEPOT';
}
