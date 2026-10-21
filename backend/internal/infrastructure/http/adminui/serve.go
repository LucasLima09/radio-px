package adminui

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
)

// O painel React (admin_web) é compilado para dist/ e embutido no binário.
//
//go:embed dist
var assets embed.FS

var distFS = mustSub(assets, "dist")

var contentTypes = map[string]string{
	".html":  "text/html; charset=utf-8",
	".js":    "text/javascript; charset=utf-8",
	".mjs":   "text/javascript; charset=utf-8",
	".css":   "text/css; charset=utf-8",
	".json":  "application/json; charset=utf-8",
	".map":   "application/json; charset=utf-8",
	".svg":   "image/svg+xml",
	".png":   "image/png",
	".jpg":   "image/jpeg",
	".jpeg":  "image/jpeg",
	".gif":   "image/gif",
	".webp":  "image/webp",
	".ico":   "image/x-icon",
	".woff":  "font/woff",
	".woff2": "font/woff2",
	".txt":   "text/plain; charset=utf-8",
}

const contentSecurityPolicy = "default-src 'self'; " +
	"script-src 'self'; " +
	"style-src 'self' 'unsafe-inline'; " +
	"img-src 'self' data: blob: https://tile.openstreetmap.org https://*.tile.openstreetmap.org; " +
	"connect-src 'self'; " +
	"font-src 'self' data:; " +
	"frame-ancestors 'none'; base-uri 'none'; form-action 'self'"

func mustSub(fsys embed.FS, dir string) fs.FS {
	sub, err := fs.Sub(fsys, dir)
	if err != nil {
		panic(err)
	}
	return sub
}

// Serve entrega o painel React embutido em /admin.
func Serve(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Security-Policy", contentSecurityPolicy)
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")

	rel := strings.TrimPrefix(r.URL.Path, "/admin")
	rel = strings.TrimPrefix(rel, "/")
	if rel == "" {
		rel = "index.html"
	}

	if data, err := fs.ReadFile(distFS, rel); err == nil {
		writeAsset(w, rel, data)
		return
	}

	// Arquivos com extensão ausentes são 404; o resto cai no index (SPA).
	if strings.Contains(path.Base(rel), ".") {
		http.NotFound(w, r)
		return
	}
	data, err := fs.ReadFile(distFS, "index.html")
	if err != nil {
		http.Error(w, "unavailable", http.StatusInternalServerError)
		return
	}
	writeAsset(w, "index.html", data)
}

func writeAsset(w http.ResponseWriter, name string, data []byte) {
	if ct, ok := contentTypes[strings.ToLower(path.Ext(name))]; ok {
		w.Header().Set("Content-Type", ct)
	}
	if name == "index.html" || name == "theme-init.js" {
		w.Header().Set("Cache-Control", "no-store")
	} else {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	}
	_, _ = w.Write(data)
}
