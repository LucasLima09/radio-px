package adminui

import (
	"embed"
	"net/http"
	"strings"
)

//go:embed index.html admin.css admin.js leaflet.css leaflet.js
var assets embed.FS

func Serve(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
	w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://tile.openstreetmap.org; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
	name := strings.TrimPrefix(r.URL.Path, "/admin")
	switch name {
	case "", "/":
		name = "index.html"
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
	case "/admin.css":
		name = "admin.css"
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
	case "/admin.js":
		name = "admin.js"
		w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	case "/leaflet.js":
		name = "leaflet.js"
		w.Header().Set("Content-Type", "text/javascript; charset=utf-8")
	case "/leaflet.css":
		name = "leaflet.css"
		w.Header().Set("Content-Type", "text/css; charset=utf-8")
	default:
		http.NotFound(w, r)
		return
	}
	content, err := assets.ReadFile(name)
	if err != nil {
		http.Error(w, "unavailable", 500)
		return
	}
	_, _ = w.Write(content)
}
