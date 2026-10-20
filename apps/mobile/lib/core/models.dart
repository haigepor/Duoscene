class User {
  const User({
    required this.id,
    required this.username,
    required this.displayName,
  });
  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as String,
    username: json['username'] as String,
    displayName: json['displayName'] as String,
  );
  final String id;
  final String username;
  final String displayName;
}

class Credentials {
  Credentials.fromJson(Map<String, dynamic> json)
    : accessToken = json['accessToken'] as String,
      refreshToken = json['refreshToken'] as String,
      user = User.fromJson(json['user'] as Map<String, dynamic>);
  final String accessToken;
  final String refreshToken;
  final User user;
}

class RoomMember {
  RoomMember.fromJson(Map<String, dynamic> json)
    : userId = json['userId'] as String,
      displayName = json['displayName'] as String,
      seatNo = json['seatNo'] as int;
  final String userId;
  final String displayName;
  final int seatNo;
}

class Room {
  Room.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      name = json['name'] as String,
      ownerUserId = json['ownerUserId'] as String,
      status = json['status'] as String,
      members = (json['members'] as List<dynamic>? ?? [])
          .map((item) => RoomMember.fromJson(item as Map<String, dynamic>))
          .toList();
  final String id;
  final String name;
  final String ownerUserId;
  final String status;
  final List<RoomMember> members;
  bool get isOpen => status == 'OPEN';
}

class RoomPage {
  RoomPage.fromJson(Map<String, dynamic> json)
    : items = (json['items'] as List<dynamic>)
          .map((item) => Room.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor = json['nextCursor'] as String?;
  final List<Room> items;
  final String? nextCursor;
}

class Invite {
  Invite.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      token = json['token'] as String,
      expiresAt = DateTime.parse(json['expiresAt'] as String);
  final String id;
  final String token;
  final DateTime expiresAt;
  bool get expired => !expiresAt.isAfter(DateTime.now());
}
