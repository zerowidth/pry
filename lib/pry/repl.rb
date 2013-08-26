require 'forwardable'

class Pry
  class REPL
    include Pry::REPL::Basic
    include Pry::REPL::ErrorHandling
    include Pry::REPL::Indentation

    extend Forwardable
    def_delegators :@pry, :input, :output

    # @return [Pry] The instance of {Pry} that the user is controlling.
    attr_accessor :pry

    # Instantiate a new {Pry} instance with the given options, then start a
    # {REPL} instance wrapping it.
    # @option options See {Pry#initialize}
    def self.start(options)
      new(Pry.new(options)).start
    end
  end
end
