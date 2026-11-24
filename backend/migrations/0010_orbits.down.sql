ALTER TABLE locations DROP COLUMN orbit_id;
ALTER TABLE locations ADD COLUMN orbit_id TEXT;
DROP TABLE IF EXISTS orbits;
