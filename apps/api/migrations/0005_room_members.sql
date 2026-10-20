CREATE TABLE room_members (
  room_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  user_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  seat_no TINYINT UNSIGNED NOT NULL,
  joined_at DATETIME(3) NOT NULL DEFAULT (UTC_TIMESTAMP(3)),
  PRIMARY KEY (room_id, user_id),
  UNIQUE KEY uq_members_room_seat (room_id, seat_no),
  KEY ix_members_user_room (user_id, room_id),
  CONSTRAINT ck_members_seat CHECK (seat_no IN (1, 2)),
  CONSTRAINT fk_members_room FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE,
  CONSTRAINT fk_members_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
