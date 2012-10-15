class Pry
  class SourceExporter
    class MethodExporter
      
      attr_accessor :method_object
      attr_reader :target_module
      
      def initialize(method_object, candidate_rank=0)
        @method_object = method_object

        owner_or_receiver = method_object.singleton_method? ? :receiver : :owner
        @mod = Pry::WrappedModule(method_object.send(owner_or_receiver))
      end

      def generated_code
        if method_object.pry_method?
          return @generated_code if @generated_code

          @generated_code = if method_location = check_for_previous_definition
                              replace_prior_method(method_location)
                            else
                              add_new_method
                            end
        else
          raise Pry::CommandError, "This method already has an associated file, does not make sense to export, bish."
        end 
      end

      def diff(code=nil)
        Diffy::Diff.new(@original_file, code || generated_code).to_s
      end

      def export!(code=nil)
        File.open(target_module.file, "w") { |v| v.write(code || @generated_code) }

        if code
          load target_module.file
        else
          target_module.module_eval adjusted_code, target_module.file, insertion_point + 1
        end
      end

      def replacement_method?
        !!check_for_previous_definition
      end

      def target_file_content
        generated_code
        @original_file
      end

      private
      
      def setup_for_target_candidate(candidate)
        @target_module = candidate
        @original_file = File.read(target_module.file) 
        @file_buffer   = @original_file.lines.to_a
      end

      def inject_method_code_at(line)
        @file_buffer.insert(line, *indented_code(line).lines.to_a)
        @file_buffer.join        
      end

      def add_new_method
        setup_for_target_candidate(find_first_valid_candidate)
        inject_method_code_at default_insertion_point
      end

      def replace_prior_method(method_location)
        candidate, line = method_location
        setup_for_target_candidate(candidate)
        remove_method_at(line)
        inject_method_code_at (line - 1)
      end

      def remove_method_at(line)
        size = Pry::Code.new(@file_buffer).expression_at(line).lines.count
        @file_buffer.slice!(line - 1, size) 
      end

      def check_for_previous_definition
        return @previous_definition if @previous_definition
        
        @mod.candidates.each do |v|
          begin
            v.source.lines.each_with_index do |line, index|
              if File.exists?(v.file.to_s) && method_definition?(line.strip)
                return @previous_definition = [v, index + v.line]
              end
            end
          rescue Pry::CommandError
          end
        end

        @previous_definition = false
      end

      def method_definition?(line)
        if method_object.singleton_method?
          singleton_method_definition?(line)
        else
          normal_method_definition?(line)
        end
      end

      def singleton_method_definition?(line)
        /^define_singleton_method\(?\s*[:\"\']#{method_object.name}|^def\s*self\.#{method_object.name}/ =~ line
      end

      def normal_method_definition?(line)
        /^define_method\(?\s*[:\"\']#{method_object.name}|^def\s*#{method_object.name}/ =~ line
      end

      def indented_code(insertion_point)
        adjusted_code.lines.map do |v|
          "#{previous_code_indentation(insertion_point)}#{v}"
        end.join
      end

      def find_first_valid_candidate
        @mod.candidates.each do |c|
          return c if File.exists?(c.file.to_s)
        end
        
        raise Pry::CommandError, "Could not find valid file to export to!"
      end

      def adjusted_code
        return @adjusted_code if @adjusted_code
        return method_object.source if !method_object.singleton_method?
        return method_object.source if method_object.source.lines.first =~ /^def self\.|^define_singleton_method/

        line = method_object.source.lines.first
        @adjusted_code = if line =~ /^def #{Regexp.escape(method_object.name)}(?=[\(\s;]|$)/
                           src = method_object.source.lines.to_a
                           src[0] = "def self.#{method_object.name}#{$'}"
                           src.join
                         elsif line =~ /^define_method/
                           method_object.source.sub /^define_method/, "define_singleton_method"
                         else
                           method_object.source
                         end
      end

      def previous_code_indentation(insertion_point)
        search_buffer = @file_buffer[(target_module.line - 1)..(insertion_point - 1)]
        idx = search_buffer.rindex do |line|
          !line.strip.empty?
        end

        search_buffer[idx] =~ /^(\s+)/
        $1 ? $1 : ""
      end

      # We insert the new code one line before the end of the module definition
      def default_insertion_point
        target_module.line + target_module.source.lines.count  - 2
      end
    end
  end
end
