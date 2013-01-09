class Pry
  class REPL
    module Basic
      # Create an instance of {REPL} wrapping the given {Pry}.
      # @param [Pry] pry The instance of {Pry} that this {REPL} will control.
      # @param [Hash] options Options for this {REPL} instance.
      # @option options [Object] :target The initial target of the session.
      def initialize(pry, options = {})
        @pry = pry

        if options[:target]
          @pry.push_binding options[:target]
        end
      end

      # Start the read-eval-print loop.
      # @return [Object?] If the session throws `:breakout`, return the value
      #   thrown with it.
      # @raise [Exception] If the session throws `:raise_up`, raise the
      #   exception thrown with it.
      def start
        prologue
        Pry::InputLock.for(:all).with_ownership { repl }
      ensure
        epilogue
      end

      private

      # Set up the repl session.
      # @return [void]
      def prologue
        pry.exec_hook :before_session, pry.output, pry.current_binding, pry

        # Clear the line before starting Pry. This fixes issue #566.
        if Pry.config.correct_indent
          Kernel.print Pry::Helpers::BaseHelpers.windows_ansi? ? "\e[0F" : "\e[0G"
        end
      end

      # The actual read-eval-print loop.
      #
      # The {REPL} instance is responsible for reading and looping, whereas the
      # {Pry} instance is responsible for evaluating user input and printing
      # return values and command output.
      #
      # @return [Object?] If the session throws `:breakout`, return the value
      #   thrown with it.
      # @raise [Exception] If the session throws `:raise_up`, raise the
      #   exception thrown with it.
      def repl
        loop do
          case line = read(pry.select_prompt)
          when :control_c
            advance_cursor
            pry.reset_eval_string
          when :no_more_input
            advance_cursor
            break
          else
            advance_cursor if line.nil?
            return pry.exit_value unless pry.eval(line)
          end
        end
      end

      # Advance the cursor to the next line if the output is a TTY.
      def advance_cursor
        output.puts "" if output.tty?
      end

      # Clean up after the repl session.
      # @return [void]
      def epilogue
        pry.exec_hook :after_session, pry.output, pry.current_binding, pry
      end

      # Return the next line of input to be sent to the {Pry} instance.
      # @param [String] prompt The prompt to use for input.
      # @return [nil] On `<Ctrl-D>`.
      # @return [:control_c] On `<Ctrl+C>`.
      # @return [:no_more_input] On EOF.
      def read(prompt)
        with_error_handling do
          set_completion_proc

          if input == Readline
            if !$stdout.tty? && $stdin.tty? && !Pry::Helpers::BaseHelpers.windows?
              Readline.output = File.open('/dev/tty', 'w')
            end
            input_readline(prompt, false) # false since we'll add it manually
          elsif input.method(:readline).arity == 1
            input_readline(prompt)
          else
            input_readline
          end
        end
      end

      # Wrap the given block with our default error handling ({handle_eof},
      # {handle_interrupt}, and {handle_read_errors}).
      def with_error_handling
        handle_read_errors do
          handle_interrupt do
            handle_eof do
              yield
            end
          end
        end
      end

      # Set the default completion proc, if applicable.
      def set_completion_proc
        if input.respond_to? :completion_proc=
          input.completion_proc = proc do |input|
            @pry.complete input
          end
        end
      end

      # Manage switching of input objects on encountering `EOFError`s.
      # @return [Object] Whatever the given block returns.
      # @return [:no_more_input] Indicates that no more input can be read.
      def handle_eof
        should_retry = true

        begin
          yield
        rescue EOFError
          pry.input = Pry.config.input

          if should_retry
            should_retry = false
            retry
          else
            output.puts "Error: Pry ran out of things to read from! " \
              "Attempting to break out of REPL."
            return :no_more_input
          end
        end
      end

      # Handle `Ctrl-C` like Bash: empty the current input buffer, but don't
      # quit.  This is only for MRI 1.9; other versions of Ruby don't let you
      # send Interrupt from within Readline.
      # @return [Object] Whatever the given block returns.
      # @return [:control_c] Indicates that the user hit `Ctrl-C`.
      def handle_interrupt
        yield
      rescue Interrupt
        return :control_c
      end

      # Deal with any random errors that happen while trying to get user input.
      # @return [Object] Whatever the given block returns.
      # @return [:no_more_input] Indicates that no more input can be read.
      def handle_read_errors
        exception_count = 0

        begin
          yield
        # If we get a random error when trying to read a line we don't want to
        # automatically retry, as the user will see a lot of error messages
        # scroll past and be unable to do anything about it.
        rescue RescuableException => e
          puts "Error: #{e.message}"
          output.puts e.backtrace
          exception_count += 1
          if exception_count < 5
            retry
          end
          puts "FATAL: Pry failed to get user input using `#{input}`."
          puts "To fix this you may be able to pass input and output file " \
            "descriptors to pry directly. e.g."
          puts "  Pry.config.input = STDIN"
          puts "  Pry.config.output = STDOUT"
          puts "  binding.pry"
          return :no_more_input
        end
      end
    end

    def input_readline(*args)
      Pry::InputLock.for(:all).interruptible_region do
        input.readline(*args)
      end
    end
  end
end
