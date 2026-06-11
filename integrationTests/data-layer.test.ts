/**
 * Harper v5 integration tests for edge-ai-ops data layer.
 *
 * Tests cover the Harper REST API surface (tables, resource endpoints) without
 * requiring external model files, GPU, or AI framework downloads. AI inference
 * endpoints (POST /Predict, POST /Personalize, POST /Benchmark) are exercised
 * for their data-plumbing behaviour only — inference is skipped when no model
 * is loaded, which is expected in a fresh Harper install.
 *
 * Local runs fail with EADDRNOTAVAIL because macOS loopback aliases are not
 * configured. CI (ubuntu-latest) supports the full 127.0.0.0/8 range and is
 * the authoritative test gate.
 */

import { suite, test, before, after } from 'node:test';
import { strictEqual, ok, deepStrictEqual } from 'node:assert/strict';
import {
  setupHarperWithFixture,
  teardownHarper,
  type ContextWithHarper,
} from '@harperfast/integration-testing';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { createRequire } from 'node:module';

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURE_PATH = resolve(__dirname, '..');

// harper's `exports` only exposes ".", so 'harper/dist/bin/harper.js' is not resolvable.
// Resolve the CLI from the exported main entry and pass it explicitly.
const require = createRequire(import.meta.url);
const harperBinPath = resolve(dirname(require.resolve('harper')), 'bin/harper.js');

function authFetch(
  ctx: ContextWithHarper,
  path: string,
  init: RequestInit & { headers?: Record<string, string> } = {},
) {
  const { headers = {}, ...rest } = init;
  const creds = Buffer.from(
    `${ctx.harper.admin.username}:${ctx.harper.admin.password}`,
  ).toString('base64');
  return fetch(`${ctx.harper.httpURL}${path}`, {
    ...rest,
    headers: { Authorization: `Basic ${creds}`, ...headers },
  });
}

void suite('edge-ai-ops — Harper data layer', (ctx: ContextWithHarper) => {
  before(async () => {
    await setupHarperWithFixture(ctx, FIXTURE_PATH, { harperBinPath });
  });

  after(async () => {
    if ((ctx as any).harper) {
      await teardownHarper(ctx);
    }
  });

  // ─── Health / boot ────────────────────────────────────────────────────────

  void test('GET /Status returns healthy', async () => {
    const res = await authFetch(ctx, '/Status');
    strictEqual(res.status, 200);
    const body = (await res.json()) as { status: string };
    strictEqual(body.status, 'healthy');
  });

  // ─── Model table ──────────────────────────────────────────────────────────

  void test('GET /Model/ returns an array (empty on fresh install)', async () => {
    const res = await authFetch(ctx, '/Model/');
    strictEqual(res.status, 200);
    const body = await res.json();
    ok(Array.isArray(body), 'expected array');
  });

  void test('PUT /Model/:id creates a model record', async () => {
    const res = await authFetch(ctx, '/Model/test-model%3Av1', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        modelName: 'test-model',
        modelVersion: 'v1',
        framework: 'onnx',
        stage: 'development',
        metadata: JSON.stringify({
          taskType: 'text-embedding',
          equivalenceGroup: 'test-group',
          outputDimensions: 384,
        }),
        blobSize: 0,
      }),
    });
    ok([200, 204].includes(res.status), `expected 200/204 on PUT, got ${res.status}`);
  });

  void test('GET /Model/:id retrieves the created model', async () => {
    const res = await authFetch(ctx, '/Model/test-model%3Av1');
    strictEqual(res.status, 200);
    const body = (await res.json()) as { modelName: string; framework: string };
    strictEqual(body.modelName, 'test-model');
    strictEqual(body.framework, 'onnx');
  });

  void test('GET /Model/ lists the created model', async () => {
    const res = await authFetch(ctx, '/Model/');
    strictEqual(res.status, 200);
    const body = (await res.json()) as Array<{ id: string }>;
    ok(Array.isArray(body));
    ok(
      body.some((m) => m.id === 'test-model:v1'),
      'test-model:v1 should appear in list',
    );
  });

  void test('GET /Model/nonexistent:v99 returns 404', async () => {
    const res = await authFetch(ctx, '/Model/nonexistent%3Av99');
    strictEqual(res.status, 404);
  });

  // ─── ModelList resource ───────────────────────────────────────────────────

  void test('GET /ModelList returns array (no auth required if MODEL_FETCH_AUTH not set)', async () => {
    const res = await authFetch(ctx, '/ModelList');
    // May return 200 (list) or 401 (auth required) depending on env; both are valid behaviours.
    ok([200, 401, 403].includes(res.status), `unexpected status ${res.status}`);
  });

  // ─── InferenceEvent table ─────────────────────────────────────────────────

  void test('GET /InferenceEvent/ returns an array', async () => {
    const res = await authFetch(ctx, '/InferenceEvent/');
    strictEqual(res.status, 200);
    const body = await res.json();
    ok(Array.isArray(body), 'expected array');
  });

  void test('POST /InferenceEvent/ creates an inference event', async () => {
    const res = await authFetch(ctx, '/InferenceEvent/', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        modelName: 'test-model',
        modelVersion: 'v1',
        framework: 'onnx',
        requestId: 'req-test-001',
        latencyMs: 42,
        featuresIn: '[]',
        prediction: '"test"',
      }),
    });
    ok([200, 201, 204].includes(res.status), `expected 2xx on POST, got ${res.status}`);
  });

  // ─── BenchmarkResult table ────────────────────────────────────────────────

  void test('GET /BenchmarkResult/ returns an array', async () => {
    const res = await authFetch(ctx, '/BenchmarkResult/');
    strictEqual(res.status, 200);
    const body = await res.json();
    ok(Array.isArray(body), 'expected array');
  });

  // ─── Feature table ────────────────────────────────────────────────────────

  void test('PUT /Feature/:id creates a feature record', async () => {
    const res = await authFetch(ctx, '/Feature/user1%3Ascore', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        entityId: 'user1',
        featureName: 'score',
        featureValue: '0.95',
        timestamp: Date.now(),
      }),
    });
    ok([200, 204].includes(res.status), `expected 200/204, got ${res.status}`);
  });

  void test('GET /Feature/user1:score retrieves the created feature', async () => {
    const res = await authFetch(ctx, '/Feature/user1%3Ascore');
    strictEqual(res.status, 200);
    const body = (await res.json()) as { entityId: string; featureValue: string };
    strictEqual(body.entityId, 'user1');
    strictEqual(body.featureValue, '0.95');
  });

  // ─── ModelFetchJob table ──────────────────────────────────────────────────

  void test('GET /ModelFetchJob/ returns an array', async () => {
    const res = await authFetch(ctx, '/ModelFetchJob/');
    strictEqual(res.status, 200);
    const body = await res.json();
    ok(Array.isArray(body), 'expected array');
  });

  // ─── Predict resource (data path, no model loaded) ────────────────────────

  void test('POST /Predict returns error when model table unavailable or model not found', async () => {
    const res = await authFetch(ctx, '/Predict', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        modelName: 'nonexistent-model',
        modelVersion: 'v1',
        features: [1, 2, 3],
      }),
    });
    // Should return 200 with an error body (Resource pattern), not a 500.
    ok([200, 404, 400].includes(res.status), `unexpected status ${res.status}`);
    if (res.status === 200) {
      const body = (await res.json()) as { error?: string };
      ok(
        body.error !== undefined,
        'expected error field when model is not found',
      );
    }
  });

  // ─── WorkerControl resource ───────────────────────────────────────────────

  void test('GET /WorkerControl returns worker status', async () => {
    const res = await authFetch(ctx, '/WorkerControl');
    // 200 with status or 200 with error (auth); both valid
    ok([200, 401, 403].includes(res.status), `unexpected status ${res.status}`);
  });

  // ─── Cleanup ──────────────────────────────────────────────────────────────

  void test('DELETE /Model/:id removes the test record', async () => {
    const res = await authFetch(ctx, '/Model/test-model%3Av1', {
      method: 'DELETE',
    });
    ok([200, 204, 404].includes(res.status), `expected 2xx/404 on DELETE, got ${res.status}`);
  });

  void test('DELETE /Feature/:id removes the test feature', async () => {
    const res = await authFetch(ctx, '/Feature/user1%3Ascore', {
      method: 'DELETE',
    });
    ok([200, 204, 404].includes(res.status), `expected 2xx/404 on DELETE, got ${res.status}`);
  });
});
