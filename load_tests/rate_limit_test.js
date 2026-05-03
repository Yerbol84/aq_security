// pkgs/aq_security/load_tests/rate_limit_test.js
//
// Rate limit testing - test rate limiting effectiveness
//
// Run: k6 run rate_limit_test.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Counter } from 'k6/metrics';

// Custom metrics
const rateLimitHits = new Counter('rate_limit_hits');
const rateLimitBlocks = new Counter('rate_limit_blocks');
const successfulRequests = new Counter('successful_requests');

// Test configuration
export const options = {
  scenarios: {
    // Scenario 1: Burst traffic from single IP
    burst_single_ip: {
      executor: 'constant-arrival-rate',
      rate: 200,              // 200 requests per second
      timeUnit: '1s',
      duration: '30s',
      preAllocatedVUs: 10,
      maxVUs: 50,
      exec: 'burstTraffic',
    },
    // Scenario 2: Sustained high traffic
    sustained_high: {
      executor: 'ramping-arrival-rate',
      startRate: 50,
      timeUnit: '1s',
      preAllocatedVUs: 20,
      maxVUs: 100,
      stages: [
        { duration: '1m', target: 100 },  // Ramp to 100 req/s
        { duration: '2m', target: 150 },  // Ramp to 150 req/s
        { duration: '1m', target: 200 },  // Ramp to 200 req/s
        { duration: '1m', target: 0 },    // Ramp down
      ],
      exec: 'sustainedTraffic',
    },
  },
  thresholds: {
    'rate_limit_blocks': ['count>0'],  // Should have some blocks
    'http_req_duration{status:429}': ['p(95)<100'], // 429 responses should be fast
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Burst traffic scenario
export function burstTraffic() {
  const url = `${BASE_URL}/api/users`;

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-Forwarded-For': '192.168.1.100', // Simulate same IP
    },
    tags: {
      scenario: 'burst',
    },
  };

  const response = http.get(url, params);

  const isRateLimited = check(response, {
    'status is 429': (r) => r.status === 429,
  });

  if (isRateLimited) {
    rateLimitBlocks.add(1);

    // Check rate limit headers
    check(response, {
      'has X-RateLimit-Limit': (r) => r.headers['X-Ratelimit-Limit'] !== undefined,
      'has X-RateLimit-Remaining': (r) => r.headers['X-Ratelimit-Remaining'] !== undefined,
      'has X-RateLimit-Reset': (r) => r.headers['X-Ratelimit-Reset'] !== undefined,
      'has Retry-After': (r) => r.headers['Retry-After'] !== undefined,
    });
  } else if (response.status === 200) {
    successfulRequests.add(1);
    rateLimitHits.add(1);
  }

  // No sleep - burst as fast as possible
}

// Sustained traffic scenario
export function sustainedTraffic() {
  const url = `${BASE_URL}/api/projects`;

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'X-Forwarded-For': `192.168.1.${Math.floor(Math.random() * 255)}`, // Different IPs
    },
    tags: {
      scenario: 'sustained',
    },
  };

  const response = http.get(url, params);

  if (response.status === 429) {
    rateLimitBlocks.add(1);
  } else if (response.status === 200) {
    successfulRequests.add(1);
    rateLimitHits.add(1);
  }

  sleep(0.1); // Small delay
}

export function handleSummary(data) {
  const summary = {
    test_type: 'rate_limit',
    duration_seconds: data.state.testRunDurationMs / 1000,
    total_requests: data.metrics.http_reqs.values.count,
    rate_limit_hits: data.metrics.rate_limit_hits ? data.metrics.rate_limit_hits.values.count : 0,
    rate_limit_blocks: data.metrics.rate_limit_blocks ? data.metrics.rate_limit_blocks.values.count : 0,
    successful_requests: data.metrics.successful_requests ? data.metrics.successful_requests.values.count : 0,
    block_rate: data.metrics.rate_limit_blocks ?
      (data.metrics.rate_limit_blocks.values.count / data.metrics.http_reqs.values.count * 100).toFixed(2) + '%' : '0%',
    p95_latency_ms: data.metrics.http_req_duration.values['p(95)'].toFixed(2),
    p99_latency_ms: data.metrics.http_req_duration.values['p(99)'].toFixed(2),
  };

  console.log('\n=== Rate Limit Test Summary ===');
  console.log(`Duration: ${summary.duration_seconds}s`);
  console.log(`Total Requests: ${summary.total_requests}`);
  console.log(`Rate Limit Hits: ${summary.rate_limit_hits}`);
  console.log(`Rate Limit Blocks: ${summary.rate_limit_blocks}`);
  console.log(`Successful Requests: ${summary.successful_requests}`);
  console.log(`Block Rate: ${summary.block_rate}`);
  console.log(`P95 Latency: ${summary.p95_latency_ms}ms`);
  console.log(`P99 Latency: ${summary.p99_latency_ms}ms`);
  console.log('================================\n');

  return {
    'rate_limit_summary.json': JSON.stringify(summary, null, 2),
  };
}
