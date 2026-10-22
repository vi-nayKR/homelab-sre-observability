package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSecureDefaultsDisableFaultAndReceiverEndpoints(t *testing.T) {
	app := newApplication(io.Discard)
	for _, tc := range []struct {
		method, path string
		status       int
	}{
		{"GET", "/work", 200},
		{"GET", "/work?fail=true", 403},
		{"GET", "/work?delay_ms=1", 403},
		{"POST", "/admin/readiness?ready=false", 404},
		{"POST", "/alerts", 404},
	} {
		if got := executeRequest(t, app.routes(), tc.method, tc.path, "").Code; got != tc.status {
			t.Errorf("%s %s = %d, want %d", tc.method, tc.path, got, tc.status)
		}
	}
	if !app.ready.Load() {
		t.Fatal("disabled readiness endpoint changed state")
	}
}

func TestWebhookAuthenticationAndStrictPayload(t *testing.T) {
	app := newApplication(io.Discard)
	app.alertToken = strings.Repeat("t", 48)
	for _, tc := range []struct {
		name, authorization, body string
		status                    int
	}{
		{"missing", "", `{"status":"firing"}`, 401},
		{"wrong", "Bearer incorrect", `{"status":"firing"}`, 401},
		{"valid", "Bearer " + app.alertToken, `{"status":"firing","alerts":[]}`, 204},
		{"trailing JSON", "Bearer " + app.alertToken, `{"status":"firing"} {}`, 400},
		{"oversized", "Bearer " + app.alertToken, `{"status":"` + strings.Repeat("x", 1<<20) + `"}`, 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodPost, "/alerts", strings.NewReader(tc.body))
			req.Header.Set("Authorization", tc.authorization)
			w := httptest.NewRecorder()
			app.routes().ServeHTTP(w, req)
			if w.Code != tc.status {
				t.Fatalf("status = %d, want %d", w.Code, tc.status)
			}
		})
	}
	if got := executeRequest(t, app.routes(), "POST", "/admin/readiness?ready=false", "").Code; got != 404 {
		t.Fatal("receiver enabled lab controls")
	}
}

func TestRuntimeConfigurationFailsClosed(t *testing.T) {
	t.Setenv("LAB_CONTROLS_ENABLED", "")
	t.Setenv("ALERT_WEBHOOK_TOKEN_FILE", "")
	app, err := configuredApplication(io.Discard)
	if err != nil || app.labControls || app.alertToken != "" {
		t.Fatalf("unexpected defaults: %v", err)
	}
	t.Setenv("LAB_CONTROLS_ENABLED", "invalid")
	if _, err := configuredApplication(io.Discard); err == nil {
		t.Fatal("accepted invalid mode")
	}
	t.Setenv("LAB_CONTROLS_ENABLED", "false")
	path := filepath.Join(t.TempDir(), "webhook-token")
	t.Setenv("ALERT_WEBHOOK_TOKEN_FILE", path)
	if _, err := configuredApplication(io.Discard); err == nil {
		t.Fatal("accepted missing token file")
	}
	if err := os.WriteFile(path, []byte("short"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := configuredApplication(io.Discard); err == nil {
		t.Fatal("accepted short token")
	}
	if err := os.WriteFile(path, []byte(strings.Repeat("t", 48)+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	app, err = configuredApplication(io.Discard)
	if err != nil || app.labControls || len(app.alertToken) != 48 {
		t.Fatalf("valid token config failed: %v", err)
	}
}

func TestDelayRejectsDurationOverflow(t *testing.T) {
	for _, value := range []string{"9223372036855", "9223372036854775807", "999999999999999999999999"} {
		if _, err := parseDelay(value); err == nil {
			t.Errorf("accepted overflowing delay %s", value)
		}
	}
}

func TestDrainDropsReadinessWithoutLivenessFailure(t *testing.T) {
	app := newApplication(io.Discard)
	app.markUnready()
	if executeRequest(t, app.routes(), "GET", "/health/ready", "").Code != 503 {
		t.Fatal("drain did not remove readiness")
	}
	if executeRequest(t, app.routes(), "GET", "/health/live", "").Code != 200 {
		t.Fatal("drain broke liveness")
	}
}
