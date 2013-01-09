class Pry
  class REPL
    module Indentation
      def initialize(*)
        super
        @indent = Pry::Indent.new
      end

      def read(prompt)
        @indent.reset if pry.eval_string.empty?

        indentation = Pry.config.auto_indent ? @indent.current_prefix : ''

        line = super("#{prompt}#{indentation}")

        if line.is_a? String
          fix_indentation(line, prompt, indentation)
        else
          # nil for EOF, :no_more_input for error, or :control_c for <Ctrl-C>
          line
        end
      end

      private

      def fix_indentation(line, prompt, indentation)
        if Pry.config.auto_indent
          original_line = "#{indentation}#{line}"
          indented_line = @indent.indent(line)

          if output.tty? && @indent.should_correct_indentation?
            output.print @indent.correct_indentation(
              prompt, indented_line,
              original_line.length - indented_line.length
            )
            output.flush
          end

          indented_line
        else
          line
        end
      end
    end
  end
end
