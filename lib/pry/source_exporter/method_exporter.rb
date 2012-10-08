class Pry
  class SourceExporter
    class MethodExporter
      attr_accessor :method_object
      attr_reader :target_module
      
      def initialize(method_object, candidate_rank=0)
        @method_object = method_object
        @target_module = Pry::WrappedModule(method_object.owner).candidate(candidate_rank)
        @original_file = File.read(target_module.file)
        @file_buffer = @original_file.lines.to_a
      end

      def generated_code
        if method_object.pry_method?
          return @generated_code if @generated_code

          @file_buffer.insert(insertion_point, *indented_code.lines.to_a)
          @generated_code = @file_buffer.join
        else
          raise Pry::CommandError, "This method already has an associated file, does not make sense to export, bish."
        end 
      end

      def diff
        Diffy::Diff.new(@original_file, generated_code)
      end

      def export
        raise Pry::CommandError, "Not yet implemented."
      end

      def indented_code
        method_object.source.lines.map do |v|
          "#{previous_code_indentation}#{v}"
        end.join
      end

      def previous_code_indentation
        search_buffer = @file_buffer[(target_module.line - 1)..(insertion_point - 1)]
        idx = search_buffer.rindex do |line|
          !line.strip.empty?
        end

        search_buffer[idx] =~ /^(\s+)/
        $1 ? $1 : ""
      end

      # We insert the new code one line before the end of the module definition
      def insertion_point
        target_module.line + target_module.source.lines.count  - 2
      end
    end
  end
end
