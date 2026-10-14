package http

import (
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	authapp "github.com/lucas/radio-px-backend/internal/application/auth"
	channelapp "github.com/lucas/radio-px-backend/internal/application/channel"
	"github.com/lucas/radio-px-backend/internal/domain/admin"
	"github.com/lucas/radio-px-backend/internal/domain/user"
	"github.com/lucas/radio-px-backend/internal/infrastructure/auth/jwt"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/adminui"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/handlers"
	httpmw "github.com/lucas/radio-px-backend/internal/infrastructure/http/middleware"
	"github.com/lucas/radio-px-backend/internal/infrastructure/http/ws"
)

type Dependencies struct {
	Logger       *slog.Logger
	TokenManager *jwt.Manager
	Users        user.Repository
	AuthService  *authapp.Service
	Channels     *channelapp.Service
	WSHandler    *ws.Handler
	Admin        admin.Repository
	AdminUserIDs []string
}

func NewRouter(deps Dependencies) *chi.Mux {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(httpmw.CORS)

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	authHandler := handlers.NewAuthHandler(deps.AuthService)
	channelHandler := handlers.NewChannelHandler(deps.Channels)
	adminHandler := handlers.NewAdminHandler(deps.Admin, deps.WSHandler, deps.Logger)
	r.Get("/admin", adminui.Serve)
	r.Get("/admin/*", adminui.Serve)

	r.Route("/api/v1", func(r chi.Router) {
		r.Route("/admin", func(r chi.Router) {
			r.Use(httpmw.Authenticate(deps.TokenManager, deps.Users))
			r.Use(httpmw.RequireAdmin(deps.AdminUserIDs))
			r.Get("/me", adminHandler.Me)
			r.Get("/locations", adminHandler.Locations)
			r.Get("/summary", adminHandler.Summary)
			r.Get("/users", adminHandler.Users)
			r.Get("/channels", adminHandler.Channels)
			r.Delete("/channels/{channelID}", adminHandler.DeleteChannel)
		})
		r.Route("/auth", func(r chi.Router) {
			r.Post("/register", authHandler.Register)
			r.Post("/login", authHandler.Login)
			r.Post("/refresh", authHandler.Refresh)
			r.With(httpmw.Authenticate(deps.TokenManager, deps.Users)).Post("/logout", authHandler.Logout)
		})

		r.Route("/channels", func(r chi.Router) {
			r.Use(httpmw.Authenticate(deps.TokenManager, deps.Users))
			r.Get("/", channelHandler.List)
			r.Post("/", channelHandler.Create)
			r.Get("/{channelID}", channelHandler.Get)
			r.Post("/{channelID}/join", channelHandler.Join)
		})
	})

	r.Get("/ws", deps.WSHandler.ServeHTTP)

	return r
}
