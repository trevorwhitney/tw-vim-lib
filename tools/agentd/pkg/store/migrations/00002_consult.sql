-- +goose Up
ALTER TABLE jobs ADD COLUMN window_id TEXT NOT NULL DEFAULT '';
ALTER TABLE jobs ADD COLUMN verdicts_json TEXT NOT NULL DEFAULT '';
ALTER TABLE escalations ADD COLUMN answer TEXT NOT NULL DEFAULT '';

-- +goose Down
ALTER TABLE jobs DROP COLUMN window_id;
ALTER TABLE jobs DROP COLUMN verdicts_json;
ALTER TABLE escalations DROP COLUMN answer;
