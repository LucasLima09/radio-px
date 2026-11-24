-- A localização passa a ser reportada apenas quando o app encontra um Orbit
-- via Bluetooth (rede mesh). As linhas antigas, do GPS contínuo, ficam com
-- essas colunas nulas.
ALTER TABLE locations
    ADD COLUMN orbit_name TEXT,
    ADD COLUMN orbit_id   TEXT,
    ADD COLUMN rssi       SMALLINT;
