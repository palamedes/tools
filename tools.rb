module Ellis
  class Tools
    class << self

      # Look at a given model in console and give an output of the model attributes.
      # It also copies this to the clipboard
      # Usage in console:
      #  load '/{path to file}/tools.rb'
      #  Ellis::Tools.annotate [Model], *options
      #
      # Example:
      #  Ellis::Tools.annotate User, to_file: true
      #
      # Options:
      #  to_clipboard: true|false   Default: true   Copies the output to the clipboard
      #  to_screen: true|false      Default: true   Pastes the output to the screen
      #  to_file: true|false        Default: false  Appends the output to the model file
      #
      def annotate target, args = {}
        defaults = {
          to_clipboard: true,
          to_screen: true,
          to_file: false
        }
        options = defaults.merge args

        spc = longest_column_name_length(target) + 3

        res = []

        res << "# --- Model: '#{ActiveModel::Name.new(target).to_s}' Annotation"
        res << "# Table Name: #{target.table_name}"
        res << "#"
        columns = target.columns.sort_by(&:name)

        created_at = ""
        updated_at = ""

        columns.each do |col|
          next unless col.name == target.primary_key
          type_limit = col.limit.present? ? "#{col.type}(#{col.limit})" : "#{col.type}"

          opts = []
          opts << "Primary Key"
          opts << "default(#{col.default})" if col.default.present?
          opts << "not null" unless col.null

          res << "#  #{col.name.ljust(spc)}:#{type_limit.ljust(15)}#{opts.compact.join(', ')}"
        end

        res << "#"
        columns.each do |col|
          next if col.name == target.primary_key
          type_limit = col.limit.present? ? "#{col.type}(#{col.limit})" : "#{col.type}"

          opts = []
          opts << "default(#{col.default})" if col.default.present?
          opts << "not null" unless col.null

          line = "#  #{col.name.ljust(spc)}:#{type_limit.ljust(15)}#{opts.compact.join(', ')}"

          created_at = line if col.name == 'created_at'
          updated_at = line if col.name == 'updated_at'

          res << line unless col.name == 'created_at' or col.name == 'updated_at'
        end

        if !created_at.empty? || !updated_at.empty?
          res << "#"
          res << created_at
          res << updated_at
        end

        puts "--- Model Annotation ---" if options[:to_screen]
        puts res if options[:to_screen]
        puts "---" if options[:to_screen] && !options[:to_clipboard]

        puts "--- Copied to clipboard ---" if options[:to_clipboard]
        pbcopy res if options[:to_clipboard]

        puts "--- Appended to file ---" if options[:to_file]
        write_to_file target, res if options[:to_file]
      end







      # ---- RANDOM CRAP BELOW

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

      # def get_object_array obj
      #   res = []
      #   obj.all.each do |o|
      #     res << o.attributes
      #   end
      #   resg
      # end
      #
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

      def get_attribute_keys model
        keys = []
        columns = model.columns.sort_by(&:name)
        columns.each do |col|
          keys << col.name
        end
        keys
      end


      private

      # Copy to Clipboard
      def pbcopy arg
        IO.popen('pbcopy', 'w') { |io| io.puts arg }
      end

      # Get the longest column name
      def longest_column_name_length target
        target.column_names.sort_by(&:length).last.length
      end

      # Copy to End of File
      def write_to_file target, arg
        model_file = target.name.split("::").map {|c| c.downcase }.join('/') + '.rb'
        file_path = Rails.root.join('app/models/').join(model_file)
        File.open(file_path, "a") { |f| f.puts arg }
      end

    end
  end

end

