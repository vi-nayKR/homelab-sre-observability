package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const maxWorkDelay = 5 * time.Second

type serviceMetrics struct {
	requests *prometheus.CounterVec
	duration *prometheus.HistogramVec
	inFlight prometheus.Gauge
	ready    prometheus.Gauge
	alerts   *prometheus.CounterVec
}

type application struct {
	logger   *slog.Logger
	registry *prometheus.Registry
	metrics  serviceMetrics
	ready    atomic.Bool
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	if r.status != 0 {
		return
	}
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func (r *statusRecorder) Write(body []byte) (int, error) {
	if r.status == 0 {
		r.WriteHeader(http.StatusOK)
	}
	return r.ResponseWriter.Write(body)
}

func newApplication(logOutput io.Writer) *application {
	registry := prometheus.NewRegistry()
	registry.MustRegister(
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	)

	metrics := serviceMetrics{
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Namespace: "sre_demo",
			Name:      "http_requests_total",
			Help:      "Completed HTTP requests by bounded route and status class.",
		}, []string{"method", "route", "status_class"}),
		duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Namespace: "sre_demo",
			Name:      "http_request_duration_seconds",
			Help:      "HTTP request duration by bounded route.",
			Buckets:   []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
		}, []string{"method", "route"}),
		inFlight: prometheus.NewGauge(prometheus.GaugeOpts{
			Namespace: "sre_demo",
			Name:      "http_requests_in_flight",
			Help:      "HTTP requests currently being served.",
		}),
		ready: prometheus.NewGauge(prometheus.GaugeOpts{
			Namespace: "sre_demo",
			Name:      "ready",
			Help:      "Whether the service is ready to receive traffic (1 ready, 0 not ready).",
		}),
		alerts: prometheus.NewCounterVec(prometheus.CounterOpts{
			Namespace: "sre_demo",
			Name:      "alertmanager_webhooks_total",
			Help:      "Alertmanager webhook payloads received by status.",
		}, []string{"status"}),
	}
	registry.MustRegister(metrics.requests, metrics.duration, metrics.inFlight, metrics.ready, metrics.alerts)

	app := &application{
		logger:   slog.New(slog.NewJSONHandler(logOutput, &slog.HandlerOptions{Level: slog.LevelInfo})),
		registry: registry,
		metrics:  metrics,
	}
	app.ready.Store(true)
	app.metrics.ready.Set(1)
	return app
}

func (a *application) routes() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("GET /{$}", a.instrument("/", http.HandlerFunc(a.handleRoot)))
	mux.Handle("GET /work", a.instrument("/work", http.HandlerFunc(a.handleWork)))
	mux.Handle("GET /health/live", a.instrument("/health/live", http.HandlerFunc(a.handleLive)))
	mux.Handle("GET /health/ready", a.instrument("/health/ready", http.HandlerFunc(a.handleReady)))
	mux.Handle("POST /admin/readiness", a.instrument("/admin/readiness", http.HandlerFunc(a.handleSetReadiness)))
	mux.Handle("POST /alerts", a.instrument("/alerts", http.HandlerFunc(a.handleAlerts)))
	mux.Handle("GET /metrics", promhttp.HandlerFor(a.registry, promhttp.HandlerOpts{}))
	return mux
}

func (a *application) instrument(route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		recorder := &statusRecorder{ResponseWriter: w}
		method := boundedMethod(r.Method)
		a.metrics.inFlight.Inc()
		defer a.metrics.inFlight.Dec()

		next.ServeHTTP(recorder, r)
		if recorder.status == 0 {
			recorder.status = http.StatusOK
		}

		elapsed := time.Since(started)
		class := fmt.Sprintf("%dxx", recorder.status/100)
		a.metrics.requests.WithLabelValues(method, route, class).Inc()
		a.metrics.duration.WithLabelValues(method, route).Observe(elapsed.Seconds())
		a.logger.Info("request completed",
			"method", method,
			"route", route,
			"status", recorder.status,
			"duration_ms", elapsed.Milliseconds(),
		)
	})
}

func boundedMethod(method string) string {
	switch method {
	case http.MethodGet, http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete:
		return method
	default:
		return "OTHER"
	}
}

func (a *application) handleRoot(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"service": "homelab-sre-observability-demo",
		"status":  "ok",
	})
}

func (a *application) handleWork(w http.ResponseWriter, r *http.Request) {
	delay, err := parseDelay(r.URL.Query().Get("delay_ms"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	if delay > 0 {
		timer := time.NewTimer(delay)
		defer timer.Stop()
		select {
		case <-timer.C:
		case <-r.Context().Done():
			return
		}
	}
	if strings.EqualFold(r.URL.Query().Get("fail"), "true") {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "injected dependency failure"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"result": "work completed"})
}

func parseDelay(raw string) (time.Duration, error) {
	if raw == "" {
		return 0, nil
	}
	milliseconds, err := strconv.Atoi(raw)
	if err != nil || milliseconds < 0 {
		return 0, errors.New("delay_ms must be a non-negative integer")
	}
	delay := time.Duration(milliseconds) * time.Millisecond
	if delay > maxWorkDelay {
		return 0, fmt.Errorf("delay_ms must not exceed %d", maxWorkDelay.Milliseconds())
	}
	return delay, nil
}

func (a *application) handleLive(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "live"})
}

func (a *application) handleReady(w http.ResponseWriter, _ *http.Request) {
	if !a.ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not_ready"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func (a *application) handleSetReadiness(w http.ResponseWriter, r *http.Request) {
	ready, err := strconv.ParseBool(r.URL.Query().Get("ready"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "ready must be true or false"})
		return
	}
	a.ready.Store(ready)
	if ready {
		a.metrics.ready.Set(1)
	} else {
		a.metrics.ready.Set(0)
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ready": ready})
}

func (a *application) handleAlerts(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		Status string            `json:"status"`
		Alerts []json.RawMessage `json:"alerts"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	if err := decoder.Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid Alertmanager payload"})
		return
	}
	status := payload.Status
	if status != "firing" && status != "resolved" {
		status = "unknown"
	}
	a.metrics.alerts.WithLabelValues(status).Inc()
	a.logger.Warn("alertmanager webhook received", "status", status, "alert_count", len(payload.Alerts))
	w.WriteHeader(http.StatusNoContent)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func runServer() error {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	app := newApplication(os.Stdout)
	server := &http.Server{
		Addr:              ":" + port,
		Handler:           app.routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErrors := make(chan error, 1)
	go func() {
		app.logger.Info("server starting", "address", server.Addr)
		serverErrors <- server.ListenAndServe()
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	case err := <-serverErrors:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	}
}

func runHealthcheck() error {
	url := os.Getenv("HEALTHCHECK_URL")
	if url == "" {
		url = "http://127.0.0.1:8080/health/live"
	}
	client := &http.Client{Timeout: 2 * time.Second}
	response, err := client.Get(url)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("healthcheck returned HTTP %d", response.StatusCode)
	}
	return nil
}

func main() {
	var err error
	if len(os.Args) == 2 && os.Args[1] == "healthcheck" {
		err = runHealthcheck()
	} else {
		err = runServer()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
