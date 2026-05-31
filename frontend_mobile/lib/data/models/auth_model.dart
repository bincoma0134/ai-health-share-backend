/// Model phục vụ gửi request đăng nhập (Khớp với UserLogin trong schemas.py)
class UserLoginRequest {
  final String email;
  final String password;

  UserLoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
  };
}

/// Model nhận Token và Role từ Backend (Khớp với @app.post("/auth/login"))
class AuthResponse {
  final String accessToken;
  final String tokenType;
  final String role;

  AuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.role,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['access_token'] ?? '',
      tokenType: json['token_type'] ?? 'bearer',
      role: json['role'] ?? 'USER',
    );
  }
}