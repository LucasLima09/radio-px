package channel

import (
	"context"
	"errors"
	"math"
	"testing"

	"github.com/google/uuid"
	domain "github.com/lucas/radio-px-backend/internal/domain/channel"
)

type testRepository struct {
	domain.Repository
	channels []*domain.Channel
	err      error
}

func (r testRepository) List(context.Context) ([]*domain.Channel, error)      { return r.channels, r.err }
func (r testRepository) CountMembers(context.Context, uuid.UUID) (int, error) { return 1, nil }
func ptr(v float64) *float64                                                  { return &v }

func TestNearby(t *testing.T) {
	r := testRepository{channels: []*domain.Channel{
		{Name: "far", Latitude: ptr(0), Longitude: ptr(2)},
		{Name: "second", Latitude: ptr(0), Longitude: ptr(.2)},
		{Name: "legacy"},
		{Name: "private", IsPrivate: true, Latitude: ptr(0), Longitude: ptr(0)},
		{Name: "first", Latitude: ptr(0), Longitude: ptr(0)},
	}}
	s := NewService(r, nil)
	got, err := s.List(context.Background(), ListInput{Latitude: ptr(0), Longitude: ptr(0), RadiusKm: 50})
	if err != nil || len(got) != 2 {
		t.Fatalf("got %v, %v", got, err)
	}
	if got[0].Name != "first" || *got[0].DistanceKm != 0 || got[1].Name != "second" || math.Abs(*got[1].DistanceKm-22.239) > .01 {
		t.Fatalf("unexpected ordering/distances: %+v", got)
	}
	all, err := s.List(context.Background(), ListInput{})
	if err != nil || len(all) != 5 || all[0].DistanceKm != nil {
		t.Fatalf("legacy listing: %v %v", all, err)
	}
}

func TestInvalidNearby(t *testing.T) {
	s := NewService(testRepository{}, nil)
	for _, in := range []ListInput{
		{Latitude: ptr(0)},
		{Latitude: ptr(91), Longitude: ptr(0), RadiusKm: 50},
		{Latitude: ptr(math.NaN()), Longitude: ptr(0), RadiusKm: 50},
		{Latitude: ptr(0), Longitude: ptr(math.Inf(1)), RadiusKm: 50},
		{Latitude: ptr(0), Longitude: ptr(0), RadiusKm: 0},
		{Latitude: ptr(0), Longitude: ptr(0), RadiusKm: 501},
		{Latitude: ptr(0), Longitude: ptr(0), RadiusKm: math.NaN()},
	} {
		if _, err := s.List(context.Background(), in); err == nil {
			t.Fatalf("accepted %+v", in)
		}
	}
}

func TestListReportsRepositoryFailure(t *testing.T) {
	want := errors.New("database unavailable")
	_, err := NewService(testRepository{err: want}, nil).List(context.Background(), ListInput{})
	if !errors.Is(err, want) {
		t.Fatalf("got %v", err)
	}
}

func TestGreatCircleDistance(t *testing.T) {
	if d := domain.DistanceKm(0, 179.9, 0, -179.9); math.Abs(d-22.239) > .01 {
		t.Fatalf("dateline: %f", d)
	}
	if d := domain.DistanceKm(90, 0, -90, 180); math.IsNaN(d) || math.Abs(d-20015.114) > .01 {
		t.Fatalf("antipodes: %f", d)
	}
}
