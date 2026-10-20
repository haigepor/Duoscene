ALTER TABLE users
  ADD COLUMN recovery_token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL;
