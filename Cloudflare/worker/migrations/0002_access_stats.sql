CREATE TABLE IF NOT EXISTS video_access_stats_daily (
    video_id TEXT NOT NULL,
    access_date TEXT NOT NULL,
    country_code TEXT NOT NULL,
    device_class TEXT NOT NULL CHECK (
        device_class IN ('mobile', 'tablet', 'desktop')
    ),
    page_views INTEGER NOT NULL DEFAULT 0,
    play_starts INTEGER NOT NULL DEFAULT 0,
    play_completions INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (video_id, access_date, country_code, device_class),
    FOREIGN KEY (video_id) REFERENCES videos(id)
);

CREATE INDEX IF NOT EXISTS video_access_stats_date_idx
    ON video_access_stats_daily(access_date);
