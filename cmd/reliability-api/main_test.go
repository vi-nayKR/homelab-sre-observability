package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func executeRequest(t *testing.T, handler http.Handler, method, target, body string) *httptest.ResponseRecorder {
	t.Helper()
	request := httptest.NewRequest(method, target, strings.NewReader(body))
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)
	return recorder
}

func TestReadinessCanFailWithoutBreakingLiveness(t *testing.T) {
	app := newApplication(&bytes.Buffer{})
	handler := app.routes()

	if got := executeRequest(t, handler, http.MethodGet, "/health/ready", "").Code; got != http.StatusOK {
		t.Fatalf("initial readiness status = %d, want %d", got, http.StatusOK)
	}
	if got := executeRequest(t, handler, http.MethodPost, "/admin/readiness?ready=false", "").Code; got != http.StatusOK {
		t.Fatalf("readiness injection status = %d, want %d", got, http.StatusOK)
	}
	if got := executeRequest(t, handler, http.MethodGet, "/health/ready", "").Code; got != http.StatusServiceUnavailable {
		t.Fatalf("failed readiness status = %d, want %d", got, http.StatusServiceUnavailable)
	}
	if got := executeRequest(t, handler, http.MethodGet, "/health/live", "").Code; got != http.StatusOK {
		t.Fatalf("liveness status = %d, want %d", got, http.StatusOK)
	}
}

func TestInjectedFailureAppearsInBoundedMetrics(t *testing.T) {
	app := newApplication(&bytes.Buffer{})
	handler := app.routes()

	if got := executeRequest(t, handler, http.MethodGet, "/work?fail=true", "").Code; got != http.StatusServiceUnavailable {
		t.Fatalf("work status = %d, want %d", got, http.StatusServiceUnavailable)
	}
	metrics := executeRequest(t, handler, http.MethodGet, "/metrics", "").Body.String()
	want := `sre_demo_http_requests_total{method="GET",route="/work",status_class="5xx"} 1`
	if !strings.Contains(metrics, want) {
		t.Fatalf("metrics do not contain %q\n%s", want, metrics)
	}
	if strings.Contains(metrics, "fail=true") {
		t.Fatal("unbounded query parameter leaked into metric labels")
	}
}

func TestDelayIsBounded(t *testing.T) {
	app := newApplication(&bytes.Buffer{})
	response := executeRequest(t, app.routes(), http.MethodGet, "/work?delay_ms=5001", "")
	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusBadRequest)
	}
}

func TestAlertWebhookBoundsStatusLabel(t *testing.T) {
	app := newApplication(&bytes.Buffer{})
	handler := app.routes()
	body := `{"status":"unexpected-user-value","alerts":[]}`
	if got := executeRequest(t, handler, http.MethodPost, "/alerts", body).Code; got != http.StatusNoContent {
		t.Fatalf("alert status = %d, want %d", got, http.StatusNoContent)
	}
	metrics := executeRequest(t, handler, http.MethodGet, "/metrics", "").Body.String()
	if !strings.Contains(metrics, `sre_demo_alertmanager_webhooks_total{status="unknown"} 1`) {
		t.Fatal("unknown Alertmanager status was not normalized")
	}
}
