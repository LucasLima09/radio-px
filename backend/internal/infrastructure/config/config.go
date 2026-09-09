package config

import (
	"fmt"
	"os"
	"time"

	"github.com/caarlos0/env/v11"
)

type Config struct {
	HTTPPort        string        `env:"HTTP_PORT" envDefault:"8080"`
	DatabaseURL     string        `env:"DATABASE_URL"`
	JWTSecret       string        `env:"JWT_SECRET"`
	AccessTokenTTL  time.Duration `env:"ACCESS_TOKEN_TTL" envDefault:"15m"`
	RefreshTokenTTL time.Duration `env:"REFRESH_TOKEN_TTL" envDefault:"168h"`
}

func Load() (*Config, error) {
	cfg := &Config{}
	if err := env.Parse(cfg); err != nil {
		return nil, fmt.Errorf("parsing env: %w", err)
	}
	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if len(cfg.JWTSecret) < 16 {
		return nil, fmt.Errorf("JWT_SECRET must have at least 16 characters")
	}
	return cfg, nil
}

func (c *Config) AccessTokenTTLValue() time.Duration {
	if c.AccessTokenTTL <= 0 {
		return 15 * time.Minute
	}
	return c.AccessTokenTTL
}

func (c *Config) RefreshTokenTTLValue() time.Duration {
	if c.RefreshTokenTTL <= 0 {
		return 7 * 24 * time.Hour
	}
	return c.RefreshTokenTTL
}

func LoadFromEnvWithDefaults() {
	if os.Getenv("DATABASE_URL") == "" {
		os.Setenv("DATABASE_URL", "postgres://radio:radio@localhost:5432/radio_px?sslmode=disable")
	}
}
