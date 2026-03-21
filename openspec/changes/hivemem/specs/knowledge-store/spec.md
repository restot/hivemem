## ADDED Requirements

### Requirement: Knowledge record schema
The system SHALL store knowledge records with the following fields:
- `id`: primary key (UUID)
- `shortlink`: unique identifier in format `hm-<base62>`, generated at creation, immutable
- `title`: short descriptive title
- `summary`: 1-3 sentence summary for search result display
- `content`: full record content (text, no size limit for v1)
- `knowledge_type`: one of: convention, pattern, decision, failure, reference, guide
- `project`: project identifier string (e.g. "telegram-bot", "hivemem")
- `tags`: array of free-form string tags
- `created_at`, `updated_at`: timestamps
- `created_by`: actor identifier (agent name or user)

#### Scenario: Create a knowledge record
- **WHEN** a client submits a record with title, content, knowledge_type, and project
- **THEN** the system SHALL generate a unique shortlink, set created_at/updated_at, store the record, and return the complete record with shortlink

#### Scenario: Shortlink uniqueness
- **WHEN** a new record is created
- **THEN** the generated shortlink SHALL be unique across all records

#### Scenario: Shortlink immutability
- **WHEN** a record is updated
- **THEN** the shortlink SHALL NOT change

### Requirement: Knowledge record update
The system SHALL allow updating mutable fields on an existing record (title, summary, content, knowledge_type, project, tags).

#### Scenario: Update record fields
- **WHEN** a client submits an update with a valid shortlink and changed fields
- **THEN** the system SHALL update only the specified fields, update `updated_at`, and return the updated record

#### Scenario: Update non-existent record
- **WHEN** a client submits an update with an invalid shortlink
- **THEN** the system SHALL return an error indicating the record was not found

### Requirement: Knowledge record deletion
The system SHALL allow permanently deleting records by shortlink.

#### Scenario: Delete a record
- **WHEN** a client requests deletion of a record by shortlink
- **THEN** the system SHALL permanently remove the record from the database

### Requirement: Knowledge record retrieval
The system SHALL allow fetching a full record by shortlink.

#### Scenario: Fetch by shortlink
- **WHEN** a client requests a record by shortlink
- **THEN** the system SHALL return the complete record including all fields

### Requirement: BM25 index on knowledge records
The system SHALL maintain a BM25 full-text index (via pg_search) over the title, summary, content, and tags fields of all records.

#### Scenario: Index updates on write
- **WHEN** a record is created or updated
- **THEN** the BM25 index SHALL reflect the new content for subsequent searches
