## ADDED Requirements

### Requirement: Evidence-based artwork rendering
The frontend SHALL preserve valid provider artwork references and classify transport, policy, and decode failures. It SHALL NOT replace failed artwork with unrelated fictional film artwork or relax TLS verification globally.

#### Scenario: A poster cannot be rendered
- **WHEN** a provider poster fails validation, transport, or decoding
- **THEN** the original poster bounds remain stable, an explicit fallback/recovery path is shown, and no false success is reported

### Requirement: Truthful catalog filtering
Remote filters SHALL use verified provider parameters. Local-only filtering SHALL be identified as applying to loaded items. Pagination SHALL remain reachable for empty filtered pages while more server pages exist.

#### Scenario: The first filtered page is empty
- **WHEN** more server pages exist
- **THEN** the interface offers continuation rather than claiming there are no global matches

### Requirement: Short feed presentation and playback ownership
The short feed SHALL show only a search icon at the top. Bottom title, metadata, episode information and summary SHALL remain readable without overlapping action rails or bottom navigation. The visible feed alone SHALL own playback and preserve the actual loaded episode's progress.

#### Scenario: Long provider metadata
- **WHEN** a short title, genre list or episode count is long
- **THEN** metadata is constrained or wrapped without squeezing the episode indicator out of view

#### Scenario: A route or tab covers the feed
- **WHEN** the short feed becomes inactive
- **THEN** it pauses, releases or safely suspends media ownership, and does not continue hidden playback or attribute old progress to a pending episode
