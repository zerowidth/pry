require 'pry/helpers/documentation_helpers'
require 'forwardable'

class Pry
  class WrappedModule

    # This class represents a single candidate for a module/class definition.
    # It provides access to the source, documentation, line and file
    # for a monkeypatch (reopening) of a class/module.
    class Candidate
      extend Forwardable

      # @return [String] The file where the module definition is located.
      attr_reader :file

      # @return [Fixnum] The line where the module definition is located.
      attr_reader :line

      # Methods to delegate to associated `Pry::WrappedModule instance`.
      to_delegate = [:lines_for_file, :method_candidates, :name, :wrapped,
                     :yard_docs?, :number_of_candidates, :process_doc,
                     :strip_leading_whitespace, :respond_to?]

      def_delegators :@wrapper, *to_delegate
      private(*to_delegate)

      def method_missing(*args, &block)
        @wrapper.send(*args, &block)
      end
      
      # @raise [Pry::CommandError] If `rank` is out of bounds.
      # @param [Pry::WrappedModule] wrapper The associated
      #   `Pry::WrappedModule` instance that owns the candidates.
      # @param [Fixnum] rank The rank of the candidate to
      #   retrieve. Passing 0 returns 'primary candidate' (the candidate with largest
      #   number of methods), passing 1 retrieves candidate with
      #   second largest number of methods, and so on, up to
      #   `Pry::WrappedModule#number_of_candidates() - 1`
      def initialize(wrapper, rank)
        @wrapper = wrapper

        if number_of_candidates <= 0
          raise CommandError, "Cannot find a definition for #{name} module!"
        elsif rank > (number_of_candidates - 1)
          raise CommandError, "No such module candidate. Allowed candidates range is from 0 to #{number_of_candidates - 1}"
        end

        @rank = rank
        @file, @line = source_location
      end

      # @raise [Pry::CommandError] If source code cannot be found.
      # @return [String] The source for the candidate, i.e the
      #   complete module/class definition.
      def source
        return @source if @source
        raise CommandError, "Could not locate source for #{wrapped}!" if file.nil?

        @source = strip_leading_whitespace(Pry::Code.from_file(file).expression_at(line, number_of_lines_in_first_chunk))
        @source
      end

      # @raise [Pry::CommandError] If documentation cannot be found.
      # @return [String] The documentation for the candidate.
      def doc
        return @doc if @doc
        raise CommandError, "Could not locate doc for #{wrapped}!" if file.nil?

        @doc = process_doc(Pry::Code.from_file(file).comment_describing(line))
      end

      # @return [Array, nil] A `[String, Fixnum]` pair representing the
      #   source location (file and line) for the candidate or `nil`
      #   if no source location found.
      def source_location
        return @source_location if @source_location

        mod_type_string = wrapped.class.to_s.downcase
        file, line = first_method_source_location

        return nil if !file.is_a?(String)

        host_file_lines = lines_for_file(file)

        search_lines = host_file_lines[0..(line - 2)]
        idx = search_lines.rindex { |v| start_of_class_definition?(v) }

        @source_location = [file,  idx + 1]
      rescue Pry::RescuableException
        nil
      end

      private

      # This method is used by `Candidate#source_location` as a
      # starting point for the search for the candidate's definition.
      # @return [Array] The source location of the base method used to
      #   calculate the source location of the candidate.
      def first_method_source_location
        @first_method_source_location ||= adjusted_source_location(method_candidates[@rank].first.source_location)
      end

      # @return [Array] The source location of the last method in this
      #   candidate's module definition.
      def last_method_source_location
        @last_method_source_location ||= adjusted_source_location(method_candidates[@rank].last.source_location)
      end

      # Return the number of lines between the start of the class definition
      # and the start of the last method. We use this value so we can
      # quickly grab these lines from the file (without having to
      # check each intervening line for validity, which is expensive) speeding up source extraction.
      # @return [Fixum] Number of lines.
      def number_of_lines_in_first_chunk
        end_method_line = last_method_source_location.last

        end_method_line - line
      end

      def start_of_class_definition?(line)
        class_regexes.any? { |r| r =~ line }
      end

      def class_regexes
        mod_type_string = wrapped.class.to_s.downcase
        
        [/^\s*#{mod_type_string}\s*(\w*)(::)?#{wrapped.name.split(/::/).last}/,
         /^\s*(::)?#{wrapped.name.split(/::/).last}\s*?=\s*?#{wrapped.class}/,
         /^\s*(::)?#{wrapped.name.split(/::/).last}\.(class|instance)_eval/]
      end

      def adjusted_source_location(sl)
        file, line = sl

        if file && RbxPath.is_core_path?(file)
          file = RbxPath.convert_path_to_full(file)
        end

        [file, line]
      end

      def extract_multiple_module_definitions(code)
        code.lines.map.with_index do |line, index|
          start_of_class_definition?(line) ? Pry::Code.new(code).expression_at(index + 1).to_s : nil
        end.compact
      end

      def remove_overridden_methods(code)
        pry_methods = all_methods.select(&:pry_method?)
        lines = code.lines.to_a

        offset = 0
        while idx = lines.find_index { |line| method_definition?(line) }
          if pry_methods.none? { |v| v.source_location.last == line + idx - offset }
            method_length = Pry::Code.new(lines).expression_at(idx + 1).lines.count
            lines.slice!(idx, method_length)
            offset += method_length
          end
        end

        lines.join
      end

      def merge_module_definitions(code)
        definitions = extract_multiple_module_definitions(code)

        definitions = definitions.map { |definition| remove_all_methods(definition) }
        
        if definitions.size > 1
          mods = definitions[1..-1].map do |definition|
            definition.lines.to_a[1..-2].join
          end.join("\n")

          definitions[0].lines.to_a.insert(-2, *mods).join
        else
          definitions.first
        end
      end

      def method_definition?(line)
        /\s*define_(?:singleton_)?method\(?\s*[:\"\']|\s*def\s+/=~ line
      end

      def remove_all_methods(definition)
        lines = definition.lines.to_a

        while idx = lines.find_index { |line, index| method_definition?(line) }
          method_length = Pry::Code.new(lines).expression_at(idx + 1).lines.count
          lines.slice!(idx, method_length) 
        end

        lines.join
      end

      def inject_all_pry_methods(definition)
        all_methods.select { |v| v.pry_method? }        
      end
      
    end
  end
end
