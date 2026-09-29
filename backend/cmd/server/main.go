package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"time"

	authapp "github.com/lucas/radio-px-backend/internal/application/auth"
	channelapp "github.com/lucas/radio-px-backend/internal/application/channel"
	appjwt "github.com/lucas/radio-px-backend/internal/infrastructure/auth/jwt"
	"github.com/lucas/radio-px-backend/internal/infrastructure/config"
	apphttp "github.com/lucas/radio-px-backend/internal/infrastructure/http"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/ws"
	"github.com/lucas/radio-px-backend/internal/infrastructure/persistence/postgres"
)

func main() {
	logger := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	cfg, err := config.Load()
	if err != nil {
		logger.Error("loading config", "error", err)
		os.Exit(1)
	}

	ctx := context.Background()

	if err := postgres.RunMigrations(cfg.DatabaseURL); err != nil {
		logger.Error("running migrations", "error", err)
		os.Exit(1)
	}

	pool, err := postgres.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		logger.Error("connecting to postgres", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	userRepo := postgres.NewUserRepository(pool)
	channelRepo := postgres.NewChannelRepository(pool)
	refreshRepo := postgres.NewRefreshTokenRepository(pool)
	locationRepo := postgres.NewLocationRepository(pool)

	tokenManager := appjwt.New(cfg.JWTSecret, "radio-px", cfg.AccessTokenTTLValue())

	authService := authapp.NewService(userRepo, refreshRepo, tokenManager, cfg.RefreshTokenTTLValue())
	channelService := channelapp.NewService(channelRepo, userRepo)

	hub := ws.NewHub(logger, cfg.ClipTTL, cfg.ClipMax, cfg.ClipMaxBytes)
	wsHandler := ws.NewHandler(hub, logger, tokenManager, userRepo, channelService, locationRepo)

	router := apphttp.NewRouter(apphttp.Dependencies{
		Logger:       logger,
		TokenManager: tokenManager,
		Users:        userRepo,
		AuthService:  authService,
		Channels:     channelService,
		WSHandler:    wsHandler,
	})

	server := &http.Server{
		Addr:              ":" + cfg.HTTPPort,
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,
	}

	logger.Info("radio-px backend listening", "addr", server.Addr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logger.Error("http server", "error", err)
		os.Exit(1)
	}
}
