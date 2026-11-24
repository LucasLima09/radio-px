-- Orbits cadastrados uma vez no painel admin. O app reconhece cada um pelo
-- nome que ele anuncia no Bluetooth (identifier), sem parear por aparelho.
CREATE TABLE IF NOT EXISTS orbits (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT NOT NULL,
    identifier TEXT NOT NULL UNIQUE,
    active     BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- O orbit_id anterior guardava o ID que o navegador dá ao aparelho, que muda
-- de um navegador para outro. Passa a apontar para o Orbit cadastrado;
-- orbit_name continua como cópia do nome no momento do encontro.
ALTER TABLE locations DROP COLUMN orbit_id;
ALTER TABLE locations ADD COLUMN orbit_id UUID REFERENCES orbits(id) ON DELETE SET NULL;
