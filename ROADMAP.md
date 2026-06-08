# Harper Edge AI - Roadmap

**Vision:** Complete MLOps lifecycle management—from deployment through monitoring, drift detection, automated retraining, and validation.

---

## Long-Term Vision

Harper Edge AI aims to become a complete AI operations platform, providing:

- **Production Monitoring** - Real-time metrics, drift detection, alerting, and automated retraining triggers
- **Training Orchestration** - Experiment tracking, model validation, and lifecycle management
- **Feature Store** - Centralized feature management with time-travel queries
- **Deployment Orchestration** - CI/CD pipelines, canary releases, and A/B testing

### Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Production Inferencing                    │
│              (Edge Devices, APIs, Services)                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ Inference Events, Metrics, Feedback
                     ↓
┌─────────────────────────────────────────────────────────────┐
│                Harper AI Ops Cluster                        │
│                                                             │
│  ┌────────────────────┐  ┌────────────────────────────────┐ │
│  │  Monitoring &      │  │  Training & Validation         │ │
│  │  Observability     │  │                                │ │
│  │  ✅ Metrics        │  │  ✅ Model Training             │ │
│  │  ✅ Drift Detect   │  │  ✅ Experiment Tracking        │ │
│  │  ✅ Alerting       │  │  ✅ Validation & Promotion     │ │
│  │  ✅ Auto Triggers  │  │  ✅ Model Registry             │ │
│  └────────────────────┘  └────────────────────────────────┘ │
│                                                             │
│  ┌────────────────────┐  ┌────────────────────────────────┐ │
│  │  Core Data &       │  │  Deployment & Orchestration    │ │
│  │  Services          │  │                                │ │
│  │  🔄 Feature Store  │  │  🔄 Model CI/CD                │ │
│  │  🔄 Data Pipeline  │  │  🔄 Automated Deploy           │ │
│  │  🔄 Feature Eng.   │  │  🔄 Canary Releases            │ │
│  └────────────────────┘  └────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                     ↓                        ↑
            ┌────────────────┐      ┌────────────────┐
            │  BigQuery      │      │  Public Model  │
            │  Data Warehouse│      │  Repositories  │
            └────────────────┘      └────────────────┘
```

**Legend:** ✅ Designed | 🔄 Planned

---

## Current Implementation Status

### ✅ Phase 0: Foundation (COMPLETE)

**Status:** Operational and production-ready

**What's Implemented:**

- Multi-backend inference (ONNX, TensorFlow.js, Transformers.js, Ollama)
- Model fetch system (HuggingFace, HTTP, filesystem)
- Profile-based model management
- Performance benchmarking across backends
- Deployment automation scripts
- Integration testing framework
- Basic telemetry (InferenceEvent tracking)

**Documentation:**

- [README.md](README.md) - Current capabilities
- [MODEL_FETCH_SYSTEM.md](docs/MODEL_FETCH_SYSTEM.md)
- [BENCHMARKING.md](docs/BENCHMARKING.md)
- [PROFILE_TESTING.md](docs/PROFILE_TESTING.md)

---

## Planned Milestones

### 🎯 Milestone A: Monitoring & Observability

**Status:** Design complete, implementation not started

**Goal:** Production monitoring with drift detection, alerting, and automated retraining triggers.

**Key Features:**

- Real-time metrics with 5min/hourly/daily aggregation
- Input, prediction, and concept drift detection (KS test, chi-square, PSI)
- Configurable alerting with severity levels
- Automated retraining triggers with approval workflow
- Data quality tracking (schema violations, null rates, outliers)
- Dashboard for model health visualization

**Design Documentation:** [Complete Design](docs/plans/2025-01-aiops-framework-design.md#milestone-a-monitoring--observability)

**Estimated Effort:** 4-6 weeks

**Prerequisites:**

- None (can start immediately)

---

### 🎯 Milestone C: Training & Validation

**Status:** Design complete, implementation not started

**Goal:** Model training orchestration with experiment tracking and lifecycle management.

**Key Features:**

- Dual version system (source version + deployment version)
- Queue-based training with status tracking
- In-process training for simple models
- Experiment tracking with per-epoch metrics
- Validation workflow with approval gates
- Model lifecycle: candidate → staging → production → archived
- Automatic model promotion based on validation metrics

**Design Documentation:** [Complete Design](docs/plans/2025-01-aiops-framework-design.md#milestone-c-training--validation)

**Estimated Effort:** 6-8 weeks

**Prerequisites:**

- Milestone A (monitoring provides metrics for validation)

---

### 🔄 Milestone B: Core Data & Services

**Status:** Not yet designed

**Goal:** Feature engineering, data pipelines, and feature store integration.

**Planned Features:**

- Feature store with time-travel queries
- Data preprocessing pipelines
- Feature engineering framework
- BigQuery integration for data warehousing
- Feature lineage tracking

**Estimated Effort:** 8-10 weeks

**Prerequisites:**

- Milestone A (monitoring for feature drift)

---

### 🔄 Milestone D: Deployment & Orchestration

**Status:** Not yet designed

**Goal:** CI/CD pipelines with canary releases and A/B testing.

**Planned Features:**

- Model CI/CD pipelines
- Canary release system
- A/B testing framework
- Blue-green deployment support
- Automated rollback on errors

**Estimated Effort:** 6-8 weeks

**Prerequisites:**

- Milestone A (monitoring for deployment health)
- Milestone C (validation for promotion)

---

## Contributing to the Roadmap

### How to Help

1. **Review Design Docs** - Provide feedback on milestone designs
2. **Implement Features** - Pick up tasks from current milestone
3. **Test & Validate** - Help test new features
4. **Documentation** - Improve guides and examples

### Priority Areas

**Immediate (Next 3 months):**

- Milestone A: Monitoring & Observability
- Improved benchmarking UI
- Additional backend support (PyTorch, etc.)

**Medium-term (3-6 months):**

- Milestone C: Training & Validation
- Advanced drift detection algorithms
- Model explainability features

**Long-term (6-12 months):**

- Milestone B: Feature Store
- Milestone D: Deployment Orchestration
- Cloud provider integrations

---

## Design Philosophy

### Core Principles

1. **Harper-Native First** - Leverage Harper's built-in capabilities
2. **Simplicity Over Features** - Only add what's needed
3. **Production-Ready** - Everything must be tested and reliable
4. **Multi-Backend Support** - Don't lock into one framework
5. **Developer Experience** - Clear docs, good errors, easy setup

### Technology Decisions

- **Why Harper?** - Built-in CRUD, clustering, file storage, worker jobs
- **Why Multi-Backend?** - Different models have different optimal runtimes
- **Why Profile-Based?** - Easy environment-specific configuration
- **Why CLI-First?** - Fastest path to value for developers

---

## Release Strategy

### Version Numbering

- **0.x.x** - Foundation and infrastructure (current)
- **1.x.x** - Milestone A complete (monitoring)
- **2.x.x** - Milestone C complete (training)
- **3.x.x** - Milestones B+D complete (full platform)

### Current Version: 0.9.0

**Next Release:** 1.0.0 (when Milestone A ships)

---

## Timeline (Aspirational)

```
2026 Q1: Complete Milestone A (Monitoring)
2026 Q2: Complete Milestone C (Training)
2026 Q3: Complete Milestone B (Feature Store)
2026 Q4: Complete Milestone D (Deployment Orchestration)
```

**Note:** Timeline subject to change based on contributor availability and priorities.

---

## Questions or Ideas?

- Open an issue for feature requests
- Review [CONTRIBUTING.md](CONTRIBUTING.md) for how to help
- Check [docs/plans/](docs/plans/) for detailed designs
- See [README.md](README.md) for current capabilities

---

## Historical Context

### Why This Roadmap Exists

This roadmap was created to separate the project's **vision** (what we want to build) from its **reality** (what currently exists). The original README conflated these, making it hard for new users to understand what was actually implemented.

**For current capabilities**, see [README.md](README.md).

**For future plans**, you're in the right place.
