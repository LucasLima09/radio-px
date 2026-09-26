ALTER TABLE channels
 ADD COLUMN latitude DOUBLE PRECISION,
 ADD COLUMN longitude DOUBLE PRECISION,
 ADD CONSTRAINT channels_location_valid CHECK (
  (latitude IS NULL AND longitude IS NULL) OR
  (latitude IS NOT NULL AND longitude IS NOT NULL AND
   latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)
 );
