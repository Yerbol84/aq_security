// pkgs/aq_security/load_tests/concurrent_users.js
//
// Concurrent users test - test system with 10k+ concurrent connections
//
// Run: k6 run concurrent_users.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Gauge, Trend } from 'k6/metrics';

// Custom metrics
const activeUsers = new Gauge('active_users');
const totalRequests = new Counter('total_requests');
const failedRequests = new Counter('failed_requests');
const responseTime = new Trend('response_time');

// Test configuration
export const options = {
  scenarios: {
    // Ramp up to 10k users
    concurrent_users: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '2m', target: 1000 },   // Ramp to 1k users
        { duration: '2m', target: 5000 },   // Ramp to 5k users
        { duration: '2m', target: 10000 },  // Ramp to 10k users
        { duration: '5m', target: 10000 },  // Stay at 10k users
        { duration: '2m', target: 5000 },   // Ramp down to 5k
        { duration: '2m', target: 0 },      // Ramp down to 0
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    'http_req_duration': ['p(95)<1000', 'p(99)<2000'], // 95% < 1s, 99% < 2s
    'http_req_failed': ['rate<0.05'],                   // Error rate < 5%
    'failed_requests': ['count<500'],                   // Max 500 failed requests
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export default function () {
  // Update active users gauge
  activeUsers.add(1);

  // Simulate user session
  userSession();

  activeUsers.add(-1);
}

function userSession() {
  // 1. Health check
  makeRequest('/api/health', 'health_check');

  sleep(Math.random() * 2 + 1); // 1-3 seconds

  // 2. Get users list
  makeRequest('/api/users', 'list_users');

  sleep(Math.random() * 3 + 2); // 2-5 seconds

  // 3. Get specific user
  const userId = Math.floor(Math.random() * 1000) + 1;
  makeRequest(`/api/users/${userId}`, 'get_user');

  sleep(Math.random() * 2 + 1); // 1-3 seconds

  // 4. Get projects
  makeRequest('/api/projects', 'list_projects');

  sleep(Math.random() * 5 + 5); // 5-10 seconds (user reading)
}

function makeRequest(endpoint, tag) {
  const url = `${BASE_URL}${endpoint}`;

  const params = {
    headers: {
      'Content-Type': 'application/json',
      'User-Agent': 'k6-concurrent-test',
    },
    tags: {
      endpoint: tag,
    },
    timeout: '10s',
  };

  totalRequests.add(1);

  const startTime = Date.now();
  const response = http.get(url, params);
  const duration = Date.now() - startTime;

  responseTime.add(duration);

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 2s': (r) => r.timings.duration < 2000,
  });

  if (!success) {
    failedRequests.add(1);
  }
}

export function handleSummary(data) {
  const summary = {
    test_type: 'concurrent_users',
    duration_seconds: data.state.testRunDurationMs / 1000,
    max_vus: data.metrics.vus_max.values.max,
    total_requests: data.metrics.total_requests ? data.metrics.total_requests.values.count : 0,
    failed_requests: data.metrics.failed_requests ? data.metrics.failed_requests.values.count : 0,
    success_rate: data.metrics.http_req_failed ?
      ((1 - data.metrics.http_req_failed.values.rate) * 100).toFixed(2) + '%' : '100%',
    avg_response_time_ms: data.metrics.http_req_duration.values.avg.toFixed(2),
    p50_response_time_ms: data.metrics.http_req_duration.values['p(50)'].toFixed(2),
    p95_response_time_ms: data.metrics.http_req_duration.values['p(95)'].toFixed(2),
    p99_response_time_ms: data.metrics.http_req_duration.values['p(99)'].toFixed(2),
    max_response_time_ms: data.metrics.http_req_duration.values.max.toFixed(2),
    requests_per_second: data.metrics.http_reqs.values.rate.toFixed(2),
  };

  console.log('\n=== Concurrent Users Test Summary ===');
  console.log(`Duration: ${summary.duration_seconds}s`);
  console.log(`Max Concurrent Users: ${summary.max_vus}`);
  console.log(`Total Requests: ${summary.total_requests}`);
  console.log(`Failed Requests: ${summary.failed_requests}`);
  console.log(`Success Rate: ${summary.success_rate}`);
  console.log(`Requests/sec: ${summary.requests_per_second}`);
  console.log(`Avg Response Time: ${summary.avg_response_time_ms}ms`);
  console.log(`P50 Response Time: ${summary.p50_response_time_ms}ms`);
  console.log(`P95 Response Time: ${summary.p95_response_time_ms}ms`);
  console.log(`P99 Response Time: ${summary.p99_response_time_ms}ms`);
  console.log(`Max Response Time: ${summary.max_response_time_ms}ms`);
  console.log('=====================================\n');

  return {
    'concurrent_users_summary.json': JSON.stringify(summary, null, 2),
  };
}
