-- SYNTHETIC DEMO DATA for the legacy MySQL 5.7 container. Not real customers.
CREATE DATABASE IF NOT EXISTS corebank;
USE corebank;

CREATE TABLE IF NOT EXISTS accounts (
  acct_no       VARCHAR(12) PRIMARY KEY,
  holder        VARCHAR(64) NOT NULL,
  balance       DECIMAL(12,2) NOT NULL,
  pin_md5       CHAR(32) NOT NULL  -- intentional finding: MD5-hashed PIN
);

INSERT INTO accounts VALUES
  ('000111222', 'Jane Synthetic', 1043.22, MD5('1234')),
  ('000111223', 'John Synthetic',   88.10, MD5('0000')),
  ('000111224', 'Ava Synthetic',  5120.00, MD5('4321'));

CREATE TABLE IF NOT EXISTS card_vault (
  card_ref      VARCHAR(16) PRIMARY KEY,
  pan_3des      VARBINARY(64) NOT NULL  -- intentional finding: 3DES-encrypted PAN
);

INSERT INTO card_vault VALUES
  ('CARD-0001', UNHEX('A1B2C3D4E5F60718')),
  ('CARD-0002', UNHEX('0F1E2D3C4B5A6978'));
