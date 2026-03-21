## ADDED Requirements

### Requirement: MCP tool registration
The Rails server SHALL expose the following MCP tools: `hivemem_search`, `hivemem_read`, `hivemem_write`, `hivemem_update`, `hivemem_delete`.

#### Scenario: Client discovers available tools
- **WHEN** an MCP client connects and requests the tool list
- **THEN** the server SHALL return all five tools with their input schemas

### Requirement: hivemem_search tool
The `hivemem_search` tool SHALL accept a query string and optional filters (project, knowledge_type, tags, limit, offset) and return BM25-ranked search results.

#### Scenario: Agent searches for knowledge
- **WHEN** an agent calls `hivemem_search` with query "cancel streaming" and filter project="telegram-bot"
- **THEN** the server SHALL return matching records ranked by BM25, filtered to the telegram-bot project

### Requirement: hivemem_read tool
The `hivemem_read` tool SHALL accept a shortlink and return the full record content.

#### Scenario: Agent fetches full record
- **WHEN** an agent calls `hivemem_read` with shortlink "hm-abc123"
- **THEN** the server SHALL return the complete record with all fields

### Requirement: hivemem_write tool
The `hivemem_write` tool SHALL accept title, content, knowledge_type, project, and optional (summary, tags, metadata) and create a new knowledge record.

#### Scenario: Agent records a new decision
- **WHEN** an agent calls `hivemem_write` with title, content, knowledge_type="decision", project="hivemem"
- **THEN** the server SHALL create the record, generate a shortlink, and return the created record

### Requirement: hivemem_update tool
The `hivemem_update` tool SHALL accept a shortlink and fields to update. Tags can be updated via this tool by providing tags to add and/or tags to remove.

#### Scenario: Agent updates a record
- **WHEN** an agent calls `hivemem_update` with a shortlink and new tags
- **THEN** the server SHALL update the record and return the updated version

### Requirement: hivemem_delete tool
The `hivemem_delete` tool SHALL accept a shortlink and soft-delete the record.

#### Scenario: Agent deletes a record
- **WHEN** an agent calls `hivemem_delete` with a valid shortlink
- **THEN** the server SHALL soft-delete the record and confirm deletion

### Requirement: MCP transport support
The server SHALL support HTTPS-only streamable HTTP transport for all MCP clients.

#### Scenario: Client connects via streamable HTTP
- **WHEN** a client connects to the HTTPS MCP endpoint
- **THEN** the server SHALL handle MCP requests over streamable HTTP

### Requirement: Bearer token authentication
The server SHALL require a valid bearer token for all MCP requests over HTTP. The token is configured via the `HIVEMEM_AUTH_TOKEN` environment variable.

#### Scenario: Valid token provided
- **WHEN** a client sends an MCP request with a valid bearer token in the Authorization header
- **THEN** the server SHALL proceed with the request

#### Scenario: Missing or invalid token
- **WHEN** a client sends an MCP request with a missing or invalid bearer token
- **THEN** the server SHALL return an MCP authentication error

### Requirement: Error handling
The server SHALL return structured MCP errors for invalid inputs, not-found records, and server errors.

#### Scenario: Invalid shortlink format
- **WHEN** a client calls any tool with a malformed shortlink
- **THEN** the server SHALL return an MCP error with a descriptive message

#### Scenario: Server database error
- **WHEN** the database is unavailable
- **THEN** the server SHALL return an MCP error indicating a temporary failure
