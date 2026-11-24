# AGENTS.md

Guidance for AI coding agents (Claude Code, Cursor, etc.) working in this Ruby on Rails project. **Must be read and followed before generating or editing any code.**

---

## 0. Interaction Mode & Workflow (Strict Rule)

- **DO NOT EDIT CODEBASE FILES DIRECTLY:** The AI agent is strictly forbidden from directly modifying, creating, or deleting codebase files (`app/`, `config/`, `Gemfile`, etc.).
- **PROVIDE CODE IN CHAT ONLY:** The user writes/edits all code manually.
- **CONCISE CODE SNIPPETS FOR EXISTING FILES:** For existing files with minor edits, provide precise partial code diffs/snippets with clear line & method context instead of outputting the entire file. Full file snippets are permitted for newly created files.
- **MANDATORY PRE-READING:** Before outputting any code solutions in the chat, the agent MUST read `AGENTS.md` and `PRD.md`, and inspect the relevant codebase files first.
- **MANDATORY STRICT TYPING (`# typed: strict`):** Every application code file inside `app/` MUST start with `# typed: strict` and include full Sorbet `sig` type annotations for all methods. Lower strictness levels (`typed: true`, `typed: false`, `typed: ignore`) are forbidden in `app/`.
- **MANDATORY ENGLISH IN CODEBASE:** All code, variable names, method names, comments, docstrings, and error messages inside the codebase MUST be written in English.
- **STRICT PROHIBITION OF HARDCODED VALUES:** Hardcoding values (dummy fallback strings, hardcoded IDs/URLs, static mock arrays, hardcoded rack locations) directly inside application code is strictly forbidden. All data MUST be dynamically driven from database records, environment variables, configuration initializers, repositories, or model attributes.
- **DEMO DATA VIA SEEDER ONLY:** All dummy/demo data required for testing or demonstration MUST be populated strictly through database seeders (`db/seeds.rb`) or FactoryBot factories (`spec/factories/`), NEVER hardcoded directly inside application source code files (`app/`).
- **STRICT PROHIBITION OF PSEUDO-RANDOM & DUMMY MATH FALLBACKS:** Generating fake metrics using pseudo-random math formulas (e.g. `10 + rand(5)`, `order_id_num % 15`, `idx * 15`) to simulate real metrics or network ping latencies is strictly prohibited. All data MUST be derived from real database records, actual socket/HTTP network executions, or discussed with the user beforehand.
- **MANDATORY TEST PYRAMID FOR ALL FEATURES:** Every new feature or feature modification MUST be accompanied by a complete Test Pyramid test suite in RSpec: Unit Tests (`spec/services/`, `spec/repositories/`), Request/Controller Specs (`spec/requests/`), and System/Feature Specs.
- **MANDATORY PRE-ALIGNMENT BEFORE EXECUTION:** The AI agent MUST NOT immediately build, edit, or create files when receiving a request. The agent MUST ALWAYS ask the user for clarification, design alignment, and explicit confirmation FIRST before outputting code or executing tasks.
- **MANDATORY FOLLOW-UP QUESTIONS & ITERATIVE ALIGNMENT:** If the user's response or requirements contain any ambiguity, underspecified details, or potential edge cases, the AI agent MUST ask follow-up questions to resolve all ambiguities before executing any code.
- **STRICT PROHIBITION OF FAKE/SKELETON FEATURES (NO FAKE FEATURES):** The AI agent is strictly forbidden from creating fake, decorative, or useless skeleton implementations. Every feature MUST be engineered for real production execution using actual browser/system APIs, real network sockets, and real database mutations.
- **MANDATORY TECHNICAL & ARCHITECTURAL INTERVIEW:** Before building any feature, the AI agent MUST carefully plan the real execution flow and interview/ask the user regarding the real execution hardware/APIs, code structure, clean code design patterns, and domain preferences to align 100% with the user's wishes.
- **NEVER HARDCODE FALLBACK VALUES; CREATE DATABASE MIGRATIONS INSTEAD:** If a database table or model lacks required attributes (such as latitude, longitude, configurations, or status flags), the AI agent MUST NEVER hardcode arbitrary fallback values inside controllers, services, or views. The AI agent MUST create proper database migrations, update ActiveRecord models, update Sorbet `# typed: strict` signatures, and populate real values via seeders or database records.
- **MANDATORY MULTI-SERVICE ECOSYSTEM PRE-READING & CROSS-AUDIT BEFORE PLANNING (Rule 25):** Before planning, designing, or suggesting any new feature or architectural component, the AI agent MUST thoroughly read `PRD.md`, `microservices_grpc_migration_plan.md`, and inspect all existing services across the entire ecosystem (`fashion_fulfillment_oms`, `kinetix-matching-service`, `kinetix-courier-mobile`, `storefront`). The AI agent is strictly forbidden from proposing or building functionality inside OMS that already exists or belongs to another microservice (e.g. proposing direct driver WebSocket connections in OMS when `kinetix-matching-service` is dedicated to driver WebSockets).










---

## 1. Architecture Philosophy

This project **intentionally deviates from Rails' default conventions** ("fat model/controller"). Use a layered architecture:

```
Controller → Service → Repository → Model (ActiveRecord)
```

Core rules:
- **Model (ActiveRecord)** = persistence layer ONLY. No business logic, no `scope` that encodes business rules, no `before_save`/`after_save` callbacks that run business processes.
- **Repository** = the only layer allowed to call ActiveRecord/Arel queries. No database queries outside a repository.
- **Service** = one class = one business operation (use case). No business logic in controllers or models.
- **Controller** = orchestration ONLY: receive request → call service → render response. No validation or logic here.
- **Form Object** = validation and shaping of complex input, kept separate from the ActiveRecord model.

Static typing is mandatory via **Sorbet** across all layers except initializer/config files.

---

## 2. Folder Structure

```
app/
├── core/
│   ├── container.rb            # DI container setup (dry-container)
│   ├── base_repository.rb
│   └── base_service.rb
├── contracts/
│   └── <domain>_repository_interface.rb
├── repositories/
│   └── <domain>_repository.rb
├── services/
│   └── <domain>/
│       └── <action>_service.rb  # e.g. get_user_profile_service.rb
├── forms/
│   └── <domain>/
│       └── <action>_form.rb
├── models/
│   └── <model>.rb
├── controllers/
│   └── <domain>_controller.rb
sorbet/
├── config
└── rbi/
config/
└── initializers/
    └── container.rb
```

Naming conventions:
- Service class: `<Verb><Noun>Service` (e.g. `GetUserProfileService`, `CreateOrderService`)
- Repository: `<Model>Repository`
- Form: `<Verb><Noun>Form` (e.g. `UpdateProfileForm`)
- All services and repositories are namespaced per domain module (e.g. `Users::`, `Orders::`)

---

## 3. Dependency Injection

Use `dry-container` + `dry-auto_inject`. Never call `Model.new` directly inside a service — always inject the repository through the constructor.

```ruby
# app/core/container.rb
require 'dry/container'
require 'dry/auto_inject'

class Container
  extend Dry::Container::Mixin
end

AutoInject = Dry::AutoInject(Container)
```

Register dependencies in `config/initializers/container.rb`. **Every time a new service/repository is created, its registration must be added here.**

```ruby
Container.register(:user_repository) { UserRepository.new }
Container.register(:get_user_profile_service) do
  Users::GetUserProfileService.new(user_repository: Container[:user_repository])
end
```

In controllers, pull instances from the container and wrap them with `T.let` to keep Sorbet type-safe:

```ruby
service = T.let(Container[:get_user_profile_service], Users::GetUserProfileService)
```

---

## 4. Sorbet — Strictness Level Per Layer

| File type | `typed:` level |
|---|---|
| `app/contracts/*` | `strict` (use `interface!` + `abstract.`) |
| `app/repositories/*` | `strict` (use `override.`) |
| `app/services/*` | `strict` |
| `app/forms/*` | `strict` |
| `app/controllers/*` | `strict` |
| `app/models/*` | `strict` (column signatures generated by `sorbet-rails`) |
| `config/initializers/container.rb` | `false` (DI registration blocks don't need strict) |

**Mandatory rules:**
1. Every public method in a service/repository MUST have a `sig { ... }`.
2. Every interface (`app/contracts/`) uses `extend T::Helpers` + `interface!`, with methods defined via `sig { abstract... }`.
3. Every interface implementation uses `sig { override... }` — not a plain `sig { params... }` — so Sorbet cross-checks the signature against the interface.
4. Data transferred between layers (service return values) must use `T::Struct`, NOT a plain `Hash`. This makes field typos fail at compile-time.
5. Every `Container[:xxx]` result must be wrapped in `T.let(..., ClassName)` before use, since dry-container returns `T.untyped`.
6. Run `bundle exec srb tc` before considering a task complete. Any type-check error MUST be fixed, not skipped with `T.unsafe` unless there's truly no other way (and a comment explaining why is required).

---

## 5. Mandatory Code Templates

### Contract (`app/contracts/<domain>_repository_interface.rb`)
```ruby
# typed: strict
module <Domain>RepositoryInterface
  extend T::Sig
  extend T::Helpers
  interface!

  sig { abstract.params(id: Integer).returns(T.nilable(<Model>)) }
  def find_by_id(id); end
end
```

### Repository (`app/repositories/<domain>_repository.rb`)
```ruby
# typed: strict
class <Domain>Repository < BaseRepository
  include <Domain>RepositoryInterface
  extend T::Sig

  sig { void }
  def initialize
    super(<Model>)
  end

  sig { override.params(id: Integer).returns(T.nilable(<Model>)) }
  def find_by_id(id)
    model.find_by(id: id)
  end
end
```

### Service (`app/services/<domain>/<action>_service.rb`)
```ruby
# typed: strict
module <Domain>
  class <Action>Service < BaseService
    extend T::Sig
    include AutoInject['<domain>_repository']

    class ResultData < T::Struct
      const :id, Integer
      # other fields as needed
    end

    sig { params(id: Integer).returns(BaseService::Result[ResultData]) }
    def call(id:)
      record = <domain>_repository.find_by_id(id)
      return failure("Not found") unless record

      success(serialize(record))
    end

    private

    sig { params(record: <Model>).returns(ResultData) }
    def serialize(record)
      ResultData.new(id: record.id)
    end
  end
end
```

### Controller (`app/controllers/<domain>_controller.rb`)
```ruby
# typed: strict
class <Domain>Controller < ApplicationController
  extend T::Sig

  sig { void }
  def show
    service = T.let(Container[:<action>_service], <Domain>::<Action>Service)
    result = service.call(id: params[:id].to_i)

    if result.success?
      render json: result.data
    else
      render json: { error: result.error }, status: :not_found
    end
  end
end
```

---

## 6. Explicit Prohibitions

The agent MUST NOT:
- Put ActiveRecord queries (`.where`, `.find`, `.joins`, etc.) inside a service, controller, or a model scope that encodes business rules.
- Put business validation (beyond simple column validation) directly in an ActiveRecord model.
- Create a service whose `call` method lacks a `sig`.
- Create a repository without implementing an interface + `override.`.
- Return a raw `Hash` from a service — always use `T::Struct`.
- Call `Container[:xxx]` without wrapping it in `T.let`.
- Create any file under `app/` without `# typed: strict` at the top or with missing Sorbet `sig` annotations.
- Add a new gem or dependency without explicitly telling the user, especially anything that changes this architectural pattern.

---

## 7. Checklist Before Finishing a Task

- [ ] Business logic lives in a service, not in a controller/model
- [ ] Database queries only exist inside a repository
- [ ] Interface (`contracts/`) created/updated if a new repository was added
- [ ] Every public method has a `sig`
- [ ] Service return values use `T::Struct`, not `Hash`
- [ ] DI registration added to `config/initializers/container.rb`
- [ ] `bundle exec srb tc` runs with no errors
- [ ] Form object created for every complex input that needs validation

---

## 8. Gem Reference

```ruby
gem 'dry-container'
gem 'dry-auto_inject'
gem 'sorbet'
gem 'sorbet-runtime'

group :development, :test do
  gem 'tapioca', require: false
  gem 'ruby-lsp', require: false
end
```

Initial setup for a new project:
```bash
bundle install
bundle exec tapioca init
bundle exec srb tc
```

---

## 9. Principal Engineer Strict Audit Protocol (The Anti-Skeleton Rule)

When asked to perform a codebase audit, the AI agent MUST act as an Expert Principal Engineer conducting strict, deep-level audits. Evaluates ACTUAL implementation and execution logic, NOT just structural existence.

### CRITICAL AUDIT RULE: THE "ANTI-SKELETON" CHECK
Never assume a feature or module is "100% complete" simply because:
1. The file, class, or module exists.
2. Method signatures or type definitions (e.g. Sorbet `sig`, TypeScript types) are syntactically correct.
3. Test suite (RSpec) passes (tests might be stubbed/mocked or asserting against empty methods).

### Mandatory Deep Audit Checklist:
1. **Verify Core Execution Logic:** Read inside functions/methods. If a service is designed for external communication (e.g. `MatchingWebSocketClient`, REST APIs, gRPC), verify the presence of actual network execution code (e.g. `Net::HTTP` execution, active event loops, explicit socket connections, streaming logic).
2. **Identify Placeholders:** Scrutinize code for skeleton implementations. Flag methods containing empty blocks, hardcoded generic returns (e.g. `return true`, `return nil`), or logic that merely logs/prints without executing the intended side effect.
3. **Analyze Mock Dependency:** Review tests alongside implementation. Ensure test suite validates actual state mutations and network failure handling, not just happy-path stubs.

### Strict Reporting Format
For every audited file or module, output using this structure:

- **Component:** [Class/File Name]
- **Implementation Status:** [FULLY IMPLEMENTED | SKELETON/STUB | PARTIAL]
- **Execution Logic Verification:** Describe exactly how internal code operates.
- **Test Integrity:** Are tests asserting real logic or stubbed responses?
- **Actionable Gap:** Specific functional code needed for high-throughput production readiness.

**IMPORTANT:** If a skeleton or placeholder masquerading as a completed feature is detected, immediately output **[CRITICAL: STUB DETECTED]**. Do not praise structural correctness if functional business logic is missing.

---

## 10. Senior Frontend Engineer & UI/UX Design System Standard

The AI agent MUST follow the Senior Frontend Engineer Skill (`.agents/skills/senior-frontend/SKILL.md`) for all HTML/ERB views and CSS styles:
1. **Zero Generic AI Layouts:** Never use default browser fonts or flat gray backgrounds. Use dark slate mode (`#0f172a`), HSL vibrant accents (Indigo `#6366f1`, Emerald `#10b981`, Violet `#8b5cf6`), and Google Fonts (`Outfit`, `Plus Jakarta Sans`, `Inter`).
2. **Glassmorphism:** Wrap cards in semi-transparent containers (`rgba(30, 41, 59, 0.75)` with `backdrop-filter: blur(16px)` and subtle border highlights).
3. **Interactive Motion:** Add hover card lifting (`transform: translateY(-4px)`), pulse dots for live status, and responsive CSS Grid.
4. **DRY Architecture:** Reusable partials MUST be extracted to `app/views/shared/`.