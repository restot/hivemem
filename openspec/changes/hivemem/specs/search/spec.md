## ADDED Requirements

### Requirement: BM25 full-text search
The system SHALL provide BM25-ranked full-text search across all non-deleted knowledge records, searching over title, summary, content, and tags fields using pg_search. Query terms are OR'd by default, matching is performed via the pg_search `@@@` operator, and results are ranked by `paradedb.score()`.

#### Scenario: Basic search query
- **WHEN** a client submits a search query string
- **THEN** the system SHALL match records using the `@@@` operator, rank them by `paradedb.score()`, and return each result containing (shortlink, title, summary, tags, knowledge_type, project, score)

#### Scenario: Multi-term query
- **WHEN** a client submits a query with multiple terms (e.g. "convention deployment")
- **THEN** the system SHALL OR the terms together, returning records that match any of the terms, ranked by `paradedb.score()`

#### Scenario: Empty results
- **WHEN** a client submits a search query that matches no records
- **THEN** the system SHALL return an empty result set

### Requirement: Browse/list without a query
The system SHALL support browsing records when no search query string is provided. When filters are supplied but no query, the system SHALL return all records matching the filters sorted by updated_at descending.

#### Scenario: List all records for a project
- **WHEN** a client requests records with a project filter but no query string
- **THEN** the system SHALL return all non-deleted records for that project, sorted by updated_at descending

#### Scenario: List by knowledge type without query
- **WHEN** a client requests records with a knowledge_type filter but no query string
- **THEN** the system SHALL return all non-deleted records of that type, sorted by updated_at descending

#### Scenario: List with combined filters and no query
- **WHEN** a client requests records with multiple filters (e.g. project + knowledge_type + tags) but no query string
- **THEN** the system SHALL return all non-deleted records matching all filters (AND logic), sorted by updated_at descending

#### Scenario: No query and no filters
- **WHEN** a client requests records with neither a query string nor any filters
- **THEN** the system SHALL return all non-deleted records sorted by updated_at descending

### Requirement: Pre-filtering before BM25
The system SHALL support optional pre-filters that narrow the candidate set before BM25 ranking: project, knowledge_type, and tags.

#### Scenario: Filter by project
- **WHEN** a client searches with a project filter
- **THEN** the system SHALL only BM25-rank records matching that project

#### Scenario: Filter by knowledge type
- **WHEN** a client searches with a knowledge_type filter
- **THEN** the system SHALL only BM25-rank records matching that type

#### Scenario: Filter by tags
- **WHEN** a client searches with one or more tag filters
- **THEN** the system SHALL only BM25-rank records that have ALL specified tags (AND logic)

#### Scenario: Combined filters
- **WHEN** a client searches with multiple filter types (e.g. project + tags)
- **THEN** the system SHALL apply all filters (AND logic) before BM25 ranking

### Requirement: Search result format
Each search result SHALL contain: shortlink, title, summary, tags, knowledge_type, project, and BM25 relevance score. Full content SHALL NOT be included in search results.

#### Scenario: Agent scans results without fetching content
- **WHEN** a search returns results
- **THEN** each result SHALL contain sufficient metadata (shortlink, summary, tags) for an agent to assess relevance without fetching the full record

### Requirement: Search pagination
The system SHALL support limit and offset parameters for paginating search results.

#### Scenario: Paginated search
- **WHEN** a client searches with limit=10 and offset=20
- **THEN** the system SHALL return at most 10 results starting from position 20 in the ranked result set

#### Scenario: Default pagination
- **WHEN** a client searches without pagination parameters
- **THEN** the system SHALL return at most 20 results starting from position 0
