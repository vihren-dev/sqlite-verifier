CREATE TABLE history (
	id text primary key,
	timestamp integer not null,
	duration integer not null,
	exit integer not null,
	command text not null,
	cwd text not null,
	session text not null,
	hostname text not null, deleted_at integer, author text, intent text,

	unique(timestamp, cwd, command)
);

CREATE INDEX idx_history_command on history(command);

CREATE INDEX idx_history_command_timestamp on history(
	command,
	timestamp
);

CREATE INDEX idx_history_timestamp on history(timestamp);
