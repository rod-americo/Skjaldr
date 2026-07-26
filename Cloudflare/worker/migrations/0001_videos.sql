CREATE TABLE IF NOT EXISTS videos (
    id TEXT PRIMARY KEY,
    short_code TEXT NOT NULL UNIQUE,
    object_key TEXT NOT NULL UNIQUE,
    idempotency_key TEXT NOT NULL UNIQUE,
    original_filename TEXT,
    content_type TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    duration_seconds REAL,
    status TEXT NOT NULL CHECK (
        status IN (
            'pending', 'uploading', 'available', 'failed',
            'revoked', 'expired', 'deleted'
        )
    ),
    created_at TEXT NOT NULL,
    uploaded_at TEXT,
    expires_at TEXT,
    revoked_at TEXT,
    deleted_at TEXT,
    sha256 TEXT NOT NULL,
    etag TEXT,
    upload_attempts INTEGER NOT NULL DEFAULT 0,
    failure_reason TEXT,
    access_count INTEGER NOT NULL DEFAULT 0,
    last_accessed_at TEXT
);

CREATE INDEX IF NOT EXISTS videos_status_idx ON videos(status);
CREATE INDEX IF NOT EXISTS videos_expires_idx ON videos(expires_at);
CREATE INDEX IF NOT EXISTS videos_created_idx ON videos(created_at);
