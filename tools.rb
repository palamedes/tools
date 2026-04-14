# The Ellis::Tools module provides a collection of utility functions to assist developers
# in annotating, debugging, and analyzing Ruby on Rails applications directly from the console.
#
# This module focuses on improving developer productivity by exposing application structure,
# model relationships, data comparisons, and performance benchmarks.
#
# === Features
#
# * **Model Annotations**
#   - Generate detailed schema annotations for ActiveRecord models, including columns, types, defaults,
#     nullability, validations, and indexes.
#   - Output annotations to the console, copy to clipboard, or append directly to model files.
#
# * **Relationship Tracing**
#   - Explore and visualize all possible ActiveRecord association paths between two models.
#   - Supports configurable maximum depth and verbose progress reporting.
#
# * **Data Comparison**
#   - Compare two ActiveRecord objects and highlight attribute differences.
#   - Supports normalization of data types (e.g., Date/Time objects) and ignoring specific attributes.
#
# * **Benchmarking**
#   - Easily benchmark and compare the execution time of two methods using Ruby’s Benchmark library.
#
# * **Data Export**
#   - Extract model data as hashes with optional pagination and clipboard support.
#
# * **Clipboard Integration**
#   - Copy output directly to the macOS clipboard using the `pbcopy` command.
#
# * **Console Utilities**
#   - Methods for retrieving model attribute keys, required fields, and dynamically writing content to model files.
#
# === Example Usage
#
#   # Annotate the User model and display results in the console
#   Ellis::Tools.annotate User
#
#   # Find all relationship paths between User and Organization
#   Ellis::Tools.relations User, Organization
#
#   # Compare two objects for differences
#   Ellis::Tools.diff_objects user1, user2, ignore_keys: [:updated_at, :id]
#
#   # Benchmark two methods
#   Ellis::Tools.bench :old_method, :new_method
#
#   # Ambiki psql rewrite
#   Ellis::Tools.rewrite_ambiki_pg_dump("/Users/jellis/T7/DBBackups/Ambiki/postgres-172.16.1.42-......")
#
module Ellis
  class Tools
    class << self

      # Provides a detailed annotation of ActiveRecord models or Rails controllers. This method can output annotations
      # directly to the console, copy them to the clipboard, or append them to the relevant model or controller files.
      # It is designed to help developers quickly understand the structure and relationships of various components in
      # their application.
      #
      # Usage:
      #   load '/{path to file}/tools.rb'
      #   Ellis::Tools.annotate [Model], *options
      #
      # Example:
      #   Ellis::Tools.annotate User, to_file: true
      #
      # Options:
      #   :to_clipboard - (Boolean) Whether to copy the output to the clipboard. Default: true.
      #   :to_screen - (Boolean) Whether to display the output on the screen. Default: true.
      #   :to_file - (Boolean) Whether to append the output to the model's file. Default: false.
      #
      # @param target [Class] The ActiveRecord model or Rails controller to be annotated.
      # @param args [Hash] A hash of options to customize the behavior of the method.
      def annotate target, args = {}
        if target.is_a?(Class) && target < ActiveRecord::Base
          defaults = { to_clipboard: true, to_screen: true, to_file: false }
          annotate_model target, defaults.merge(args)
        elsif target.is_a?(Class) && target < ApplicationController
          defaults = { to_clipboard: false, to_screen: true, to_file: true }
          annotate_controller target, defaults.merge(args)
        else
          puts "Error: I don't know what you're trying to do."
        end
      end

      ##
      # Finds and returns all possible ActiveRecord association paths between two models.
      #
      # This method performs a breadth-first search to discover all unique ways one model
      # can be related to another through ActiveRecord associations. It is useful for
      # understanding complex relationships in large Rails applications and tracing indirect
      # connections between models.
      #
      # @param source [Class] The starting model class (must be an ActiveRecord::Base descendant).
      # @param destination [Class] The target model class (must be an ActiveRecord::Base descendant).
      # @param max_depth [Integer] Maximum allowed relationship depth to prevent infinite traversal. Default: 10.
      # @param verbose [Boolean] Whether to print progress updates to the console. Default: true.
      # @param max_steps [Integer] Maximum number of traversal steps before aborting the search. Default: 100,000.
      #
      # @return [Array<String>]
      #   An array of formatted strings, each representing a valid relationship path between the models.
      #   If no path is found, returns a message indicating that no relationship path exists.
      def relations source, destination, max_depth = 10, verbose: false, max_steps: 100_000
        # Validate that source is a valid ActiveRecord model class
        unless source.is_a?(Class) && source < ActiveRecord::Base
          return "Error: Source must be an ActiveRecord model class."
        end
        # Validate that destination is a valid ActiveRecord model class
        unless destination.is_a?(Class) && destination < ActiveRecord::Base
          return "Error: Destination must be an ActiveRecord model class."
        end
        all_paths = []                       # Stores all found valid relationship paths
        queue = [[source, []]]                # BFS queue initialized with the source model
        steps_checked = 0                     # Tracks how many relationship steps we’ve evaluated
        globally_visited = Set.new            # Prevents revisiting the same models unnecessarily
        while queue.any?
          current, path = queue.shift         # Dequeue the next model and its current path
          steps_checked += 1
          # Output progress every 500 steps if verbose mode is enabled
          puts "🔄 Checked #{steps_checked} steps. Current: #{current.name}, Depth: #{path.size}" if verbose && (steps_checked % 100).zero?
          # Hard stop if maximum number of steps is exceeded
          return "Traversal aborted after #{steps_checked} steps." if steps_checked >= max_steps
          # Skip any paths that exceed the max allowed depth
          next if path.size > max_depth
          # If we've reached the destination model, store the full path and continue exploring for more paths
          if current == destination
            all_paths << (path + [[current, nil]])
            next
          end
          globally_visited.add(current)  # Mark current model as visited globally to prevent re-exploring
          # Explore all associations for the current model
          current.reflect_on_all_associations.each do |assoc|
            assoc_class = safe_association_class(assoc)  # Safely resolve the associated class
            next unless assoc_class                      # Skip if association doesn't resolve to a valid class
            next if globally_visited.include?(assoc_class)  # Skip if this model has already been globally visited
            # Enqueue the next model to explore with the updated path
            queue << [assoc_class, path + [[current, assoc]]]
          end
        end
        # Output completion message if verbose is enabled
        puts "✅ Done. Checked #{steps_checked} steps. Found #{all_paths.size} path(s)." if verbose
        # If no paths were found, return a helpful message
        return "No relationship path found between #{source.name} and #{destination.name}" if all_paths.empty?
        # Format the paths into readable strings and sort them alphabetically by the first relationship
        result = all_paths.map { |p| format_relationship_path(p) }
        result.sort_by! { |path| path.split(' -> ').first }
        result
      end

      ##
      # Compares two ActiveRecord objects and returns the differences in their attributes.
      #
      # This method is useful for auditing changes between two records, identifying discrepancies,
      # or performing custom equality checks outside of ActiveRecord's built-in dirty tracking.
      #
      # @param obj1 [ActiveRecord::Base] The first object to compare (must respond to `.attributes`).
      # @param obj2 [ActiveRecord::Base] The second object to compare (must respond to `.attributes`).
      # @param ignore_keys [Array<Symbol, String>] Attributes to ignore during comparison (default: []).
      # @param normalize [Boolean] Whether to normalize values for comparison (e.g., dates to strings). Default: true.
      #
      # @return [Hash<String, Array>]
      #   A hash where each key is a differing attribute name, and the value is a two-element array
      #   containing [value_in_obj1, value_in_obj2].
      def diff_objects obj1, obj2, ignore_keys: [], normalize: true
        # Ensure both objects implement .attributes
        unless obj1.respond_to?(:attributes) && obj2.respond_to?(:attributes)
          raise ArgumentError, "Both objects must respond to .attributes"
        end
        # Retrieve attribute hashes from both objects
        attrs1 = obj1.attributes
        attrs2 = obj2.attributes
        # Build a complete list of unique keys across both objects, excluding ignored keys
        all_keys = (attrs1.keys + attrs2.keys).uniq - ignore_keys.map(&:to_s)
        diffs = {}
        # Iterate through each attribute and compare values
        all_keys.each do |key|
          val1 = attrs1[key]
          val2 = attrs2[key]
          # Normalize values for consistent comparison (e.g., date objects to strings)
          if normalize
            val1 = normalize_value(val1)
            val2 = normalize_value(val2)
          end
          # If the values differ, store them in the diffs hash
          diffs[key] = [val1, val2] if val1 != val2
        end
        # Return only attributes with differences
        diffs
      end

      # Compares the execution times of two methods using the Ruby Benchmark module.
      # It executes each method a specified number of times and reports the execution time.
      #
      # @param old [Symbol, String] the name of the first method to benchmark.
      # @param new [Symbol, String, nil] the name of the second method to benchmark, optional.
      # @param n [Integer] the number of times each method is called during the benchmark; defaults to 250.
      # @return [nil] Outputs the benchmarking result to stdout and returns nil.
      def bench old, new=nil, n=250
        Benchmark.bm do |b|
          b.report(old) do
            n.times do
              send old.to_sym
            end
          end
          b.report(new) do
            n.times do
              send new.to_sym
            end
          end unless new.nil?
        end
        nil
      end

      # Fetches data for all records of a model, applies optional pagination, and can copy results to the clipboard.
      #
      # @param model [ActiveRecord::Base, ActiveRecord::Relation] the model or scope from which to fetch data.
      # @param options [Hash] options to customize the operation with keys :to_clipboard, :limit, and :offset.
      #   :to_clipboard - when true, copies the data to the clipboard.
      #   :limit - limits the number of records fetched.
      #   :offset - skips a number of records.
      # @return [Array, String] Returns an array of data hashes unless :to_clipboard is true, then returns a string confirmation.
      def get_data_hash model, options = { to_clipboard: false, limit: 1000 }
        res = []
        model = model.all if model.class == Class
        model = model.offset(options[:offset]) if options.key? :offset
        model = model.limit(options[:limit]) if options.key? :limit
        model.each do |m|
          res << self.get_object_data(m)
        end
        # Copy to cliboard if we need to
        if options.key?(:to_clipboard) && options[:to_clipboard]
          pbcopy res
          return 'Copied to Clipboard'
        else
          res
        end
      end

      ##
      # Retrieves attribute values for a given ActiveRecord object and formats them in a hash.
      # Dates are wrapped in quotes to ensure proper formatting.
      #
      # @param object [ActiveRecord::Base] the ActiveRecord object from which data is extracted.
      # @return [Hash] a hash where each key is an attribute name and the value is the attribute's value from the object.
      def get_object_data object
        res = {}
        keys = get_attribute_keys object.class
        keys.each do |k|
          # Wrap Date in Quotes
          if object[k].class == ActiveSupport::TimeWithZone
            res[k] = "#{object[k]}"
          else
            res[k] = object[k]
          end
        end
        res
      end

      ##
      # Fetches and sorts the attribute names of a given ActiveRecord model class.
      #
      # @param model [Class] the ActiveRecord model class for which to retrieve attribute names.
      # @return [Array<String>] a sorted array of attribute names from the model.
      def get_attribute_keys model
        keys = []
        columns = model.columns.sort_by(&:name)
        columns.each do |col|
          keys << col.name
        end
        keys
      end

      ##
      # Returns a hash of required fields for the given model that are needed to save it.
      # A required field is considered to be:
      # 1. A field that is marked as "NOT NULL" in the database and does not have a default value (or with a default value).
      # 2. A field that has a `validates_presence_of` or similar validation in the model.
      #
      # The returned hash will have field names as keys and their default value (if any) as the value.
      # If there is no default value, the value will be `nil`.
      #
      # @param model [Class] the ActiveRecord model class to check.
      # @return [Hash<String, Object>] the hash of required field names and their default values.
      ##
      # Returns a detailed hash describing all validations on a model's fields.
      #
      # Each key is the attribute (or foreign key) name. Each value is either a single
      # validation description string or an array of descriptions when multiple validations
      # apply to the same field.
      #
      # Validation descriptions include the type, any constraints/options, and any
      # conditions (:if, :unless, :on) so you can see when a validation actually fires.
      #
      # @param model [Class] The ActiveRecord model class to inspect.
      # @param validators_only [Boolean] When true, skip database-level NOT NULL checks. Default: true.
      #
      # @return [Hash<String, String|Array<String>>]
      #
      # @example
      #   Ellis::Tools.required Evaluation
      #   # => {
      #   #   "date"       => "presence",
      #   #   "patient_id" => "presence (association: :patient)",
      #   #   "title"      => ["presence", "length(minimum: 2, maximum: 255)"],
      #   #   "amount"     => "numericality(greater_than_or_equal_to: 0) — if: :billable?"
      #   # }
      def required model, validators_only: true
        raise ArgumentError, 'Argument must be an ActiveRecord model class' unless model.is_a?(Class) && model < ActiveRecord::Base

        field_validations = Hash.new { |h, k| h[k] = [] }

        # Step 1: Database-level NOT NULL constraints (when not skipping)
        unless validators_only
          model.columns.each do |column|
            next if ['id', 'created_at', 'updated_at'].include?(column.name)
            if !column.null
              desc = column.default.present? ? "not_null(default: #{column.default})" : "not_null"
              field_validations[column.name] << desc
            end
          end
        end

        # Build a map of belongs_to foreign_key -> association name for lookup
        fk_to_assoc = {}
        model.reflect_on_all_associations(:belongs_to).each do |assoc|
          fk_to_assoc[assoc.foreign_key] = assoc.name
        end

        # Step 2: Inspect every validator on the model
        model.validators.each do |validator|
          desc = format_validator(validator)
          next unless desc

          condition_suffix = format_conditions(validator)

          next unless validator.respond_to?(:attributes)
          validator.attributes.each do |attribute|
            attr_name = attribute.to_s

            # If the attribute is an association, convert to its foreign key
            assoc = model.reflect_on_association(attribute)
            if assoc && assoc.belongs_to?
              attr_name = assoc.foreign_key
              assoc_note = " (association: :#{attribute})"
            else
              assoc_note = ""
            end

            field_validations[attr_name] << "#{desc}#{assoc_note}#{condition_suffix}"
          end
        end

        # Deduplicate: if an association-tagged entry like "presence (association: :x)"
        # exists alongside a plain "presence", keep only the association-tagged one.
        result = {}
        field_validations.sort.each do |key, descriptions|
          descriptions.uniq!
          # Remove plain entries when a more descriptive version exists for the same validation type
          descriptions.reject! do |desc|
            base = desc.split(" —").first.strip # strip conditions to get the core validation
            descriptions.any? { |other| other != desc && other.split(" —").first.strip.start_with?(base) && other.include?("(") }
          end
          result[key] = descriptions.size == 1 ? descriptions.first : descriptions
        end
        result
      end

      ##
      # Lists all models in the application that have associations referencing a given model.
      #
      # This is extremely helpful when determining dependencies before deleting, renaming,
      # or refactoring a model or table. It searches all ActiveRecord models in the
      # application for `belongs_to`, `has_one`, `has_many`, and `has_and_belongs_to_many`
      # associations that point to the given target model.
      #
      # === Parameters
      # * +model+ - The ActiveRecord model class for which to find dependents.
      # * +verbose+ - (Boolean) Whether to print each dependency to the console as it is found. Default: true.
      # * +to_clipboard+ - (Boolean) When true, copies the dependency list to the macOS clipboard.
      #
      # === Example
      #   Ellis::Tools.dependents(Patient)
      #   # => Prints all models that reference Patient
      #
      # @return [Array<Hash>] A structured list of dependency details.
      def dependents(model, verbose: true, to_clipboard: false)
        raise ArgumentError, "Argument must be an ActiveRecord model class" unless model.is_a?(Class) && model < ActiveRecord::Base
        dependencies = []
        # Iterate through all loaded models in the application
        ActiveRecord::Base.descendants.each do |candidate|
          candidate.reflect_on_all_associations.each do |assoc|
            assoc_class = safe_association_class(assoc)
            next unless assoc_class == model

            dependencies << {
              model: candidate.name,
              association_name: assoc.name,
              macro: assoc.macro,
              foreign_key: assoc.foreign_key,
              dependent: assoc.options[:dependent],
              polymorphic: assoc.polymorphic?,
              as: assoc.options[:as]
            }

            if verbose
              puts "🔗 #{candidate.name} #{assoc.macro} :#{assoc.name}" \
                     " → #{model.name}" \
                     "#{assoc.polymorphic? ? ' (polymorphic)' : ''}" \
                     "#{assoc.options[:dependent] ? " [dependent: #{assoc.options[:dependent]}]" : ''}"
            end
          end
        end

        if dependencies.empty?
          puts "ℹ️  No models reference #{model.name}" if verbose
        else
          puts "\n✅ Found #{dependencies.size} dependent association#{'s' if dependencies.size != 1}." if verbose
        end
        if to_clipboard && dependencies.any?
          text = dependencies.map do |d|
            "#{d[:model]} #{d[:macro]} :#{d[:association_name]} → #{model.name}" \
              "#{d[:polymorphic] ? ' (polymorphic)' : ''}" \
              "#{d[:dependent] ? " [dependent: #{d[:dependent]}]" : ''}"
          end.join("\n")
          pbcopy text
          puts "📋 Copied #{dependencies.size} associations to clipboard."
        end
        dependencies
      end

      ##
      # Copies the given value to the system clipboard without printing or returning output.
      # Arrays are joined with newlines, hashes are converted to YAML, and all other values
      # are coerced to strings before copying.
      #
      # @param value [Object] The value to copy to the clipboard.
      # @return [nil]
      def clipboard(value)
        text =
          case value
          when Array
            value.join("\n")
          when Hash
            value.to_yaml
          else
            value.to_s
          end

        pbcopy(text)
        nil
      end

      ##
      # Performs high-performance streaming text replacements on a large file.
      #
      # Designed for massive Postgres dump rewrites without loading the entire file
      # into memory. Processes the file line-by-line and writes to a temp file.
      #
      # @param input_path [String] Path to the source file.
      # @param replacements [Hash{String => String}] Literal string replacements.
      # @param output_path [String, nil] Optional output path. Defaults to in-place rewrite.
      #
      # @return [void]
      def rewrite_file(input_path, replacements:, output_path: nil)
        raise ArgumentError, "File not found: #{input_path}" unless File.exist?(input_path)

        output_path ||= "#{input_path}.tmp"
        pattern = Regexp.union(replacements.keys)

        start_time = Time.now
        lines_processed = 0

        File.open(output_path, "w") do |out|
          File.foreach(input_path) do |line|
            line = line.gsub(pattern) { |match| replacements[match] }
            out.write(line)
            lines_processed += 1
          end
        end

        File.rename(output_path, input_path)
        duration = Time.now - start_time
        puts "✅ Rewrote #{lines_processed} lines in #{duration.round(2)}s"
        nil
      end

      ##
      # Rewrites a Postgres dump to match local development environment.
      #
      # @param path [String] Path to dump file.
      #
      # @return [void]
      def rewrite_ambiki_pg_dump(path)
        replacements = {
          "ROLE ambiki" => "ROLE ambiki_development",
          "Owner: ambiki" => "Owner: ambiki_development",
          "TO ambiki" => "TO ambiki_development",
          "DATABASE ambiki" => "DATABASE ambiki_development",
          "\\connect ambiki" => "\\connect ambiki_development",
          "DROP DATABASE template1;" => "",
          "en_US.utf8" => "en_US.UTF-8"
        }
        rewrite_file(path, replacements: replacements)
      end

      private

      ##
      # Annotates an ActiveRecord model with schema details including column names, types, defaults, and indexes.
      # It can optionally output this annotation to the console, copy it to the clipboard, or append it to the model's file.
      #
      # The annotation includes:
      # - Model name and table name.
      # - Each column's name, type (with limit), defaults, and nullability.
      # - Special handling for 'created_at' and 'updated_at' for better readability.
      # - List of indexes on the table, noting which are unique.
      #
      # Annotations are intended to help developers quickly understand the underlying database structure directly
      # from their model files or console output.
      #
      # @param target [Class] the ActiveRecord model class to annotate.
      # @param options [Hash] options to control the output of the annotations:
      #   :to_clipboard - When true, copies the annotation to the system clipboard.
      #   :to_screen - When true, prints the annotation to the console.
      #   :to_file - When true, appends the annotation to the model's file.
      #
      # @example Annotate the User model and output to console and clipboard
      #   annotate_model(User, to_screen: true, to_clipboard: true)
      # @example Annotate the User model and append to the model file
      #   annotate_model(User, to_file: true)
      #
      # @return [void] This method outputs annotations based on the options provided and does not return a value.
      def annotate_model target, options
        spc = longest_column_name_length(target) + 3
        res = []
        res << "# --- Model: '#{ActiveModel::Name.new(target).to_s}' Annotation"
        res << "# Table Name: #{target.table_name}"
        res << "#"
        # Getting columns and their details
        columns = target.columns.sort_by(&:name)
        primary_key = target.primary_key
        # Ensure primary key is processed first
        primary_key_column = columns.detect { |col| col.name == primary_key }
        other_columns = columns.reject { |col| col.name == primary_key }
        ordered_columns = [primary_key_column] + other_columns
        indexes = target.connection.indexes(target.table_name)
        # set some defaults
        created_at = ""
        updated_at = ""
        ordered_columns.each do |col|
          next unless col
          type_limit = col.limit.present? ? "#{col.type}(#{col.limit})" : "#{col.type}"
          opts = []
          opts << "Primary Key" if col.name == primary_key
          opts << "default(#{format_default(col)})" if col.default.present?
          opts << "not null" unless col.null
          opts << "enum" if target.defined_enums.key?(col.name)
          validations = column_validations(target, col.name)
          opts_str = opts.compact.join(', ')
          validations_str = validations.any? ? " ~ #{validations.join(', ')}" : ""
          # Pad only if there's something after the type
          type_str = (opts_str.empty? && validations_str.empty?) ? type_limit : type_limit.ljust(15)
          line = "#  #{col.name.ljust(spc)}:#{type_str}#{opts_str}#{validations_str}"
          comment_line = format_column_comment(col)
          created_at = line if col.name == 'created_at'
          updated_at = line if col.name == 'updated_at'
          unless col.name == 'created_at' || col.name == 'updated_at'
            res << line
            res << "##{comment_line}" if comment_line
          end
        end
        # Adding created_at and updated_at at the end for readability
        res << "#" unless created_at.empty? && updated_at.empty?
        res << created_at unless created_at.empty?
        res << updated_at unless updated_at.empty?
        # Append index information at the bottom
        if indexes.any?
          res << "#"
          res << "# Indexes"
          indexes.each do |index|
            res << "#  #{index.name}: #{index.columns.join(', ')}#{' (unique)' if index.unique}"
          end
        end
        # Append check constraint information if available
        constraints = get_check_constraints(target)
        if constraints.any?
          res << "#"
          res << "# Check Constraints"
          constraints.each do |constraint|
            res << "#  #{constraint['name']}: #{constraint['definition']}"
          end
        end
        # # Append enum definitions if present
        # enums = target.defined_enums
        # if enums.any?
        #   res << "#"
        #   res << "# Enums"
        #   enums.each do |name, values|
        #     res << "#  #{name}: { #{values.map { |k,v| "#{k}: #{v}" }.join(', ')} }"
        #   end
        # end
        # Output options
        puts "--- Model Annotation ---" if options[:to_screen]
        puts res if options[:to_screen]
        puts "---" if options[:to_screen] && !options[:to_clipboard]
        puts "--- Copied to clipboard ---" if options[:to_clipboard]
        pbcopy res if options[:to_clipboard]
        puts "--- Appended to file ---" if options[:to_file]
        write_to_file target, res if options[:to_file]
      end

      ##
      # Retrieves and formats validation rules for a specific column on an ActiveRecord model.
      #
      # This method inspects all validators applied to the given column and returns a list of
      # formatted validation descriptions. Standard Rails validations are labeled accordingly,
      # and custom validators are labeled using their class names.
      #
      # @param model [Class] The ActiveRecord model class being inspected.
      # @param column_name [String, Symbol] The name of the column to check for validations.
      #
      # @return [Array<String>]
      #   An array of validation descriptions. Examples include:
      #   'presence', 'uniqueness', 'length(minimum=2, maximum=50)', 'numericality', 'custom(my_validator)'.
      def column_validations model, column_name
        validations = []
        # Standard column-level validations
        model.validators_on(column_name.to_sym).each do |validator|
          case validator
          when ActiveModel::Validations::PresenceValidator
            validations << 'presence'
          when ActiveRecord::Validations::UniquenessValidator
            validations << 'uniqueness'
          when ActiveModel::Validations::LengthValidator
            range = validator.options.slice(:minimum, :maximum).map { |k, v| "#{k}=#{v}" }.join(", ")
            validations << "length(#{range})"
          when ActiveModel::Validations::NumericalityValidator
            validations << 'numericality'
          else
            validations << "custom(#{validator.class.name.demodulize.underscore})"
          end
        end
        # Handle presence validations on associations (e.g., validates :discharge, presence: true)
        model.reflect_on_all_associations(:belongs_to).each do |assoc|
          if column_name == assoc.foreign_key
            model.validators_on(assoc.name).each do |validator|
              validations << 'presence' if validator.is_a?(ActiveModel::Validations::PresenceValidator)
              validations << 'associated' if validator.is_a?(ActiveRecord::Validations::AssociatedValidator)
            end
          end
        end
        validations.uniq
      end

      # Annotate Controller -- See Annotate above for options
      #
      # When :to_file is true, inserts route comments directly above each action
      # method definition in the controller source file. For example:
      #
      #   # [GET] /evaluations
      #   def index
      #
      # Multiple verbs for the same action are combined:
      #
      #   # [PUT/PATCH] /evaluations/:id
      #   def update
      #
      # Re-running will replace existing route comments rather than duplicating them.
      def annotate_controller(target, options)
        controller_name = target.name.underscore.gsub('_controller', '')
        routes = Rails.application.routes.routes

        matched_routes = routes.select do |r|
          r.defaults[:controller] == controller_name
        end

        # Build a map of action_name => { verbs: [...], path: "..." }
        action_routes = {}
        matched_routes.each do |r|
          verb = r.verb.is_a?(Regexp) ? r.verb.source.gsub("^", "").gsub("$", "") : r.verb
          path = r.path.spec.to_s.gsub("(.:format)", "")
          path = resolve_friendly_params(path, controller_name)
          action = r.defaults[:action]
          next if verb.empty?
          action_routes[action] ||= { verbs: [], path: path }
          action_routes[action][:verbs] << verb unless action_routes[action][:verbs].include?(verb)
        end

        # Build summary for screen/clipboard output
        annotations = []
        annotations << "# --- Controller: '#{target.name}' Annotation"
        annotations << "#"
        annotations << "# Routes:"
        annotations << "#"
        action_routes.sort.each do |action, info|
          verbs = info[:verbs].join("/")
          annotations << "#  #{action.ljust(20)} [#{verbs}] #{info[:path]}"
        end
        # Show any actions that have no route
        no_route_actions = target.action_methods.sort - action_routes.keys
        if no_route_actions.any?
          annotations << "#"
          annotations << "# Actions without routes:"
          no_route_actions.each { |a| annotations << "#  #{a}" }
        end

        puts "--- Controller Annotation ---" if options[:to_screen]
        puts annotations if options[:to_screen]
        pbcopy(annotations) if options[:to_clipboard]
        puts "--- Copied to clipboard ---" if options[:to_clipboard]

        if options[:to_file]
          write_route_comments_to_controller(target, action_routes)
        end
      end

      # Reads the controller source file and inserts or replaces route comments
      # directly above each action's `def` line.
      #
      # Existing route comments (lines matching `# [VERB...] /path`) immediately
      # above a `def` are stripped before inserting the current ones, so re-runs
      # are safe.
      def write_route_comments_to_controller(target, action_routes)
        file_path = Module.const_source_location(target.name)&.first
        unless file_path && File.exist?(file_path)
          puts "❌ Could not determine the file path for #{target.name}. Skipping file write."
          return
        end

        lines = File.readlines(file_path)
        result = []
        actions_annotated = []

        i = 0
        while i < lines.length
          line = lines[i]

          # Check if this line is a `def action_name` that we have route info for
          if line =~ /^(\s*)def\s+(\w+)/
            indent = $1
            method_name = $2

            if action_routes.key?(method_name)
              # Strip any existing route comments immediately above this def
              while result.any? && result.last =~ /^\s*# \[[A-Z\/]+\] \//
                result.pop
              end
              # Remove blank line above if we stripped comments (we'll re-add one if needed)
              # but keep at least one blank line for readability if there's code above
              while result.length > 1 && result.last.strip.empty? && result[-2].strip.empty?
                result.pop
              end

              info = action_routes[method_name]
              verbs = info[:verbs].join("/")
              result << "#{indent}# [#{verbs}] #{info[:path]}\n"
              actions_annotated << method_name
            end
          end

          result << line
          i += 1
        end

        File.write(file_path, result.join)
        puts "✅ Annotated #{actions_annotated.size} action#{'s' if actions_annotated.size != 1} in #{file_path}"
        if actions_annotated.any?
          puts "   #{actions_annotated.join(', ')}"
        end
      end

      # Replaces route params like `:id` or `:user_id` with `{:id|:slug}` when
      # the corresponding model uses friendly_id.
      def resolve_friendly_params(path, controller_name)
        # Infer the "own" model from the controller name (e.g. "admin/users" -> "User")
        own_model_name = controller_name.split("/").last.classify

        path.gsub(/:(\w+_id|id)\b/) do |match|
          param = $1
          model_name = if param == "id"
                         own_model_name
                       else
                         param.sub(/_id$/, "").classify
                       end

          begin
            model = model_name.constantize
            if model.respond_to?(:friendly_id_config)
              slug_column = model.friendly_id_config.slug_column rescue "slug"
              "{:#{param}|:#{slug_column}}"
            else
              match
            end
          rescue NameError
            match
          end
        end
      end

      ##
      # Copies the given content to the system clipboard (macOS only).
      #
      # This method uses the `pbcopy` command-line utility available on macOS to
      # copy text content directly to the clipboard.
      #
      # @param arg [String] The content to be copied to the clipboard.
      #
      # @return [void]
      def pbcopy(arg)
        return unless RbConfig::CONFIG['host_os'] =~ /darwin/
        IO.popen('pbcopy', 'w') { |io| io.puts arg }
      end

      ##
      # Calculates the length of the longest column name in a given ActiveRecord model.
      #
      # This is primarily used to help align column annotations when generating
      # formatted model documentation.
      #
      # @param target [Class] The ActiveRecord model class.
      #
      # @return [Integer] The length of the longest column name.
      #
      # @example
      #   longest_column_name_length(User)  # => 12
      def longest_column_name_length target
        target.column_names.sort_by(&:length).last.length
      end

      ##
      # Appends the given annotation content to the corresponding model source file.
      #
      # This method attempts to locate the model's source file using Ruby's Module reflection (`const_source_location`).
      # If the file path cannot be determined, it will skip writing and output an error message.
      #
      # @param target [Class] The ActiveRecord model class whose file will be updated.
      # @param arg [Array<String>, String] The annotation content to append. If an array is provided, it will be joined with newlines.
      #
      # @return [void]
      def write_to_file(target, arg)
        # Locate the source file for the given model using Ruby's Module reflection.
        model_file_path = Module.const_source_location(target.name)&.first
        # Exit early if the file cannot be located.
        unless model_file_path && File.exist?(model_file_path)
          puts "❌ Could not determine the file path for #{target.name}. Skipping file write."
          return
        end
        # Read the current content of the model file.
        content = File.read(model_file_path)
        start_marker = "# --- Model: '#{target.name}' Annotation"
        # Remove any existing annotation by locating the last occurrence of the annotation marker.
        last_marker_index = content.rindex(start_marker)
        if last_marker_index
          # Remove everything from the marker to the end of the file, also trim trailing whitespace.
          content = content[0...last_marker_index].rstrip
        else
          # If no annotation exists, simply remove any trailing blank lines.
          content = content.rstrip
        end
        # Prepare the new annotation content.
        new_annotation = arg.is_a?(Array) ? arg.join("\n") : arg
        # Ensure the annotation marker is included at the start of the annotation.
        unless new_annotation.include?(start_marker)
          new_annotation = start_marker + "\n" + new_annotation
        end
        # Ensure exactly one blank line between the end of the class and the annotation.
        updated_content = content + "\n\n" + new_annotation + "\n"
        # Write the updated content back to the model file.
        File.write(model_file_path, updated_content)
        puts "✅ Annotation successfully updated in #{model_file_path}"
      end

      ##
      # Normalizes values for consistent comparison when diffing objects.
      #
      # This method is primarily used to ensure that values like dates and times
      # are converted to strings before comparison, avoiding false positives due
      # to differing object types but equivalent logical values.
      #
      # === Parameters
      # * +value+ - The value to normalize.
      #
      # === Returns
      # * The normalized value. Dates and times are converted to strings; all other values are returned as-is.
      #
      # === Example
      #   normalize_value(Time.now)  # => "2025-05-15 14:30:00 -0400"
      def normalize_value value
        case value
        when ActiveSupport::TimeWithZone, Time, DateTime, Date
          # Convert date and time objects to string for comparison consistency
          value.to_s
        else
          # Leave all other value types unchanged
          value
        end
      end

      ##
      # Safely resolves the class associated with an ActiveRecord association.
      #
      # This prevents errors when dealing with invalid or polymorphic associations that
      # may not have a directly resolvable class.
      #
      # === Parameters
      # * +assoc+ - An ActiveRecord::Reflection::AssociationReflection object.
      #
      # === Returns
      # * The associated class if it can be resolved, otherwise +nil+.
      #
      # === Example
      #   safe_association_class(User.reflect_on_association(:organization))
      #   # => Organization
      def safe_association_class assoc
        # Attempt to resolve the associated class; rescue errors and return nil if unresolved
        assoc.klass rescue nil
      end

      ##
      # Formats a relationship path into a readable string representation.
      #
      # This method converts a sequence of models and their associations into a
      # human-readable path like:
      #   "User has_many :organization_users -> OrganizationUser belongs_to :organization -> Organization"
      #
      # === Parameters
      # * +path+ - An array of [model, association] pairs representing the relationship path.
      #
      # === Returns
      # * A formatted string showing the relationship path.
      #
      # === Example
      #   format_relationship_path([[User, assoc1], [OrganizationUser, assoc2], [Organization, nil]])
      #   # => "User has_many :organization_users -> OrganizationUser belongs_to :organization -> Organization"
      def format_relationship_path path
        # Iterate through pairs of models and associations, formatting each step
        path.each_cons(2).map do |(model, assoc), (next_model, _)|
          assoc_part = assoc ? "#{assoc.macro} :#{assoc.name}" : ''
          "#{model.name} #{assoc_part}".strip
        end.join(" -> ") + " -> #{path.last[0].name}"  # Add the final model name at the end
      end

      ##
      # Retrieves all check constraints defined on a given table in PostgreSQL.
      #
      # @param model [Class] The ActiveRecord model whose table should be inspected.
      # @return [Array<Hash>] A list of hashes, each containing :name and :definition for the constraint.
      #
      # @example
      #   get_check_constraints(User)
      #   # => [{ name: "age_check", definition: "CHECK ((age >= 0))" }]
      def get_check_constraints(model)
        table_name = model.table_name
        sql = <<~SQL
          SELECT conname AS name, pg_get_constraintdef(oid) AS definition
          FROM pg_constraint
          WHERE conrelid = '#{table_name}'::regclass
            AND contype = 'c'
          ORDER BY conname;
        SQL
        ActiveRecord::Base.connection.exec_query(sql).to_a
      rescue StandardError => e
        puts "⚠️  Could not retrieve check constraints for #{model.name}: #{e.message}"
        []
      end

      ##
      # Formats a single validator into a human-readable description string.
      #
      # @param validator [ActiveModel::Validator]
      # @return [String, nil] A description like "presence", "length(minimum: 2)", etc. Returns nil for unknown validators.
      def format_validator(validator)
        case validator
        when ActiveModel::Validations::PresenceValidator
          "presence"
        when ActiveModel::Validations::AbsenceValidator
          "absence"
        when ActiveRecord::Validations::UniquenessValidator
          opts = []
          opts << "scope: #{Array(validator.options[:scope]).map(&:inspect).join(', ')}" if validator.options[:scope]
          opts << "case_sensitive: #{validator.options[:case_sensitive]}" if validator.options.key?(:case_sensitive)
          opts.any? ? "uniqueness(#{opts.join(', ')})" : "uniqueness"
        when ActiveModel::Validations::LengthValidator
          parts = validator.options.slice(:minimum, :maximum, :is, :in).map { |k, v| "#{k}: #{v}" }
          parts.any? ? "length(#{parts.join(', ')})" : "length"
        when ActiveModel::Validations::NumericalityValidator
          parts = validator.options.except(:if, :unless, :on, :message, :allow_nil, :allow_blank)
            .map { |k, v| "#{k}: #{v}" }
          parts << "allow_nil" if validator.options[:allow_nil]
          parts.any? ? "numericality(#{parts.join(', ')})" : "numericality"
        when ActiveModel::Validations::InclusionValidator
          set = validator.options[:in] || validator.options[:within]
          if set.is_a?(Range)
            "inclusion(in: #{set})"
          elsif set.is_a?(Array) && set.size <= 10
            "inclusion(in: #{set.inspect})"
          elsif set.is_a?(Array)
            "inclusion(in: [#{set.size} values])"
          else
            "inclusion"
          end
        when ActiveModel::Validations::ExclusionValidator
          set = validator.options[:in] || validator.options[:within]
          if set.is_a?(Array) && set.size <= 10
            "exclusion(from: #{set.inspect})"
          else
            "exclusion"
          end
        when ActiveModel::Validations::FormatValidator
          with = validator.options[:with]
          without = validator.options[:without]
          parts = []
          parts << "with: #{with.inspect}" if with
          parts << "without: #{without.inspect}" if without
          parts.any? ? "format(#{parts.join(', ')})" : "format"
        when ActiveModel::Validations::AcceptanceValidator
          "acceptance"
        when ActiveModel::Validations::ConfirmationValidator
          "confirmation"
        when ActiveRecord::Validations::AssociatedValidator
          "associated"
        else
          # Custom validator — use class name
          "custom(#{validator.class.name.demodulize.underscore})"
        end
      end

      ##
      # Extracts conditional options (:if, :unless, :on) from a validator
      # and formats them as a readable suffix string.
      #
      # @param validator [ActiveModel::Validator]
      # @return [String] e.g. " — if: :active?, on: :create" or "" if no conditions.
      def format_conditions(validator)
        parts = []
        if validator.options[:if]
          conditions = Array(validator.options[:if]).map { |c| c.is_a?(Proc) ? "proc{...}" : ":#{c}" }
          parts << "if: #{conditions.join(', ')}"
        end
        if validator.options[:unless]
          conditions = Array(validator.options[:unless]).map { |c| c.is_a?(Proc) ? "proc{...}" : ":#{c}" }
          parts << "unless: #{conditions.join(', ')}"
        end
        if validator.options[:on]
          contexts = Array(validator.options[:on]).map { |c| ":#{c}" }
          parts << "on: #{contexts.join(', ')}"
        end
        parts << "allow_nil" if validator.options[:allow_nil] && !validator.is_a?(ActiveModel::Validations::NumericalityValidator)
        parts << "allow_blank" if validator.options[:allow_blank]
        parts.any? ? " — #{parts.join(', ')}" : ""
      end

      ##
      # Formats a column's default value for annotation output based on its database type.
      #
      # Strings are wrapped in quotes, booleans are normalized to true/false,
      # and all other types are returned as-is.
      #
      # @param column [ActiveRecord::ConnectionAdapters::Column]
      # @return [String, Object] Formatted default value suitable for annotations.
      def format_default(column)
        value = column.default
        case column.type
        when :string, :text
          %("#{value}")
        when :boolean
          value.to_s
        else
          value
        end
      end

      ##
      # Formats a database column comment for inclusion in model annotations.
      #
      # Returns a prefixed, indented comment line or nil if no comment exists.
      #
      # @param column [ActiveRecord::ConnectionAdapters::Column]
      # @return [String, nil] Formatted annotation comment line.
      def format_column_comment(column)
        return nil if column.comment.blank?
        "   ^^ comment: #{column.comment}"
      end

    end
  end

end
