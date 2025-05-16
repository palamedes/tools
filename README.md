
# Tools Repository

This repository contains a collection of utility tools created over the years to streamline and improve the development workflow, particularly in Ruby on Rails applications.

---

## Ellis::Tools Module

The `Ellis::Tools` module enhances the Rails development experience by providing a rich set of utility functions for:

- Annotations
- Debugging
- Relationship Analysis
- Data Comparison
- Performance Benchmarking

It’s especially useful for developers who need to quickly understand and document the structure of complex Rails applications. The module is intended for interactive use within the Rails console but also supports persistent documentation via file updates.

---

### ✨ **Key Features**

- **📚 Model and Controller Annotations**
    - Generate detailed annotations for ActiveRecord models and Rails controllers.
    - Includes columns, data types, defaults, nullability, validations, and indexes.
    - Output can be displayed in the console, copied to the clipboard, or appended directly to model files.

- **🔗 Relationship Tracing**
    - Explore and visualize all possible ActiveRecord relationship paths between two models.
    - Helps uncover deeply nested and indirect associations.
    - Supports configurable max depth and verbose progress reporting.

- **📝 Data Comparison**
    - Compare two ActiveRecord objects and highlight attribute differences.
    - Supports normalization (e.g., dates to strings) and excluding specific attributes from comparison.

- **🚀 Benchmarking Utilities**
    - Easily benchmark and compare the execution time of methods using Ruby’s `Benchmark` library.

- **📤 Data Export**
    - Extract model data as hashes with optional pagination and clipboard support.

- **📋 Clipboard Integration (macOS)**
    - Copy output directly to the system clipboard using the `pbcopy` utility.

- **🔧 Console Utilities**
    - Retrieve model attribute keys, required fields, and dynamically update model files with annotation content.

---

### 📖 **Usage Examples**

#### Annotate Models and Controllers

```ruby
# Load the tools in your Rails console
load '/path/to/tools.rb'

# Annotate a model and print to console
Ellis::Tools.annotate(User)

# Annotate a model and append the annotation directly to the model file
Ellis::Tools.annotate(User, to_file: true)

# Options:
# :to_clipboard - Copy the output to the clipboard (default: true)
# :to_screen    - Display the output in the console (default: true)
# :to_file      - Append the output directly to the model file (default: false)
```

---

#### Trace Relationships Between Models

```ruby
Ellis::Tools.relations(User, Organization)
# Example Output:
# [
#   "User belongs_to :current_organization -> Organization",
#   "User has_many :organization_users -> OrganizationUser belongs_to :organization -> Organization"
# ]
```

---

#### Compare Two ActiveRecord Objects

```ruby
Ellis::Tools.diff_objects(user1, user2, ignore_keys: [:updated_at, :id])
# => { "email" => ["old@example.com", "new@example.com"], "name" => ["John", "Johnny"] }
```

---

#### Benchmark Method Performance

```ruby
Ellis::Tools.bench :old_method, :new_method
```

---

#### Export Model Data

```ruby
Ellis::Tools.get_data_hash(User, to_clipboard: true, limit: 100)
```

---

### 📅 **Planned Improvements**

- Add support for non-macOS clipboard utilities.
- Enhance file path resolution for models in non-standard locations.
- Add relationship path weighting to highlight "primary" paths.
- Expand controller annotation support.
