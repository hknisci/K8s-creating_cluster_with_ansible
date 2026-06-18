package com.dreamgames.controller;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class QueryParamController {

    private static final Logger log = LoggerFactory.getLogger(QueryParamController.class);
    private final Counter requestCounter;

    public QueryParamController(MeterRegistry registry) {
        this.requestCounter = Counter.builder("app_echo_requests_total")
                .description("Total number of echo endpoint requests")
                .register(registry);
    }

    @GetMapping("/echo")
    public ResponseEntity<Map<String, String>> echo(
            @RequestParam Map<String, String> params) {

        requestCounter.increment();

        if (params.isEmpty()) {
            log.info("Received request with no query parameters");
        } else {
            params.forEach((key, value) ->
                log.info("Query parameter received: key={} value={}", key, value));
        }

        return ResponseEntity.ok(params);
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of("status", "UP"));
    }
}
