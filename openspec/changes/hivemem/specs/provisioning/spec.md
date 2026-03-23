## ADDED Requirements

### Requirement: Docker Compose deployment
The system SHALL provide a `docker-compose.yml` that runs PostgreSQL (with pg_search) and the Rails MCP server as services.

#### Scenario: Start all services
- **WHEN** an operator runs `docker compose up`
- **THEN** PostgreSQL SHALL start with pg_search extension enabled, and the Rails server SHALL start and connect to the database

#### Scenario: Stop all services
- **WHEN** an operator runs `docker compose down`
- **THEN** all services SHALL stop gracefully, and data SHALL persist in Docker volumes

### Requirement: PostgreSQL with pg_search
The PostgreSQL service SHALL use the ParadeDB Docker image with pg_search extension pre-installed and enabled.

#### Scenario: pg_search extension available
- **WHEN** the PostgreSQL container starts
- **THEN** the pg_search extension SHALL be available and `CREATE EXTENSION pg_search` SHALL succeed

### Requirement: Persistent data storage
The PostgreSQL data directory SHALL be mounted as a Docker volume to persist data across container restarts.

#### Scenario: Data survives restart
- **WHEN** the PostgreSQL container is stopped and restarted
- **THEN** all previously stored knowledge records SHALL be intact

### Requirement: Database initialization
The system SHALL run database migrations automatically on first start to create the knowledge records schema and BM25 index.

#### Scenario: Fresh deployment
- **WHEN** the system starts with an empty database
- **THEN** migrations SHALL run automatically, creating all required tables and indexes

#### Scenario: Existing deployment
- **WHEN** the system starts with an already-migrated database
- **THEN** only pending migrations SHALL run (no data loss)

### Requirement: Environment configuration
The system SHALL use environment variables for database credentials, host, port, Rails secret key, and authentication token.

#### Scenario: Custom database credentials
- **WHEN** an operator sets DB_USER, DB_PASSWORD, DB_HOST, DB_PORT environment variables
- **THEN** the Rails server SHALL connect using those credentials

#### Scenario: Authentication token configured
- **WHEN** an operator sets the HIVEMEM_AUTH_TOKEN environment variable
- **THEN** the Rails server SHALL require that token for authenticating API requests

#### Scenario: Default configuration
- **WHEN** no custom environment variables are set
- **THEN** the system SHALL use sensible defaults for local Docker Compose deployment

### Requirement: HTTP port exposure
The Rails MCP server container SHALL expose its HTTP port to the host so that clients can connect to the API.

#### Scenario: Port mapped to host
- **WHEN** the system starts via `docker compose up`
- **THEN** port 3055 inside the Rails container SHALL be mapped to port 3055 on the host, and HTTP requests to `http://localhost:3055` SHALL reach the Rails server

### Requirement: Health check endpoint
The Rails application SHALL expose a health endpoint that Docker can use for container health checks.

#### Scenario: Healthy container
- **WHEN** the Rails server is running and connected to the database
- **THEN** a GET request to the health endpoint SHALL return an HTTP 200 response

#### Scenario: Docker health check integration
- **WHEN** the Docker Compose configuration defines a health check using the health endpoint
- **THEN** Docker SHALL mark the Rails container as healthy only after the endpoint returns a successful response
