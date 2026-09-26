package channel

import (
	"errors"
	"math"
)

var ErrInvalidLocation = errors.New("latitude and longitude must be supplied together and within valid ranges")
var ErrInvalidRadius = errors.New("radiusKm must be greater than 0 and at most 500")

func ValidateLocation(lat, lon *float64) error {
	if lat == nil && lon == nil {
		return nil
	}
	if lat == nil || lon == nil || math.IsNaN(*lat) || math.IsNaN(*lon) || math.IsInf(*lat, 0) || math.IsInf(*lon, 0) || *lat < -90 || *lat > 90 || *lon < -180 || *lon > 180 {
		return ErrInvalidLocation
	}
	return nil
}

// DistanceKm returns great-circle distance, not road distance.
func DistanceKm(lat1, lon1, lat2, lon2 float64) float64 {
	const rad = math.Pi / 180
	dlat, dlon := (lat2-lat1)*rad, (lon2-lon1)*rad
	a := math.Pow(math.Sin(dlat/2), 2) + math.Cos(lat1*rad)*math.Cos(lat2*rad)*math.Pow(math.Sin(dlon/2), 2)
	a = math.Max(0, math.Min(1, a))
	return 6371.0088 * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
