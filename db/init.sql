CREATE DATABASE IF NOT EXISTS appdb;
USE appdb;

CREATE TABLE IF NOT EXISTS healthchecks (
    id INT AUTO_INCREMENT PRIMARY KEY,
    checked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(32) NOT NULL,
    notes TEXT
);

INSERT INTO healthchecks (status, notes)
VALUES ('ok', 'Initial database seed');
