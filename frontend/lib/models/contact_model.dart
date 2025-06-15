class ContactInfo {
  final String telephone;
  final String email;
  final String adresse;
  final String? facebook;
  final String? linkedin;

  ContactInfo({
    required this.telephone,
    required this.email,
    required this.adresse,
    this.facebook,
    this.linkedin,
  });

  factory ContactInfo.fromJson(Map<String, dynamic> json) {
    return ContactInfo(
      telephone: json['telephone'] ?? '',
      email: json['email'] ?? '',
      adresse: json['adresse'] ?? '',
      facebook: json['facebook'],
      linkedin: json['linkedin'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'telephone': telephone,
      'email': email,
      'adresse': adresse,
      'facebook': facebook,
      'linkedin': linkedin,
    };
  }

  @override
  String toString() {
    return 'ContactInfo(telephone: $telephone, email: $email, adresse: $adresse, facebook: $facebook, linkedin: $linkedin)';
  }
}