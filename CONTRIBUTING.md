# Contributing to Harper Edge AI Example

Thank you for considering contributing! This guide will help you get started.

## Code of Conduct

Be respectful, inclusive, and professional in all interactions.

## Getting Started

### 1. Fork and Clone

```bash
git clone https://github.com/YOUR_USERNAME/harper-edge-ai-example.git
cd harper-edge-ai-example
npm install
```

### 2. Run Tests

```bash
npm run test:all
```

### 3. Start Development Server

```bash
npm run dev
```

## Development Workflow

### Branching Strategy

- `main` - Stable releases
- `feature/*` - New features
- `fix/*` - Bug fixes

### Making Changes

1. Create feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make changes following code style

3. Write/update tests

4. Commit with descriptive message:
   ```bash
   git commit -m "feat: add new backend for XYZ"
   ```

### Commit Message Format

Follow conventional commits:

```
type(scope): description

[optional body]
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `refactor`: Code refactoring
- `test`: Test changes
- `chore`: Maintenance tasks

**Examples**:
```
feat(backend): add PyTorch backend support
fix(onnx): correct mean pooling dimension handling
docs(api): update predict endpoint documentation
```

### Pull Request Process

1. Push to your fork
2. Open PR against `main` branch
3. Fill out PR template
4. Ensure all CI checks pass
5. Request review from maintainers
6. Address feedback
7. Squash commits if requested

## Code Style

### JavaScript

- Use ESM modules (`import`/`export`)
- Follow existing code formatting
- Use meaningful variable names
- Add JSDoc for all public APIs
- Keep functions small and focused

### Documentation

- Update relevant docs for API changes
- Add code examples for new features
- Keep line length under 100 characters
- Use markdown for all documentation

### Testing

- Write unit tests for all new code
- Add integration tests for API changes
- Aim for >80% code coverage
- Use descriptive test names

**Example**:
```javascript
describe('BenchmarkEngine', () => {
  it('should find models with matching equivalenceGroup', async () => {
    // Test implementation
  });
});
```

## Project Structure

```
harper-edge-ai-example/
├── src/
│   ├── core/
│   │   ├── backends/        # ML framework backends
│   │   ├── InferenceEngine.js
│   │   └── BenchmarkEngine.js
│   ├── resources.js         # Harper API resources
│   └── PersonalizationEngine.js
├── tests/
│   ├── unit/               # Unit tests
│   └── integration/        # Integration tests
├── docs/                   # Documentation
├── scripts/               # Utility scripts
└── examples/             # Usage examples
```

## Adding New Features

### New Backend

1. Extend `BaseBackend` class
2. Implement `loadModel()` and `predict()` methods
3. Add unit tests in `tests/unit/`
4. Register in `InferenceEngine.initialize()`
5. Add documentation

**Example**:
```javascript
export class MyBackend extends BaseBackend {
  constructor() {
    super('MyBackend');
  }

  async loadModel(modelKey, modelBlob, modelRecord) {
    // Implementation
    this.models.set(modelKey, {model, config});
    return {loaded: true, inputNames: [...], outputNames: [...]};
  }

  async predict(modelKey, inputs) {
    const modelInfo = this._validateLoaded(modelKey);
    // Run inference
    return {output: result};
  }
}
```

### New Model Type

1. Define metadata schema in model record
2. Add to existing backend or create new one
3. Add benchmark test data
4. Document usage

### New API Endpoint

1. Add Resource to `src/resources.js`
2. Implement handler methods
3. Add integration tests
4. Document in inline JSDoc

## Testing Guidelines

### Unit Tests

Test individual components in isolation.

**Location**: `tests/unit/`

```bash
npm run test:unit
```

### Integration Tests

Test end-to-end workflows with Harper.

**Location**: `tests/integration/`

```bash
npm run test:integration
```

### Running Tests

```bash
# All tests
npm run test:all

# Unit tests only
npm run test:unit

# Integration tests only
npm run test:integration

# Single file
node --test tests/unit/MyTest.test.js
```

## Documentation

### Code Documentation

Use JSDoc for all public APIs:

```javascript
/**
 * Brief description
 *
 * Detailed description with multiple lines.
 *
 * @param {Type} paramName - Parameter description
 * @returns {Type} Return value description
 * @throws {Error} When error occurs
 * @example
 * const result = myFunction(param);
 */
```

### File Documentation

Update:
- README for usage changes
- Inline JSDoc for API changes
- Add code examples for new features

## Need Help?

- Check existing documentation in `/docs`
- Search issues on GitHub
- Open discussion for questions
- Join Harper community Discord

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.
