package com.example.luceneanalyzer;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import io.micrometer.prometheus.PrometheusMeterRegistry;
import java.net.InetAddress;
import java.time.Duration;
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
public class AnalyzerController {
  private final LuceneAnalyzerService analyzerService;
  private final PrometheusMeterRegistry prometheusRegistry;
  private final Counter analyzeSuccess;
  private final Counter analyzeFailure;
  private final Timer analyzeTimer;

  public AnalyzerController(
      LuceneAnalyzerService analyzerService,
      PrometheusMeterRegistry prometheusRegistry,
      MeterRegistry meterRegistry) {
    this.analyzerService = analyzerService;
    this.prometheusRegistry = prometheusRegistry;
    this.analyzeSuccess = meterRegistry.counter("analyze_requests_total", "result", "success");
    this.analyzeFailure = meterRegistry.counter("analyze_requests_total", "result", "failure");
    this.analyzeTimer = Timer.builder("analyze_duration_seconds")
        .publishPercentileHistogram()
        .minimumExpectedValue(Duration.ofMillis(10))
        .maximumExpectedValue(Duration.ofMinutes(2))
        .register(meterRegistry);
  }

  @GetMapping("/healthz")
  public String healthz() {
    return "ok";
  }

  @GetMapping("/info")
  public Map<String, String> info() throws Exception {
    String version = getenvOrDefault("APP_VERSION", "unknown");
    String gitSha = getenvOrDefault("GIT_SHA", "unknown");
    String arch = System.getProperty("os.arch", "unknown");
    String hostname = InetAddress.getLocalHost().getHostName();
    return Map.of(
        "version", version,
        "git_sha", gitSha,
        "arch", arch,
        "hostname", hostname
    );
  }

  @GetMapping(value = "/metrics", produces = MediaType.TEXT_PLAIN_VALUE)
  public String metrics() {
    return prometheusRegistry.scrape();
  }

  @PostMapping(
      value = "/analyze",
      consumes = MediaType.MULTIPART_FORM_DATA_VALUE,
      produces = MediaType.APPLICATION_JSON_VALUE)
  public AnalysisReport analyze(@RequestParam("file") MultipartFile file) {
    Timer.Sample sample = Timer.start();
    try {
      AnalysisReport report = analyzerService.analyze(file);
      analyzeSuccess.increment();
      return report;
    } catch (RuntimeException ex) {
      analyzeFailure.increment();
      throw ex;
    } finally {
      sample.stop(analyzeTimer);
    }
  }

  private String getenvOrDefault(String key, String fallback) {
    String value = System.getenv(key);
    return value == null || value.isBlank() ? fallback : value;
  }
}
