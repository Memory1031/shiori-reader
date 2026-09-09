# AGENTS.md

Conventions for coding agents working in this repository. Keep this file focused on durable project principles; task-specific designs, implementation steps, progress, and acceptance criteria belong in the project documentation.

## Working conventions

- Follow the user's current task and constraints. Consult [docs/TASK_PLAN.md](docs/TASK_PLAN.md) for scope, dependencies, architecture decisions, and acceptance criteria before implementation. Do not automatically start subsequent tasks.
- Inspect the working tree and preserve user / other agent changes, including staged and untracked files. Coordinate shared files when parallel work is authorized.
- Prefer small, reviewable changes and the simplest design that meets the task. Avoid speculative abstractions, premature optimization, and unrelated refactoring.
- Use Chinese for project explanations and task documentation unless requested otherwise; preserve established code naming and the English commit convention below.

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
- Record task outcomes and evidence in the relevant project documents. Keep this file free of task status snapshots, specific task instructions, and duplicated implementation specifications.

## Git commits

- Commit messages must be written in English (user requirement, effective 2026-09-07).
- Keep the repo's existing format: `<type>: <short summary>` subject line, followed by `-` bullet points grouping the change by module.
