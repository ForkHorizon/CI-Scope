package agent

import (
	"errors"
	"strconv"
	"strings"
	"time"
)

type bootstrapDurationSpec struct {
	key, message     string
	minimum, maximum int64
	destination      *time.Duration
	fallback         time.Duration
}

func loadBootstrapOptionalConfig(getenv func(string) string, config *BootstrapConfig) error {
	for key, destination := range map[string]*string{
		"CI_SCOPE_ENROLLMENT_TOKEN":  &config.EnrollmentToken,
		"CI_SCOPE_DEVICE_SECRET":     &config.DeviceSecret,
		"CI_SCOPE_ENROLLMENT_ISSUER": &config.EnrollmentIssuer,
		"CI_SCOPE_POOL_IDENTITY":     &config.PoolIdentity,
	} {
		*destination = strings.TrimSpace(getenv(key))
	}
	values := []*string{&config.EnrollmentToken, &config.DeviceSecret, &config.EnrollmentIssuer}
	if optionalBootstrapCount(values) != 0 && optionalBootstrapCount(values) != len(values) {
		return errors.New("enrollment configuration must provide token, device secret and issuer together")
	}
	if err := parseBootstrapDuration(getenv, bootstrapDurationSpec{key: "CI_SCOPE_HEARTBEAT_INTERVAL_MS", message: "CI_SCOPE_HEARTBEAT_INTERVAL_MS must be between 1000 and 86400000", minimum: 1000, maximum: 24 * 60 * 60 * 1000, destination: &config.HeartbeatInterval, fallback: 15 * time.Second}); err != nil {
		return err
	}
	return parseBootstrapDuration(getenv, bootstrapDurationSpec{key: "CI_SCOPE_HTTP_TIMEOUT_MS", message: "CI_SCOPE_HTTP_TIMEOUT_MS must be between 100 and 300000", minimum: 100, maximum: 5 * 60 * 1000, destination: &config.HTTPTimeout, fallback: 10 * time.Second})
}

func optionalBootstrapCount(values []*string) int {
	count := 0
	for _, value := range values {
		if *value != "" {
			count++
		}
	}
	return count
}

func parseBootstrapDuration(getenv func(string) string, spec bootstrapDurationSpec) error {
	*spec.destination = spec.fallback
	raw := strings.TrimSpace(getenv(spec.key))
	if raw == "" {
		return nil
	}
	milliseconds, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || milliseconds < spec.minimum || milliseconds > spec.maximum {
		return errors.New(spec.message)
	}
	*spec.destination = time.Duration(milliseconds) * time.Millisecond
	return nil
}
