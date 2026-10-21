## ADDED Requirements

### Requirement: Frontend owns the provider
The Android frontend SHALL call and decode the first provider directly. The backend MUST NOT fetch, decode or proxy provider content and Duoscene credentials MUST NOT be sent upstream.

#### Scenario: Authenticated browsing
- **WHEN** an authenticated user opens the catalog
- **THEN** the frontend loads real provider items without contacting a backend media route

#### Scenario: Design preview
- **WHEN** an explicit preview library is used
- **THEN** the existing static catalog remains isolated and no provider request is made

### Requirement: Complete and bounded protocol surface
The provider SHALL expose all 17 documented methods with request allowlisting, bounded network work and validated response shapes. Reconstructed responses MUST NOT be represented as authoritative server acknowledgements.

#### Scenario: Invalid envelope or business error
- **WHEN** a response has invalid padding, unsupported shape or a non-success business code
- **THEN** the operation fails explicitly and no fake catalog success is returned

#### Scenario: Truncated parser parameter
- **WHEN** secret_parse_api_url returns a short parameter
- **THEN** the frontend retries at most eight times and fails if the known complete length is never reached

### Requirement: Browse and resolve real media
The frontend SHALL support recommendation, category and search pages, detail, line selection, episode selection and resolved PlaybackSource identities.

#### Scenario: Pagination ignores requested limit
- **WHEN** the provider returns 21 items for limit 10 and reports pagecount
- **THEN** pagination uses returned page metadata and deduplicates provider-qualified IDs

#### Scenario: Direct versus parser source
- **WHEN** a source contains a parse_api even though its token starts with http
- **THEN** it is resolved through the parser instead of being treated as a direct stream

### Requirement: Persistent safe metadata
The frontend SHALL persist account-scoped favorite and history metadata without persisting short-lived media credentials or breaking existing v1 entries.

#### Scenario: Restart with provider history
- **WHEN** the app restarts after watching and favoriting a provider item
- **THEN** metadata and progress restore and playback resolves a fresh address

### Requirement: Safe upstream presentation
The frontend MUST NOT execute upstream HTML, updates, advertisements or arbitrary player parameters. Android cleartext exemptions SHALL be limited to the configured provider host and existing debug local hosts.

#### Scenario: Remote HTML or executable options
- **WHEN** the provider returns markup, advertisement links or core_params
- **THEN** they do not execute or alter native player configuration

### Requirement: Evidence-based delivery
The change SHALL include serial live interface evidence, offline protocol tests and Android build/runtime verification with limitations explicitly recorded.

#### Scenario: Partial playback verification
- **WHEN** manifests and 64-byte media ranges succeed but a device has not rendered frames
- **THEN** the report distinguishes network success from device playback success
