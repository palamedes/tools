
# Tools Repository

A personal collection of utility tools for Ruby on Rails development. The primary file is `tools.rb`, which defines `Ellis::Tools` — a module you load into a Rails console to inspect models, trace relationships, annotate schemas, and more.

---

## Usage

```ruby
# Load in any Rails console
load ‘/path/to/tools.rb’
```

---

## Features

### Model Annotations

Generate detailed schema annotations including columns, types, defaults, nullability, validations, indexes, and check constraints.

```ruby
# Annotate a model — prints to console and copies to clipboard
Ellis::Tools.annotate(User)

# Write the annotation directly to the model file
Ellis::Tools.annotate(User, to_file: true)
```

**Model options** (defaults: `to_clipboard: true`, `to_screen: true`, `to_file: false`):
- `:to_clipboard` — Copy the output to the clipboard
- `:to_screen` — Display the output in the console
- `:to_file` — Append the annotation to the model source file

### Controller Annotations

Inserts route comments directly above each action method in the controller source file.

```ruby
# Annotates the controller file with route comments above each action
Ellis::Tools.annotate(EvaluationsController)

# Example result in the controller file:
# [GET] /evaluations
def index

# [PUT/PATCH] /evaluations/:id
def update
```

Controllers default to `to_file: true` and `to_clipboard: false`. Multiple HTTP verbs for the same action are combined. Re-running safely replaces existing route comments.

### Relationship Tracing

Find all ActiveRecord association paths between two models via breadth-first search.

```ruby
Ellis::Tools.relations(User, Organization)
# => [
#   "User belongs_to :current_organization -> Organization",
#   "User has_many :organization_users -> OrganizationUser belongs_to :organization -> Organization"
# ]

# Options: max_depth (default: 10), verbose: true, max_steps: 100_000
```

### Dependents

List all models that reference a given model through associations.

```ruby
Ellis::Tools.dependents(Patient)
# => 🔗 Evaluation has_many :patients → Patient [dependent: :destroy]
#    ...
```

### Required Fields / Validations

Returns a detailed hash of all validations on a model’s fields.

```ruby
Ellis::Tools.required(Evaluation)
# => {
#   "date"       => "presence",
#   "patient_id" => "presence (association: :patient)",
#   "title"      => ["presence", "length(minimum: 2, maximum: 255)"],
#   "amount"     => "numericality(greater_than_or_equal_to: 0) — if: :billable?"
# }

# Include database-level NOT NULL constraints:
Ellis::Tools.required(Evaluation, validators_only: false)
```

### Data Comparison

Compare two ActiveRecord objects and highlight attribute differences.

```ruby
Ellis::Tools.diff_objects(user1, user2, ignore_keys: [:updated_at, :id])
# => { "email" => ["old@example.com", "new@example.com"], "name" => ["John", "Johnny"] }
```

### Benchmarking

Compare execution times of methods.

```ruby
Ellis::Tools.bench :old_method, :new_method, 500  # 500 iterations (default: 250)
```

### Data Export

Extract model data as hashes.

```ruby
Ellis::Tools.get_data_hash(User, to_clipboard: true, limit: 100)
```

### Clipboard

Copy any value to the macOS clipboard.

```ruby
Ellis::Tools.clipboard(some_value)
```

### PostgreSQL Dump Rewriting

Stream-based find/replace for large files, designed for rewriting pg dumps for local development.

```ruby
# Generic file rewrite
Ellis::Tools.rewrite_file("/path/to/dump.sql", replacements: { "old_role" => "new_role" })

# Preset rewrite for Ambiki dumps
Ellis::Tools.rewrite_ambiki_pg_dump("/path/to/dump.sql")
```
