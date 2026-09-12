# AGENTS.md

Conventions for coding agents working in this repository.

Keep this file focused on durable project principles. Do not create or update project documentation merely to record the current task, implementation process, validation run, or agent reasoning.

## Working conventions

- Follow the user's current task and constraints. Consult [docs/README.md](docs/README.md) for relevant module documentation before implementation and [docs/release/README.md](docs/release/README.md) for release operations. Do not automatically start subsequent tasks.
- Inspect the working tree and preserve user / other agent changes, including staged and untracked files. Coordinate shared files when parallel work is authorized.
- Prefer small, reviewable changes and the simplest design that meets the task. Avoid speculative abstractions, premature optimization, and unrelated refactoring.
- Use Chinese for project explanations and task documentation when documentation is actually required, unless requested otherwise; preserve established code naming and the English commit convention below.
- Do not broaden the scope to cleanup, documentation, refactoring, or follow-up work unless it is required for correctness or explicitly requested.

## Documentation policy

Documentation changes are opt-in, not a default part of implementation work.

- Do not create a new document unless the user explicitly requests one or there is no appropriate existing document for a durable project-level fact.
- Do not update documentation just because code was changed.
- Update an existing document only when the change makes that document materially incorrect or incomplete about stable behavior.
- Documentation should describe the current durable state of the project, not the history of how that state was reached.
- Before editing docs, ask: "Would the existing documentation be false or materially misleading after this change?" If not, do not edit it.
- Prefer code, tests, commit messages, and pull-request descriptions for implementation details and development evidence.

Never add the following to tracked project documentation unless the user explicitly asks for it:

- task IDs or phase names such as `TASK-123`, or implementation milestones;
- task plans, TODO checklists, acceptance checklists, progress reports, or completion reports;
- dated validation records or "tested on YYYY-MM-DD" sections;
- local machine diagnostics, temporary environment workarounds, cache issues, or tool installation notes that are not durable setup requirements;
- command transcripts, test-run counts, elapsed times, or one-off build results;
- agent reasoning, review notes, investigation history, or explanations of why the agent chose an implementation;
- temporary compatibility notes that cease to matter once the implementation is complete;
- duplicated implementation details already clear from code or tests.

When documentation must change:

- describe behavior, contracts, architecture, user workflow, supported platforms, or durable setup requirements;
- keep it concise and platform-neutral where behavior is shared;
- avoid duplicating the same contract across multiple documents;
- use terminology consistently with the code;
- remove obsolete statements instead of appending historical corrections.

Commit messages and pull-request descriptions are the preferred place for implementation summaries, validation evidence, test counts, migration notes, temporary limitations, and task-specific context.

If unsure whether a documentation change is necessary, do not make it.

## Architecture principles

- Keep domain logic pure Dart and independent of UI frameworks, networking, storage, and concrete data sources. Domain models remain immutable.
- Presentation consumes domain contracts. Keep site-specific protocols, parsing, credentials, and transport/storage details behind the data layer boundaries.
- Use explicit dependency injection and clear resource ownership. Avoid hidden global service dependencies; handle asynchronous cancellation and lifecycle cleanup deliberately.
- Preserve existing model and contract semantics. Read [docs/architecture.md](docs/architecture.md) and [docs/contracts.md](docs/contracts.md) when affected, and update specifications and consumers together when contracts change.
- Keep development fixtures and test infrastructure separate from production behavior.
- Design user-facing UI for localization; currently support Chinese and English. Keep translatable copy in shared language resources and account for different text lengths. See [docs/architecture.md](docs/architecture.md) for the implementation convention.

## Platforms and dependencies

- Android and iOS are the application targets; Windows is a development host. Preserve shared-code compatibility and respect platform conventions.
- Follow the toolchain pins and [docs/development.md](docs/development.md). Add or upgrade dependencies only when needed for the task, checking SDK and target-platform compatibility.
- Keep machine-specific paths, downloaded toolchains, credentials, and generated build artifacts out of tracked application configuration.

## Validation and evidence

- Run checks appropriate to the change and the task's acceptance criteria. Default tests to offline, deterministic fixtures; live Source checks require explicit opt-in and documented request limits.
- Report what was actually validated. Distinguish unit tests, widget tests, builds, emulator runs, device runs, and release checks; document skipped or blocked verification without claiming success.
- Review iOS compatibility for shared changes. Track unavailable iOS runtime validation separately from Android completion; documentation or compile success does not establish device/runtime success.
- Treat Source behavior as evidence-based and time-sensitive. Consult [docs/source/lightnovel.md](docs/source/lightnovel.md), preserve unresolved assumptions, respect access boundaries, and sanitize logs and fixtures.
- Keep task outcomes, validation evidence, and development process in commit messages or pull-request descriptions rather than tracked project documentation; update a document only when the change makes its description of stable behavior materially incorrect or incomplete. Keep this file free of task status snapshots, specific task instructions, and duplicated implementation specifications.

## Git commits

- Commit messages must be written in English (user requirement, effective 2026-09-07).
- Keep the repo's existing format: `<type>: <short summary>` subject line, followed by `-` bullet points grouping the change by module.
