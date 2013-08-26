class Pry
  class REPL
    module ErrorHandling
      def read(*)
        with_error_handling do
          super
        end
      end

      private

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
  end
end
