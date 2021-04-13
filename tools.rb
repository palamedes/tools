module Ellis
  class Tools
    class << self
      
      def annotate target
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
          typeLimit = col.limit.present? ? "#{col.type}(#{col.limit})" : "#{col.type}"

          options = []
          options << "Primary Key"
          options << "default(#{col.default})" if col.default.present?
          options << "not null" unless col.null

          res << "#  #{col.name.ljust(spc)}:#{typeLimit.ljust(15)}#{options.compact.join(', ')}"
        end

        res << "#"
        columns.each do |col|
          next if col.name == target.primary_key
          typeLimit = col.limit.present? ? "#{col.type}(#{col.limit})" : "#{col.type}"

          options = []
          options << "default(#{col.default})" if col.default.present?
          options << "not null" unless col.null

          line = "#  #{col.name.ljust(spc)}:#{typeLimit.ljust(15)}#{options.compact.join(', ')}"

          created_at = line if col.name == 'created_at'
          updated_at = line if col.name == 'updated_at'

          res << line unless col.name == 'created_at' or col.name == 'updated_at'
        end

        if !created_at.empty? || !updated_at.empty?
          res << "#"
          res << created_at
          res << updated_at
        end

        puts "--- Copied to clipboard ---"
        puts res
        puts "---"
        pbcopy res
      end

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

      private

      def pbcopy arg  
        IO.popen('pbcopy', 'w') { |io|
          io.puts arg
        };
      end

      def longest_column_name_length target
        target.column_names.sort_by(&:length).last.length
      end

    end
  end

end

# Load in console:
# load '/Users/jasonellis/Sites/Tools/tools.rb'
