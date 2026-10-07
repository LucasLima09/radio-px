DELETE FROM locations WHERE channel_id IS NULL;
ALTER TABLE locations ALTER COLUMN channel_id SET NOT NULL;