package handlers

import (
	"net/http/httptest"
	"testing"

	channelapp "github.com/lucas/radio-px-backend/internal/application/channel"
)

func TestListRejectsInvalidLocationQuery(t *testing.T) {
	h := NewChannelHandler(channelapp.NewService(nil, nil))
	for _, query := range []string{
		"latitude=abc&longitude=0",
		"latitude=0",
		"longitude=0",
		"latitude=NaN&longitude=0",
		"latitude=0&longitude=181",
		"radiusKm=50",
		"latitude=0&longitude=0&radiusKm=0",
		"latitude=0&longitude=0&radiusKm=501",
		"latitude=0&longitude=0&radiusKm=NaN",
	} {
		t.Run(query, func(t *testing.T) {
			w := httptest.NewRecorder()
			h.List(w, httptest.NewRequest("GET", "/api/v1/channels?"+query, nil))
			if w.Code != 400 {
				t.Fatalf("status %d: %s", w.Code, w.Body.String())
			}
		})
	}
}
