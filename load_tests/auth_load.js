// pkgs/aq_security/load_tests/auth_load.js
//
// Auth load test - test authentication system under load
//
// Run: k6 run auth_load.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// Custom metrics
const loginAttempts = new Counter('login_attempts');
const loginSuccesses = new Counter('login_successes');
const loginFailures = new Counter('login_failures');
const tokenValidations = new Counter('token_validations');
const loginDuration = new Trend('login_duration');

// Test configuration
export const options = {
  scenarios: {
    // Scenario 1: Normal login/logout cycles
    normal_auth: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 50 },   // Ramp to 50 users
        { duration: '3m', target: 50 },   // Stay at 50 users
        { duration: '1m', target: 100 },  // Ramp to 100 users
        { duration: '3m', target: 100 },  // Stay at 100 users
        { duration: '1m', target: 0 },    // Ramp down
      ],
      exec: 'normalAuth',
    },
    // Scenario 2: Failed login attempts (brute force simulation)
    failed_logins: {
      executor: 'constant-arrival-rate',
      rate: 10,
      timeUnit: '1s',
      duration: '2m',
      preAllocatedVUs: 10,
      maxVUs: 20,
      exec: 'failedLogins',
      startTime: '9m',
    },
  },
  thresholds: {
    'login_duration': ['p(95)<500', 'p(99)<1000'], // Login should be fast
    'http_req_duration{endpoint:validate}': ['p(95)<100'], // Token validation should be very fast
    'login_successes': ['count>100'], // Should have successful logins
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Normal authentication flow
export function normalAuth() {
  // 1. Login
  const loginResult = login('user@example.com', 'password123');

  if (!loginResult.success) {
    return;
  }

  const token = loginResult.token;

  sleep(Math.random() * 2 + 1); // 1-3 seconds

  // 2. Make authenticated requests
  for (let i = 0; i < 5; i++) {
    makeAuthenticatedRequest(token, '/api/users');
    sleep(Math.random() * 3 + 2); // 2-5 seconds
  }

  // 3. Validate token
  validateToken(token);

  sleep(Math.random() * 2 + 1); // 1-3 seconds

  // 4. Logout
  logout(token);

  sleep(Math.random() * 5 + 5); // 5-10 seconds before next cycle
}

// Failed login attempts
export function failedLogins() {
  const username = `attacker${Math.floor(Math.random() * 10)}@example.com`;
  const password = `wrong_password_${Math.random()}`;

  login(username, password);

  // No sleep - attempt as fast as possible
}

function login(username, password) {
  const url = `${BASE_URL}/api/auth/login`;

  const payload = JSON.stringify({
    username: username,
    password: password,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: {
      endpoint: 'login',
    },
  };

  loginAttempts.add(1);

  const startTime = Date.now();
  const response = http.post(url, payload, params);
  const duration = Date.now() - startTime;

  loginDuration.add(duration);

  const success = check(response, {
    'login status is 200': (r) => r.status === 200,
    'has access token': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.access_token !== undefined;
      } catch (e) {
        return false;
      }
    },
  });

  if (success) {
    loginSuccesses.add(1);
    const body = JSON.parse(response.body);
    return {
      success: true,
      token: body.access_token,
    };
  } else {
    loginFailures.add(1);
    return {
      success: false,
    };
  }
}

function makeAuthenticatedRequest(token, endpoint) {
  const url = `${BASE_URL}${endpoint}`;

  const params = {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    tags: {
      endpoint: 'authenticated',
    },
  };

  const response = http.get(url, params);

  check(response, {
    'authenticated request status is 200': (r) => r.status === 200,
  });
}

function validateToken(token) {
  const url = `${BASE_URL}/api/auth/validate`;

  const params = {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
    tags: {
      endpoint: 'validate',
    },
  };

  tokenValidations.add(1);

  const response = http.get(url, params);

  check(response, {
    'token validation status is 200': (r) => r.status === 200,
  });
}

function logout(token) {
  const url = `${BASE_URL}/api/auth/logout`;

  const params = {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
    tags: {
      endpoint: 'logout',
    },
  };

  const response = http.post(url, null, params);

  check(response, {
    'logout status is 200': (r) => r.status === 200,
  });
}

export function handleSummary(data) {
  const summary = {
    test_type: 'auth_load',
    duration_seconds: data.state.testRunDurationMs / 1000,
    login_attempts: data.metrics.login_attempts ? data.metrics.login_attempts.values.count : 0,
    login_successes: data.metrics.login_successes ? data.metrics.login_successes.values.count : 0,
    login_failures: data.metrics.login_failures ? data.metrics.login_failures.values.count : 0,
    token_validations: data.metrics.token_validations ? data.metrics.token_validations.values.count : 0,
    success_rate: data.metrics.login_attempts && data.metrics.login_successes ?
      ((data.metrics.login_successes.values.count / data.metrics.login_attempts.values.count) * 100).toFixed(2) + '%' : '0%',
    avg_login_duration_ms: data.metrics.login_duration ? data.metrics.login_duration.values.avg.toFixed(2) : 0,
    p95_login_duration_ms: data.metrics.login_duration ? data.metrics.login_duration.values['p(95)'].toFixed(2) : 0,
    p99_login_duration_ms: data.metrics.login_duration ? data.metrics.login_duration.values['p(99)'].toFixed(2) : 0,
  };

  console.log('\n=== Auth Load Test Summary ===');
  console.log(`Duration: ${summary.duration_seconds}s`);
  console.log(`Login Attempts: ${summary.login_attempts}`);
  console.log(`Login Successes: ${summary.login_successes}`);
  console.log(`Login Failures: ${summary.login_failures}`);
  console.log(`Token Validations: ${summary.token_validations}`);
  console.log(`Success Rate: ${summary.success_rate}`);
  console.log(`Avg Login Duration: ${summary.avg_login_duration_ms}ms`);
  console.log(`P95 Login Duration: ${summary.p95_login_duration_ms}ms`);
  console.log(`P99 Login Duration: ${summary.p99_login_duration_ms}ms`);
  console.log('==============================\n');

  return {
    'auth_load_summary.json': JSON.stringify(summary, null, 2),
  };
}
