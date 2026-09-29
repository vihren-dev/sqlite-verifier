"""Shared SQL fixture text for translation and generated-Lean tests."""

RICH_BASELINE = """
CREATE INDEX event_time ON events(occurred);
CREATE TABLE events(id TEXT PRIMARY KEY, occurred INTEGER NOT NULL, message TEXT NOT NULL,
                    author TEXT, UNIQUE(occurred, message));
CREATE UNIQUE INDEX author_message ON events(author, message);
CREATE TABLE ledger(version BIGINT PRIMARY KEY, description TEXT NOT NULL,
                    installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    success BOOLEAN NOT NULL, checksum BLOB NOT NULL, execution_time BIGINT NOT NULL);
"""
"""A declarative baseline using every supported column, key and index feature."""
