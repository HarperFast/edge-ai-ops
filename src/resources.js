/**
 * Harper Edge AI - Product Personalization using Universal Sentence Encoder
 */

/* global tables, Resource, server, logger */

import { PersonalizationEngine } from './PersonalizationEngine.js';
import { v4 as uuidv4 } from 'uuid';
import {
	InferenceEngine,
	MonitoringBackend,
	BenchmarkEngine
} from './core/index.js';
import { globals } from './globals.js';
import { ModelFetchWorker } from './core/ModelFetchWorker.js';
import { LocalFilesystemAdapter } from './core/fetchers/LocalFilesystemAdapter.js';
import { HttpUrlAdapter } from './core/fetchers/HttpUrlAdapter.js';
import { HuggingFaceAdapter } from './core/fetchers/HuggingFaceAdapter.js';
import { verifyModelFetchAuth } from './core/utils/auth.js';

// Initialize personalization engine (shared across requests)
const personalizationEngineCache = new Map();

async function getPersonalizationEngine(modelName, modelVersion) {
	const cacheKey = `${modelName}:${modelVersion}`;

	if (!personalizationEngineCache.has(cacheKey)) {
		const engine = new PersonalizationEngine({
			inferenceEngine,
			modelName,
			modelVersion
		});
		await engine.initialize();
		personalizationEngineCache.set(cacheKey, engine);
	}

	return personalizationEngineCache.get(cacheKey);
}

// Shared instances
let monitoringBackend;
let inferenceEngine;
let benchmarkEngine;
let modelFetchWorker;

async function ensureInitialized() {
	if (!inferenceEngine) {
		inferenceEngine = new InferenceEngine();
		await inferenceEngine.initialize();
	}
	if (!monitoringBackend) {
		monitoringBackend = new MonitoringBackend();
		await monitoringBackend.initialize();
	}
	if (!benchmarkEngine) {
		benchmarkEngine = new BenchmarkEngine(inferenceEngine);
	}
	// Initialize Model Fetch Worker (once)
	if (!modelFetchWorker && process.env.MODEL_FETCH_WORKER !== 'false') {
		try {
			modelFetchWorker = new ModelFetchWorker();
			await modelFetchWorker.start();
			globals.set('modelFetchWorker', modelFetchWorker);
			if (typeof logger !== 'undefined') {
				logger.info('[ensureInitialized] ModelFetchWorker started');
			}
		} catch (error) {
			if (typeof logger !== 'undefined') {
				logger.error('[ensureInitialized] Failed to start ModelFetchWorker:', error);
			}
		}
	}
}

/**
 * Main resource for product personalization
 * Supports model selection via query parameters: ?modelName=...&modelVersion=...
 */
export class Personalize extends Resource {
	async post(data, request) {
		const requestId = uuidv4();
		const startTime = Date.now();

		try {
			// Parse query parameters for model selection
			const url = new URL(request.url);
			const modelName = url.searchParams.get('modelName');
			const modelVersion = url.searchParams.get('modelVersion');

			if (!modelName || !modelVersion) {
				return {
					error: 'modelName and modelVersion query parameters are required',
					requestId
				};
			}

			const { products, userContext } = data;

			if (!products || !Array.isArray(products)) {
				return {
					error: 'Missing or invalid products array',
					requestId
				};
			}

			// Get AI engine with model selection
			const engine = await getPersonalizationEngine(modelName, modelVersion);

			if (!engine.isReady()) {
				return {
					error: 'AI engine not ready',
					requestId
				};
			}

			// Enhance products with personalization
			const enhancedProducts = await engine.enhanceProducts(products, userContext || {});

			// Sort by personalized score
			const sortedProducts = enhancedProducts.sort((a, b) => (b.personalizedScore || 0) - (a.personalizedScore || 0));

			return {
				requestId,
				products: sortedProducts,
				personalized: true,
				model: `${modelName}:${modelVersion}`,
				responseTime: Date.now() - startTime
			};
		} catch (error) {
			logger.error('Personalization failed:', error);
			return {
				error: error.message,
				requestId
			};
		}
	}
}

/**
 * Health check resource
 */
export class Status extends Resource {
	async get() {
		return {
			status: 'healthy',
			uptime: process.uptime(),
			memory: process.memoryUsage(),
			components: {
				inferenceEngine: 'ready',
				monitoringBackend: 'ready',
				benchmarkEngine: 'ready'
			}
		};
	}
}

/**
 * Predict resource - POST /predict
 * Run inference with a loaded model
 */
export class Predict extends Resource {
	async post(data) {
		try {
			await ensureInitialized();

			const { modelName, modelVersion = 'v1', features, userId, sessionId } = data;

			// Validation
			if (!modelName || !features) {
				return {
					error: 'modelName and features required'
				};
			}

			// Fetch model from table
			const id = `${modelName}:${modelVersion}`;

			// Check if Model table is available
			if (!tables.Model) {
				return {
					error: 'Model table not available. Check schema configuration.'
				};
			}

			const model = await tables.Model.get(id);

			if (!model) {
				return {
					error: `Model ${id} not found`
				};
			}

			// Run inference
			const result = await inferenceEngine.predict(modelName, features, modelVersion, model);

			// Record to monitoring
			const inferenceId = await monitoringBackend.recordInference({
				modelName,
				modelVersion: result.modelVersion,
				framework: result.framework,
				requestId: `req-${Date.now()}`,
				userId: userId || null,
				sessionId: sessionId || null,
				featuresIn: JSON.stringify(features),
				prediction: JSON.stringify(result.output),
				confidence: result.confidence || null,
				latencyMs: result.latencyMs
			});

			return {
				inferenceId,
				prediction: result.output,
				confidence: result.confidence,
				modelVersion: result.modelVersion,
				latencyMs: result.latencyMs
			};
		} catch (error) {
			logger.error('Prediction failed:', error);
			return {
				error: error.message
			};
		}
	}
}

/**
 * Monitoring resource - GET /monitoring/metrics
 * Compute aggregate metrics (use GET /InferenceEvent for raw events)
 */
export class Monitoring extends Resource {
	async get(data, request) {
		try {
			await ensureInitialized();

			if (!request || !request.url) {
				return {
					error: 'Invalid request'
				};
			}

			const url = new URL(request.url);
			const modelName = url.searchParams.get('modelName');

			if (!modelName) {
				return {
					error: 'modelName parameter required'
				};
			}

			// Time range
			let startTime = url.searchParams.get('startTime');
			let endTime = url.searchParams.get('endTime');

			if (startTime) {
				startTime = new Date(parseInt(startTime));
			}
			if (endTime) {
				endTime = new Date(parseInt(endTime));
			}

			const metrics = await monitoringBackend.getMetrics(modelName, {
				startTime,
				endTime
			});

			return {
				modelName,
				...metrics
			};
		} catch (error) {
			logger.error('Get metrics failed:', error);
			return {
				error: error.message
			};
		}
	}
}

/**
 * Benchmark resource
 * POST /benchmark/compare - Compare performance of equivalent models
 * GET /benchmark/history - Get historical benchmark results
 */
export class Benchmark extends Resource {
	async post(data) {
		try {
			await ensureInitialized();

			const {
				taskType,
				equivalenceGroup,
				testData,
				iterations = 10,
				runBy,
				notes
			} = data;

			// Validation
			if (!taskType || !equivalenceGroup) {
				return {
					error: 'taskType and equivalenceGroup are required'
				};
			}

			if (!testData || !Array.isArray(testData) || testData.length === 0) {
				return {
					error: 'testData must be a non-empty array'
				};
			}

			// Find equivalent models
			const models = await benchmarkEngine.findEquivalentModels(
				taskType,
				equivalenceGroup
			);

			if (models.length < 2) {
				return {
					error: `Not enough models found. Found ${models.length} models with taskType="${taskType}" and equivalenceGroup="${equivalenceGroup}". At least 2 models are required.`
				};
			}

			// Run benchmark
			const result = await benchmarkEngine.compareBenchmark(
				models,
				testData,
				{
					iterations,
					taskType,
					equivalenceGroup,
					runBy: runBy || 'api',
					notes: notes || ''
				}
			);

			return result;
		} catch (error) {
			logger.error('Benchmark comparison failed:', error);
			return {
				error: error.message
			};
		}
	}

	async get(data, request) {
		try {
			await ensureInitialized();

			const url = new URL(request.url);
			const taskType = url.searchParams.get('taskType');
			const equivalenceGroup = url.searchParams.get('equivalenceGroup');

			const filters = {};
			if (taskType) filters.taskType = taskType;
			if (equivalenceGroup) filters.equivalenceGroup = equivalenceGroup;

			const history = await benchmarkEngine.getHistoricalResults(filters);

			return {
				count: history.length,
				results: history
			};
		} catch (error) {
			logger.error('Get benchmark history failed:', error);
			return {
				error: error.message
			};
		}
	}
}

/**
 * Upload Model Blob Resource
 *
 * Uses Harper's native tables API to store large model blobs with proper file-backed storage.
 * This avoids the REST API limitation where blobs are stored as indexed JSON objects.
 *
 * Usage:
 *   PUT /UploadModelBlob?modelName={name}&modelVersion={version}&framework={framework}&stage={stage}&metadata={json}
 *   Headers:
 *     Content-Type: application/octet-stream
 *   Body: binary blob data
 *
 * Query Parameters:
 *   - modelName (required): Model name
 *   - modelVersion (optional): Model version (default: v1)
 *   - framework (required): onnx|tensorflow|ollama
 *   - stage (optional): development|staging|production (default: development)
 *   - metadata (optional): URL-encoded JSON string with taskType, equivalenceGroup, etc.
 */
export class UploadModelBlob extends Resource {
	async put(data, request) {
		try {
			// Parse query parameters for metadata
			const searchParams = new URLSearchParams(request.search || '');
			const modelName = searchParams.get('modelName');
			const modelVersion = searchParams.get('modelVersion') || 'v1';
			const framework = searchParams.get('framework');
			const stage = searchParams.get('stage') || 'development';
			const metadata = searchParams.get('metadata') || '{}';

			if (!modelName || !framework) {
				return {
					success: false,
					error: 'Missing required query parameters: modelName, framework'
				};
			}

			// Binary blob data is in the data parameter as a Buffer
			const blobBuffer = data;
			const id = `${modelName}:${modelVersion}`;

			// Use Harper's native tables API - triggers file-backed blob storage for large files
			await tables.Model.put({
				id,
				modelName,
				modelVersion,
				framework,
				stage,
				metadata,
				modelBlob: blobBuffer,
				blobSize: blobBuffer.length,
			});

			return {
				success: true,
				id,
				size: blobBuffer.length
			};
		} catch (error) {
			logger.error('UploadModelBlob failed:', error);
			return {
				success: false,
				error: error.message
			};
		}
	}
}

/**
 * ModelList Resource
 *
 * GET /ModelList?stage=...&framework=...
 *
 * List models from the Model table
 */
export class ModelList extends Resource {
	async get(data, request) {
		try {
			// Check authentication
			const authError = verifyModelFetchAuth(data);
			if (authError) {
				return authError;
			}

			await ensureInitialized();

			// Parse query parameters
			const searchParams = new URLSearchParams(data?.search || '');
			const stage = searchParams.get('stage');
			const framework = searchParams.get('framework');

			// Query Model table
			const models = [];
			for await (const model of tables.Model.search()) {
				// Apply filters
				if (stage && model.stage !== stage) continue;
				if (framework && model.framework !== framework) continue;

				// Don't return the full blob in list view
				models.push({
					id: model.id,
					modelName: model.modelName,
					modelVersion: model.modelVersion,
					framework: model.framework,
					stage: model.stage,
					blobSize: model.blobSize || 0,
					uploadedAt: model.uploadedAt,
					metadata: model.metadata
				});
			}

			return models;
		} catch (error) {
			logger.error('[ModelList] Error:', error);
			return {
				error: error.message,
				code: error.code || 'LIST_FAILED'
			};
		}
	}
}

/**
 * InspectModel Resource
 *
 * GET /InspectModel?source={source}&sourceReference={reference}&variant={variant}
 *
 * Inspect a model at a source without downloading it.
 * Returns framework, available variants, and inferred metadata.
 *
 * Query Parameters:
 *   - source (required): "filesystem" | "url" | "huggingface"
 *   - sourceReference (required): file path, URL, or HuggingFace model ID
 *   - variant (optional): variant name (for HuggingFace: "default" | "quantized")
 */
export class InspectModel extends Resource {
	async get(data, request) {
		try {
			// Check authentication using query parameter
			const authError = verifyModelFetchAuth(data);
			if (authError) {
				return authError;
			}

			await ensureInitialized();

			// Parse query parameters from data.search
			const searchParams = new URLSearchParams(data?.search || '');
			const source = searchParams.get('source');
			const sourceReference = searchParams.get('sourceReference');
			const variant = searchParams.get('variant');

			// Validation
			if (!source || !sourceReference) {
				return {
					error: 'Missing required query parameters: source, sourceReference'
				};
			}

			// Get adapter
			logger.info('[InspectModel] Creating adapters');
			const adapters = {
				filesystem: new LocalFilesystemAdapter(),
				url: new HttpUrlAdapter(),
				huggingface: new HuggingFaceAdapter()
			};

			const adapter = adapters[source];
			if (!adapter) {
				return {
					error: `Unsupported source: ${source}. Supported: filesystem, url, huggingface`
				};
			}

			// Detect framework
			let framework;
			try {
				logger.info('[InspectModel] Calling detectFramework');
				framework = await adapter.detectFramework(sourceReference, variant);
				logger.info('[InspectModel] Framework detected:', framework);
			} catch (error) {
				logger.error('[InspectModel] detectFramework failed:', error);
				return {
					error: `Failed to detect framework: ${error.message}`,
					code: error.code || 'DETECTION_FAILED'
				};
			}

			// List variants
			let variants;
			try {
				logger.info('[InspectModel] Calling listVariants');
				variants = await adapter.listVariants(sourceReference);
				logger.info('[InspectModel] Variants found:', variants.length);
			} catch (error) {
				logger.error('[InspectModel] listVariants failed:', error);
				return {
					error: `Failed to list variants: ${error.message}`,
					code: error.code || 'LIST_VARIANTS_FAILED'
				};
			}

			// Infer metadata
			let inferredMetadata;
			try {
				inferredMetadata = await adapter.inferMetadata(sourceReference, variant);
			} catch (error) {
				logger.warn('[InspectModel] Failed to infer metadata:', error.message);
				inferredMetadata = {};
			}

			// Suggest model name from source reference
			let suggestedModelName = sourceReference.split('/').pop().replace(/\.[^.]+$/, '');
			if (source === 'huggingface') {
				// For HuggingFace, use the repo name
				const parts = sourceReference.split('/');
				suggestedModelName = parts[parts.length - 1];
			}

			return {
				source,
				sourceReference,
				framework,
				variants,
				inferredMetadata,
				suggestedModelName
			};
		} catch (error) {
			logger.error('[InspectModel] Error:', error);
			return {
				error: error.message,
				code: error.code || 'INSPECT_FAILED'
			};
		}
	}
}

/**
 * FetchModel Resource
 *
 * POST /FetchModel
 *
 * Create a job to fetch a model from a source and store it in the Model table.
 * Returns jobId for tracking progress.
 *
 * Request Body:
 *   {
 *     source: "filesystem" | "url" | "huggingface",
 *     sourceReference: "path/to/model.onnx" | "https://..." | "Xenova/all-MiniLM-L6-v2",
 *     variant: "default" | "quantized" (optional, for HuggingFace),
 *     modelName: "my-model" (required),
 *     modelVersion: "v1" (optional, default: "v1"),
 *     framework: "onnx" | "tensorflow" | "transformers" (optional, auto-detected if omitted),
 *     stage: "development" | "staging" | "production" (optional, default: "development"),
 *     metadata: { taskType, equivalenceGroup, ... } (optional, merged with inferred metadata),
 *     webhookUrl: "https://..." (optional, called on completion/failure),
 *     maxRetries: 3 (optional, default: 3)
 *   }
 */

export class FetchModel extends Resource {
	async post(data, request) {
		try {
			// Check authentication
			const authError = verifyModelFetchAuth(data);
			if (authError) {
				return authError;
			}

			await ensureInitialized();

			const {
				source,
				sourceReference,
				variant = null,
				modelName,
				modelVersion = 'v1',
				framework,
				stage = 'development',
				metadata = {},
				webhookUrl = null,
				maxRetries = 3
			} = data;

			// Validation
			if (!source || !sourceReference || !modelName) {
				return {
					error: 'Missing required fields: source, sourceReference, modelName'
				};
			}

			const supportedSources = ['filesystem', 'url', 'huggingface'];
			if (!supportedSources.includes(source)) {
				return {
					error: `Unsupported source: ${source}. Supported: ${supportedSources.join(', ')}`
				};
			}

			const modelId = `${modelName}:${modelVersion}`;

			// Check if model already exists
			const existingModel = await tables.Model.get(modelId);
			if (existingModel) {
				// Check if it's the same source (idempotent) or different source (error)
				const existingMetadata = JSON.parse(existingModel.metadata || '{}');
				const existingSource = existingMetadata.fetchSource;
				const existingReference = existingMetadata.fetchReference;

				if (existingSource === source && existingReference === sourceReference) {
					// Same source, return success (idempotent)
					return {
						message: 'Model already exists with same source',
						modelId,
						existing: true
					};
				} else {
					// Different source, error
					return {
						error: `Model ${modelId} already exists from a different source (${existingSource}:${existingReference}). Delete it first or use a different modelName/modelVersion.`
					};
				}
			}

			// TODO: Fix duplicate check - filter syntax not working correctly
			// Temporarily disabled to test job processing
			// const activeJobs = [];
			// for await (const job of tables.ModelFetchJob.search({
			// 	filter: ['modelName', '=', modelName, 'and', 'modelVersion', '=', modelVersion, 'and', 'status', '=', 'queued']
			// })) {
			// 	activeJobs.push(job);
			// }
			// if (activeJobs.length > 0) {
			// 	return {
			// 		error: `A job is already queued for model ${modelId}`,
			// 		existingJobId: activeJobs[0].id
			// 	};
			// }

			// Detect framework if not provided
			let detectedFramework = framework;
			if (!detectedFramework) {
				const adapters = {
					filesystem: new LocalFilesystemAdapter(),
					url: new HttpUrlAdapter(),
					huggingface: new HuggingFaceAdapter()
				};

				const adapter = adapters[source];
				try {
					detectedFramework = await adapter.detectFramework(sourceReference, variant);
				} catch (error) {
					return {
						error: `Failed to detect framework: ${error.message}. Please specify framework explicitly.`,
						code: error.code || 'DETECTION_FAILED'
					};
				}
			}

			// Validate framework
			const supportedFrameworks = ['onnx', 'tensorflow', 'transformers', 'ollama'];
			if (!supportedFrameworks.includes(detectedFramework)) {
				return {
					error: `Unsupported framework: ${detectedFramework}. Supported: ${supportedFrameworks.join(', ')}`
				};
			}

			// Infer metadata (best effort, failures are ignored)
			let inferredMetadata = {};
			try {
				const adapters = {
					filesystem: new LocalFilesystemAdapter(),
					url: new HttpUrlAdapter(),
					huggingface: new HuggingFaceAdapter()
				};
				const adapter = adapters[source];
				inferredMetadata = await adapter.inferMetadata(sourceReference, variant);
			} catch (error) {
				logger.warn('[FetchModel] Failed to infer metadata:', error.message);
			}

			// Create job
			const jobId = uuidv4();
			const job = {
				id: jobId,
				jobId, // Indexed field for queries
				source,
				sourceReference,
				variant,
				modelName,
				modelVersion,
				framework: detectedFramework,
				stage,
				status: 'queued',
				progress: 0,
				downloadedBytes: 0,
				totalBytes: 0,
				retryCount: 0,
				maxRetries,
				lastError: null,
				errorCode: null,
				retryable: true,
				inferredMetadata: JSON.stringify(inferredMetadata),
				userMetadata: JSON.stringify(metadata),
				webhookUrl,
				createdAt: Date.now(),
				startedAt: null,
				completedAt: null,
				resultModelId: null
			};

			await tables.ModelFetchJob.create(job);

			logger.info(`[FetchModel] Created job ${jobId} for model ${modelId} (${source}:${sourceReference})`);

			// Trigger on-demand processing
			if (modelFetchWorker) {
				modelFetchWorker.triggerProcessing().catch((error) => {
					logger.error('[FetchModel] Error triggering worker:', error);
				});
			}

			return {
				jobId,
				status: 'queued',
				message: 'Job created successfully. Worker will process it shortly. Use GET /ModelFetchJob?id={jobId} to track progress.',
				modelId
			};
		} catch (error) {
			logger.error('[FetchModel] Error:', error);
			return {
				error: error.message,
				code: error.code || 'FETCH_FAILED'
			};
		}
	}
}

/**
 * ModelFetchJobs Resource
 *
 * GET /ModelFetchJobs?id={jobId} - Get job status by ID
 * GET /ModelFetchJobs?status={status} - List jobs by status
 * GET /ModelFetchJobs?modelName={name} - List jobs by model name
 * POST /ModelFetchJobs - Retry a failed job
 */
export class ModelFetchJobs extends Resource {
	async get(data, request) {
		try {
			// Check authentication
			const authError = verifyModelFetchAuth(data);
			if (authError) {
				return authError;
			}

			await ensureInitialized();

			// Parse query parameters
			const searchParams = new URLSearchParams(data.search || '');
			const jobId = searchParams.get('id');
			const status = searchParams.get('status');
			const modelName = searchParams.get('modelName');
			const limit = parseInt(searchParams.get('limit') || '50');

			// Get single job by ID
			if (jobId) {
				const job = await tables.ModelFetchJob.get(jobId);
				if (!job) {
					return {
						error: `Job ${jobId} not found`
					};
				}
				return job;
			}

			// List jobs with filters
			const filter = [];
			if (status && modelName) {
				filter.push('status', '=', status, 'and', 'modelName', '=', modelName);
			} else if (status) {
				filter.push('status', '=', status);
			} else if (modelName) {
				filter.push('modelName', '=', modelName);
			}

			const jobs = [];
			const searchOptions = filter.length > 0 ? { filter } : {};
			for await (const job of tables.ModelFetchJob.search(searchOptions)) {
				jobs.push(job);
				if (jobs.length >= limit) break;
			}

			// Sort by createdAt desc
			jobs.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));

			return {
				jobs,
				count: jobs.length
			};
		} catch (error) {
			logger.error('[ModelFetchJob] GET Error:', error);
			return {
				error: error.message
			};
		}
	}

	async post(data, request) {
		try {
			// Check authentication
			const authError = verifyModelFetchAuth(data);
			if (authError) {
				return authError;
			}

			await ensureInitialized();

			const { jobId, action = 'retry' } = data;

			// Validation
			if (!jobId) {
				return {
					error: 'Missing required field: jobId'
				};
			}

			// Get job
			const job = await tables.ModelFetchJob.get(jobId);
			if (!job) {
				return {
					error: `Job ${jobId} not found`
				};
			}

			// Handle actions
			if (action === 'retry') {
				// Only retry failed jobs
				if (job.status !== 'failed') {
					return {
						error: `Job ${jobId} is not in failed state (current status: ${job.status})`
					};
				}

				// Reset job to queued (v5: use put with spread to avoid frozen-record mutation)
				// Coerce date strings to integer timestamps (Harper v5 may return ISO-8601 strings
				// from get(); Date fields require integers for FIFO sort correctness)
				const retryJobData = {
					...job,
					status: 'queued',
					retryCount: 0,
					lastError: null,
					errorCode: null
				};
				if (typeof retryJobData.createdAt === 'string') {
					retryJobData.createdAt = new Date(retryJobData.createdAt).getTime();
				}
				if (typeof retryJobData.startedAt === 'string') {
					retryJobData.startedAt = new Date(retryJobData.startedAt).getTime();
				}
				if (typeof retryJobData.completedAt === 'string') {
					retryJobData.completedAt = new Date(retryJobData.completedAt).getTime();
				}
				await tables.ModelFetchJob.put(retryJobData);

				return {
					jobId,
					status: 'queued',
					message: 'Job reset to queued for retry'
				};
			}

			return {
				error: `Unknown action: ${action}. Supported: retry`
			};
		} catch (error) {
			logger.error('[ModelFetchJob] POST Error:', error);
			return {
				error: error.message
			};
		}
	}
}

/**
 * WorkerControl Resource
 *
 * GET /WorkerControl - Get worker status
 * POST /WorkerControl - Start/restart worker manually
 */
export class WorkerControl extends Resource {
	async get(data, request) {
		try {
			// Check authentication
			const authError = verifyModelFetchAuth(data);
			if (authError) {
				return authError;
			}

			await ensureInitialized();

			const worker = globals.get('modelFetchWorker');

			if (!worker) {
				return {
					running: false,
					message: 'Worker not initialized (MODEL_FETCH_WORKER=false or initialization failed)'
				};
			}

			const status = worker.getStatus();

			return {
				running: status.running,
				activeJobs: status.activeJobs,
				maxConcurrent: status.maxConcurrent,
				pollInterval: status.pollInterval,
				rateLimitedSources: status.rateLimitedSources
			};
		} catch (error) {
			logger.error('[WorkerControl] GET Error:', error);
			return {
				error: error.message
			};
		}
	}

	async post(data, request) {
		try {
			// Check authentication
			const authError = verifyModelFetchAuth(data);
			if (authError) {
				return authError;
			}

			await ensureInitialized();

			const worker = globals.get('modelFetchWorker');

			if (!worker) {
				return {
					error: 'Worker not available (MODEL_FETCH_WORKER=false or initialization failed)'
				};
			}

			const { action = 'start' } = data;

			if (action === 'start') {
				if (worker.running) {
					return {
						message: 'Worker is already running',
						status: worker.getStatus()
					};
				}

				await worker.start();
				logger.info('[WorkerControl] Worker started manually');

				return {
					message: 'Worker started successfully',
					status: worker.getStatus()
				};
			} else if (action === 'stop') {
				if (!worker.running) {
					return {
						message: 'Worker is already stopped',
						status: worker.getStatus()
					};
				}

				await worker.stop();
				logger.info('[WorkerControl] Worker stopped manually');

				return {
					message: 'Worker stopped successfully',
					status: worker.getStatus()
				};
			} else {
				return {
					error: `Unknown action: ${action}. Supported: start, stop`
				};
			}
		} catch (error) {
			logger.error('[WorkerControl] POST Error:', error);
			return {
				error: error.message
			};
		}
	}
}

