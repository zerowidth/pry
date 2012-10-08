require 'pry/source_exporter/method_exporter'

class Pry
  class SourceExporter
    def self.for(code_object, candidate_rank=0)
      case code_object
      when Pry::Method
        MethodExporter.new(code_object, candidate_rank)
      when Pry::WrappedModule
        raise Pry::CodeError, "Not implemented yet!"
      end
    end
  end
end
