require 'pry/source_exporter'

class Pry
  Pry::Commands.create_command "save-source" do
    extend  Pry::Helpers::BaseHelpers

    group 'Introspection'
    description "Save the source for a method or class."

    banner <<-BANNER
      Usage: save-source [OPTIONS] [METH|CLASS]
      Aliases: $, show-method

      Show the source for a method or class. Tries instance methods first and then methods by default.

      e.g: `show-source hello_method`
      e.g: `show-source -m hello_method`
      e.g: `show-source Pry#rep`         # source for Pry#rep method
      e.g: `show-source Pry`             # source for Pry class
      e.g: `show-source Pry -a`          # source for all Pry class definitions (all monkey patches)
      e.g: `show-source Pry --super      # source for superclass of Pry (Object class)

      https://github.com/pry/pry/wiki/Source-browsing#wiki-Show_method
    BANNER

    options :shellwords => false

    required_gems = ["diffy"]
    required_gems << "ruby18_source_location" if mri_18?
    options :requires_gem => required_gems

    def setup
      require 'ruby18_source_location' if mri_18?
      require 'diffy'
    end

    def process
      @code_object = retrieve_code_object_from_string(arg_string, target)
      case @code_object
      when Pry::Method
        save_method
      when Pry::WrappedModule
        save_module
      else
        raise Pry::CommandError, "#{arg_string} is not a valid method or class/module"
      end
    end

    def save_method
      exporter = SourceExporter.for(@code_object, 0)
      show_diff(exporter)
      confirm_export(exporter)
    end

    def confirm_export(exporter)
      output.puts "If you are happy with the changes, press y<enter> to write the code to disk."
      answer = $stdin.gets.to_s.chomp
      if answer.upcase == "Y"
        exporter.export!
      else
        output.puts "Changes not saved."
      end
    end

    def show_diff(exporter)
      text_size = @code_object.source.lines.count

      # FIXME
      # this is a workaround for a fucking bug in Diffy
      # without this line it puts + before EVERY line in the diff 
      exporter.diff.to_s
      
      out = %{
#{text.bold("Export diff for #{arg_string} method is: ")}
---

..clipped..
#{colorize_code exporter.diff.lines.to_a.last(text_size + 10).join}
}
      stagger_output out
    end
  end
end
