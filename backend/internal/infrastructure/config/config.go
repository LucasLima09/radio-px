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

	// Clip queue cache (in-memory, no persistence).
	ClipTTL           time.Duration `env:"CLIP_TTL" envDefault:"20m"`
	ClipMax           int           `env:"CLIP_MAX" envDefault:"200"`
	ClipMaxBytes      int64         `env:"CLIP_MAX_BYTES" envDefault:"5242880"`
	ClipMaxQueueBytes int64         `env:"CLIP_MAX_QUEUE_BYTES" envDefault:"67108864"`
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
	if cfg.ClipTTL <= 0 {
		cfg.ClipTTL = 20 * time.Minute
	}
	if cfg.ClipMax <= 0 {
		cfg.ClipMax = 200
	}
	if cfg.ClipMaxBytes <= 0 {
		cfg.ClipMaxBytes = 5 << 20
	}
	if cfg.ClipMaxQueueBytes <= 0 {
		cfg.ClipMaxQueueBytes = 64 << 20
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
