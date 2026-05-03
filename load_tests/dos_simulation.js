// pkgs/aq_security/load_tests/dos_simulation.js
//
// DoS attack simulation - test DoS protection effectiveness
//
// Run: k6 run dos_simulation.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate } from 'k6/metrics';

// Custom metrics
const connectionAttempts = new Counter('connection_attempts');
const connectionBlocks = new Counter('connection_blocks');
const ipBlocks = new Counter('ip_blocks');
const successfulConnections = new Counter('successful_connections');

// Test configuration
export const options = {
  scenarios: {
    // Scenario 1: Connection flooding
    connection_flood: {
      executor: 'constant-vus',
      vus: 100,
      duration: '2m',
      exec: 'connectionFlood',
    },
    // Scenario 2: Slow loris attack simulation
    slow_loris: {
      executor: 'constant-vus',
      vus: 50,
      duration: '2m',
      exec: 'slowLoris',
      startTime: '2m',
    },
    // Scenario 3: Request flooding from single IP
    request_flood: {
      executor: 'constant-arrival-rate',
      rate: 500,
      timeUnit: '1s',
      duration: '1m',
      preAllocatedVUs: 50,
      maxVUs: 100,
      exec: 'requestFlood',
      startTime: '4m',
    },
  },
  thresholds: {
    'connection_blocks': ['count>0'],  // Should block some connections
    'ip_blocks': ['count>0'],          // Should block some IPs
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

// Connection flooding scenario
export function connectionFlood() {
  const url = `${BASE_URL}/api/health`;

  const params = {
    headers: {
      'X-Forwarded-For': `10.0.0.${Math.floor(Math.random() * 255)}`,
    },
    tags: {
      scenario: 'connection_flood',
    },
    timeout: '5s',
  };

  connectionAttempts.add(1);

  const response = http.get(url, params);

  if (response.status === 503 || response.status === 429) {
    connectionBlocks.add(1);
  } else if (response.status === 200) {
    successfulConnections.add(1);
  }

  // No sleep - flood as fast as possible
}

// Slow loris attack simulation
export function slowLoris() {
  const url = `${BASE_URL}/api/users`;

  const params = {
    headers: {
      'X-Forwarded-For': `172.16.0.${Math.floor(Math.random() * 255)}`,
      'Connection': 'keep-alive',
    },
    tags: {
      scenario: 'slow_loris',
    },
    timeout: '30s',
  };

  connectionAttempts.add(1);

  const response = http.get(url, params);

  if (response.status === 503 || response.status === 429) {
    connectionBlocks.add(1);
  } else if (response.status === 200) {
    successfulConnections.add(1);
  }

  // Keep connection open longer
  sleep(Math.random() * 5 + 5); // 5-10 seconds
}

// Request flooding from single IP
export function requestFlood() {
  const url = `${BASE_URL}/api/projects`;

  const params = {
    headers: {
      'X-Forwarded-For': '192.168.100.100', // Same IP for all requests
    },
    tags: {
      scenario: 'request_flood',
    },
  };

  connectionAttempts.add(1);

  const response = http.get(url, params);

  if (response.status === 403) {
    // IP blocked
    ipBlocks.add(1);
  } else if (response.status === 503 || response.status === 429) {
    connectionBlocks.add(1);
  } else if (response.status === 200) {
    successfulConnections.add(1);
  }

  // No sleep - flood as fast as possible
}

export function handleSummary(data) {
  const summary = {
    test_type: 'dos_simulation',
    duration_seconds: data.state.testRunDurationMs / 1000,
    connection_attempts: data.metrics.connection_attempts ? data.metrics.connection_attempts.values.count : 0,
    connection_blocks: data.metrics.connection_blocks ? data.metrics.connection_blocks.values.count : 0,
    ip_blocks: data.metrics.ip_blocks ? data.metrics.ip_blocks.values.count : 0,
    successful_connections: data.metrics.successful_connections ? data.metrics.successful_connections.values.count : 0,
    block_rate: data.metrics.connection_blocks && data.metrics.connection_attempts ?
      ((data.metrics.connection_blocks.values.count / data.metrics.connection_attempts.values.count) * 100).toFixed(2) + '%' : '0%',
    protection_effectiveness: data.metrics.connection_blocks && data.metrics.connection_attempts ?
      ((data.metrics.connection_blocks.values.count / data.metrics.connection_attempts.values.count) * 100).toFixed(2) + '%' : '0%',
  };

  console.log('\n=== DoS Simulation Summary ===');
  console.log(`Duration: ${summary.duration_seconds}s`);
  console.log(`Connection Attempts: ${summary.connection_attempts}`);
  console.log(`Connection Blocks: ${summary.connection_blocks}`);
  console.log(`IP Blocks: ${summary.ip_blocks}`);
  console.log(`Successful Connections: ${summary.successful_connections}`);
  console.log(`Block Rate: ${summary.block_rate}`);
  console.log(`Protection Effectiveness: ${summary.protection_effectiveness}`);
  console.log('==============================\n');

  return {
    'dos_simulation_summary.json': JSON.stringify(summary, null, 2),
  };
}
